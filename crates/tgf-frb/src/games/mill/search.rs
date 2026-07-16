// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill search-event spawn helpers used by the FRB streaming entry points.
//
// This module owns every piece of Mill-specific search wiring that used
// to live inline in `crate::api::simple`:
//
//   * Default `Searcher<MillGame>` factory (qsearch policy etc.).
//   * Move-order context construction for MCTS / shuffle seeds.
//   * `EngineRuntimeOptions` selection of the recommended depth.
//   * The PVS / MTD(f) / α-β / MCTS / random algorithm dispatch and
//     `EngineEvent` stream emission.
//
// `crate::api::simple` and `crate::api::kernel` both delegate to the
// public `spawn_with_*` functions here so the FRB entry points remain
// thin and game-neutral structurally.

use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
#[cfg(not(target_arch = "wasm32"))]
use std::thread;
use std::time::{Duration, Instant};

use once_cell::sync::Lazy;

use tgf_core::{
    Action, ActionList, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext,
    SEARCH_ACTION_CAPACITY, SearchActionList, Workbench,
};
use tgf_mill::{
    EngineRuntimeOptions, MillActionKind, MillGame, MillRules, MillSearchAlgorithmKind,
    MillVariantOptions as NativeMillVariantOptions, recommended_search_depth,
};
#[cfg(test)]
use tgf_mill::{MillPhase, MillState};
#[cfg(target_arch = "wasm32")]
use tgf_search::MctsSearcher;
#[cfg(not(target_arch = "wasm32"))]
use tgf_search::mcts_search_parallel;
use tgf_search::{
    MctsOptions, SearchAbortHandle, SearchAlgorithm, SearchOptions, SearchPolicy, SearchResult,
    Searcher, SharedTt,
};

use crate::engine_event::EngineEvent;
use crate::frb_generated::StreamSink;
use crate::games::mill::action_codec::action_to_uci_str;
use crate::games::mill::perfect;

// ---------------------------------------------------------------------------
// Cancellation handle for the most recent native Mill search worker.
// ---------------------------------------------------------------------------

/// Tracks the currently-running search worker so the FRB
/// `native_mill_search_stop` entry point can request abort without owning
/// a per-call handle.
pub(crate) static ACTIVE_SEARCH: Lazy<Mutex<Option<SearchAbortHandle>>> =
    Lazy::new(|| Mutex::new(None));

static MILL_SHARED_TT: Lazy<SharedTt> = Lazy::new(|| {
    let tt = SharedTt::default();
    // Match master's process-global TT lifecycle: pay physical initialization
    // once, then use fake-clean generation bumps before each search.
    tt.clear();
    tt
});

const ANALYSIS_MULTI_PV_TT_MB: u32 = 16;
const ANALYSIS_MULTI_PV_TT_CLUSTER_BITS_FLOOR: u32 = 14;

// ---------------------------------------------------------------------------
// Mill-specific runtime configuration consumed by the search dispatcher.
//
// The FRB-public `MillEngineConfig` DTO (in `crate::api::simple`) converts
// into [`MillEngineConfigPlan`] before reaching the dispatch loop so
// `crate::api::*` stays thin and the dispatcher does not depend on FRB
// ABI details.  The algorithm enumeration is shared with the rest of the
// crate via [`MillSearchAlgorithmKind`] in `tgf_mill::engine_config`.
// ---------------------------------------------------------------------------

#[inline]
fn algorithm_to_search(kind: MillSearchAlgorithmKind) -> SearchAlgorithm {
    match kind {
        MillSearchAlgorithmKind::AlphaBeta => SearchAlgorithm::AlphaBeta,
        MillSearchAlgorithmKind::Pvs => SearchAlgorithm::Pvs,
        MillSearchAlgorithmKind::Mtdf => SearchAlgorithm::Mtdf,
        MillSearchAlgorithmKind::Mcts => SearchAlgorithm::Mcts,
        MillSearchAlgorithmKind::Random => SearchAlgorithm::Random,
    }
}

fn search_context_for_config(config: &MillEngineConfigPlan) -> MoveOrderContext {
    MoveOrderContext {
        algorithm: match algorithm_to_search(config.algorithm) {
            SearchAlgorithm::AlphaBeta => MoveOrderAlgorithm::AlphaBeta,
            SearchAlgorithm::Pvs => MoveOrderAlgorithm::Pvs,
            SearchAlgorithm::Mtdf => MoveOrderAlgorithm::Mtdf,
            SearchAlgorithm::Mcts => MoveOrderAlgorithm::Mcts,
            SearchAlgorithm::Random => MoveOrderAlgorithm::Random,
        },
        skill_level: config.skill_level,
        shuffling: config.shuffling,
        hash_move: None,
        shuffle_seed: search_shuffle_seed(),
    }
}

/// FRB-internal Mill engine configuration.  Lives next to the dispatch
/// loop so the FRB DTO layer can translate the public `MillEngineConfig`
/// into a typed plan and hand it directly to the worker thread.
#[derive(Clone, Debug)]
pub(crate) struct MillEngineConfigPlan {
    pub algorithm: MillSearchAlgorithmKind,
    pub depth: i32,
    pub move_time_ms: u32,
    pub ai_is_lazy: bool,
    pub last_best_value: i32,
    pub skill_level: u8,
    pub use_perfect_database: bool,
    /// When true and the perfect database drives the move choice, prefer --
    /// among the database's tied-best moves -- the one whose resulting
    /// position carries the highest trap-library score (Flutter "Set traps
    /// for the opponent" with the Perfect Database on). The baseline stays
    /// the plain chooseRandom pick; see
    /// `perfect::try_perfect_best_action_trap_aware`.
    pub patch_make_traps: bool,
    /// Randomise the order of equally-ranked root moves so the AI does not
    /// always pick the same line.  Maps to master's `Shuffling` UCI option;
    /// disable for deterministic play.
    pub shuffling: bool,
    /// Enable multi-threaded native search where supported.  This is gated by
    /// `shuffling` so fixed-position deterministic play remains single-threaded.
    pub use_lazy_smp: bool,
    /// Requested worker/thread count for multi-threaded search.
    pub engine_threads: u32,
    /// Requested MultiPV root line count.  `1` preserves the legacy event
    /// stream and avoids the additional sorting / event emission work.
    pub multi_pv: u8,
}

impl Default for MillEngineConfigPlan {
    fn default() -> Self {
        Self {
            algorithm: MillSearchAlgorithmKind::Mtdf,
            depth: 1,
            move_time_ms: 0,
            ai_is_lazy: false,
            last_best_value: 0,
            skill_level: 1,
            use_perfect_database: false,
            patch_make_traps: false,
            shuffling: true,
            use_lazy_smp: false,
            engine_threads: 4,
            multi_pv: 1,
        }
    }
}

pub(crate) fn perfect_move_ordering(
    config: &MillEngineConfigPlan,
) -> perfect_db::PerfectMoveOrdering {
    if config.algorithm == MillSearchAlgorithmKind::Random && !config.ai_is_lazy {
        perfect_db::PerfectMoveOrdering::StrictSteps
    } else {
        perfect_db::PerfectMoveOrdering::LegacyWdl
    }
}

// ---------------------------------------------------------------------------
// Searcher / move-ordering helpers
// ---------------------------------------------------------------------------

/// Construct a `Searcher<MillGame>` configured with the Mill removal
/// qsearch policy.  Used by every native_mill_* smoke entry point.
pub(crate) fn mill_searcher_default() -> Searcher<MillGame> {
    let mut s = Searcher::with_shared_tt(MILL_SHARED_TT.clone());
    s.clear_tt();
    configure_mill_searcher_defaults(&mut s);
    s
}

fn mill_searcher_for_config(config: &MillEngineConfigPlan) -> Searcher<MillGame> {
    let mut searcher = if config.multi_pv > 1 {
        mill_searcher_with_shared_tt(SharedTt::with_capacity_mb_and_tt_move(
            ANALYSIS_MULTI_PV_TT_MB,
            ANALYSIS_MULTI_PV_TT_CLUSTER_BITS_FLOOR,
            true,
        ))
    } else {
        mill_searcher_default()
    };
    searcher.set_root_move_summaries_enabled(config.multi_pv > 1);
    searcher
}

fn mill_searcher_with_shared_tt(shared_tt: SharedTt) -> Searcher<MillGame> {
    let mut s = Searcher::with_shared_tt(shared_tt);
    configure_mill_searcher_defaults(&mut s);
    s
}

fn configure_mill_searcher_defaults(s: &mut Searcher<MillGame>) {
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s.set_options(mill_base_search_options());
}

/// Whether this build enables full TT prefetch for the Mill engine.
///
/// Prefetch is a measured, node-preserving win on modern desktop CPUs (see the
/// engine-performance-audit skill: ~+50% IPC / ~-33% cycles on a Zen4 part).
/// Mobile targets (Android/iOS, ARM) and wasm stay off pending per-device
/// validation: their cache hierarchies and TT sizes differ, and a `key_after`
/// hint buys nothing on wasm where `TT::prefetch` is a no-op. `MillGame`'s
/// `key_after` is an O(1) incremental-Zobrist hint, which is exactly the
/// precondition documented on `SearchOptions::enable_prefetch`.
pub(crate) const MILL_PREFETCH: bool = cfg!(not(any(
    target_os = "android",
    target_os = "ios",
    target_arch = "wasm32"
)));

/// Base [`SearchOptions`] for the Mill engine: identical to the searcher
/// default except that desktop builds enable full TT prefetch. Use this
/// instead of `SearchOptions::default()` at every Mill search-setup site so the
/// prefetch policy lives in exactly one place.
pub(crate) fn mill_base_search_options() -> SearchOptions {
    SearchOptions {
        enable_prefetch: MILL_PREFETCH,
        prefetch_all: MILL_PREFETCH,
        ..SearchOptions::default()
    }
}

/// Move-order context used for the MCTS path.
pub(crate) fn mcts_move_order_context(skill_level: u8, shuffling: bool) -> MoveOrderContext {
    MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mcts,
        skill_level,
        shuffling,
        hash_move: None,
        shuffle_seed: search_shuffle_seed(),
    }
}

/// Time-seeded RNG for root shuffle and random search.  Mirrors the
/// `rand() + time()` recipe used by the legacy C++ engine.
pub(crate) fn search_shuffle_seed() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

fn configured_search_options(
    config: &MillEngineConfigPlan,
    search_context: MoveOrderContext,
) -> SearchOptions {
    SearchOptions {
        time_limit_ms: if config.move_time_ms > 0 {
            Some(config.move_time_ms as u64)
        } else {
            None
        },
        move_order_context: search_context,
        ..mill_base_search_options()
    }
}

fn remaining_time_limit_ms(move_time_ms: u32, elapsed_ms: u128) -> Option<u64> {
    if move_time_ms == 0 {
        return None;
    }
    let remaining = u128::from(move_time_ms).saturating_sub(elapsed_ms);
    Some(remaining as u64)
}

fn nodes_per_second(nodes: u64, elapsed: Duration) -> u64 {
    if nodes == 0 {
        return 0;
    }
    let elapsed_nanos = elapsed.as_nanos();
    if elapsed_nanos == 0 {
        return 0;
    }
    let value = u128::from(nodes)
        .saturating_mul(1_000_000_000)
        .saturating_div(elapsed_nanos);
    value.min(u128::from(u64::MAX)) as u64
}

fn set_iteration_search_options(
    searcher: &mut Searcher<MillGame>,
    config: &MillEngineConfigPlan,
    search_context: MoveOrderContext,
    search_started_at: Instant,
) -> Option<u64> {
    let mut options = configured_search_options(config, search_context);
    let remaining_ms =
        remaining_time_limit_ms(config.move_time_ms, search_started_at.elapsed().as_millis());
    if let Some(remaining_ms) = remaining_ms {
        options.time_limit_ms = Some(remaining_ms);
    }
    searcher.set_options(options);
    remaining_ms
}

fn run_searcher_algorithm(
    searcher: &mut Searcher<MillGame>,
    wb: &mut tgf_mill::MillWorkbench,
    algorithm: MillSearchAlgorithmKind,
    depth: i32,
    first_guess: i32,
) -> SearchResult {
    match algorithm {
        MillSearchAlgorithmKind::AlphaBeta | MillSearchAlgorithmKind::Pvs => {
            // Master routes Algorithm 0 and 1 to Search::search.  Keep the
            // same parity path here; Rust PVS remains available internally.
            searcher.search(wb, depth)
        }
        MillSearchAlgorithmKind::Mtdf => searcher.search_mtdf_with_guess(wb, depth, first_guess),
        MillSearchAlgorithmKind::Mcts | MillSearchAlgorithmKind::Random => {
            SearchResult::default_none()
        }
    }
}

fn run_ab_like_search(
    searcher: &mut Searcher<MillGame>,
    wb: &mut tgf_mill::MillWorkbench,
    config: &MillEngineConfigPlan,
    search_context: MoveOrderContext,
    max_depth: i32,
    mut on_info: impl FnMut(&Searcher<MillGame>, i32, &SearchResult),
) -> SearchResult {
    let mut result = SearchResult::default_none();
    let mut first_guess = 0;
    let search_started_at = Instant::now();
    if config.move_time_ms > 0 {
        for d in 2..max_depth {
            if searcher.was_aborted() {
                break;
            }
            let remaining_ms =
                set_iteration_search_options(searcher, config, search_context, search_started_at);
            if remaining_ms == Some(0) && !result.best_action.is_none() {
                break;
            }
            result = run_searcher_algorithm(searcher, wb, config.algorithm, d, first_guess);
            first_guess = result.score;
            on_info(searcher, d, &result);
        }
    }
    if !searcher.was_aborted() || result.best_action.is_none() {
        let remaining_ms =
            set_iteration_search_options(searcher, config, search_context, search_started_at);
        if remaining_ms == Some(0) && !result.best_action.is_none() {
            return result;
        }
        result = run_searcher_algorithm(searcher, wb, config.algorithm, max_depth, first_guess);
        on_info(searcher, max_depth, &result);
    }
    result
}

fn search_threads_for_config(config: &MillEngineConfigPlan) -> u32 {
    config.engine_threads.clamp(1, 16)
}

fn multi_thread_search_is_allowed(config: &MillEngineConfigPlan) -> bool {
    #[cfg(target_arch = "wasm32")]
    {
        let _ = config;
        false
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        config.multi_pv <= 1
            && config.use_lazy_smp
            && config.shuffling
            && search_threads_for_config(config) > 1
    }
}

const MAX_MULTI_PV_PLIES: usize = 16;

fn multi_pv_limit(config: &MillEngineConfigPlan) -> usize {
    usize::from(config.multi_pv).max(1)
}

fn should_complete_multi_pv_tail(config: &MillEngineConfigPlan) -> bool {
    config.move_time_ms == 0
}

fn validate_root_action_capacity(
    snapshot: &GameStateSnapshot,
    rules: &MillRules,
    config: &MillEngineConfigPlan,
) -> Result<usize, String> {
    if usize::from(config.multi_pv) > SEARCH_ACTION_CAPACITY {
        return Err(format!(
            "requested Multi-PV line count {} exceeds the shared search action capacity {}",
            config.multi_pv, SEARCH_ACTION_CAPACITY
        ));
    }

    let mut legal = ActionList::<256>::default();
    rules.legal_actions(snapshot, &mut legal);
    if legal.len() > SEARCH_ACTION_CAPACITY {
        return Err(format!(
            "unsupported rule position: {} legal root actions exceed the shared search action capacity {}",
            legal.len(),
            SEARCH_ACTION_CAPACITY
        ));
    }
    Ok(legal.len())
}

struct MultiPvEventContext<'a> {
    game: &'a MillGame,
    snapshot: &'a GameStateSnapshot,
    searcher: &'a Searcher<MillGame>,
    root_side_to_move: i8,
    config: &'a MillEngineConfigPlan,
    search_context: MoveOrderContext,
    nodes_per_second: u64,
    complete_tail: bool,
}

fn multi_pv_events(ctx: &MultiPvEventContext<'_>, depth: i32) -> Vec<EngineEvent> {
    if ctx.config.multi_pv <= 1 {
        return Vec::new();
    }

    let mut rows = ctx.searcher.root_moves().to_vec();
    if rows.is_empty() {
        return Vec::new();
    }
    rows.sort_by(|a, b| b.value.cmp(&a.value).then_with(|| b.nodes.cmp(&a.nodes)));

    let mut events = Vec::<EngineEvent>::new();
    let mut emitted = Vec::<Action>::new();
    for row in rows {
        if emitted.contains(&row.action) {
            continue;
        }
        let notation = action_to_uci_str(row.action);
        let pv_notation = multi_pv_notation(ctx, row.action, depth);
        let rank = emitted.len() + 1;
        events.push(crate::engine_event::principal_variation(
            crate::engine_event::PrincipalVariationEvent {
                rank,
                action: row.action,
                score: row.value,
                root_side_to_move: ctx.root_side_to_move,
                notation: &notation,
                pv_notation: &pv_notation,
                nodes: row.nodes,
                nodes_per_second: ctx.nodes_per_second,
                depth,
                cutoff: row.cutoff,
            },
        ));
        emitted.push(row.action);
        if emitted.len() >= multi_pv_limit(ctx.config) {
            break;
        }
    }
    events
}

fn single_pv_event(
    ctx: &MultiPvEventContext<'_>,
    depth: i32,
    result: &SearchResult,
) -> Option<EngineEvent> {
    if ctx.config.multi_pv != 1 || result.best_action.is_none() {
        return None;
    }

    let action = result.best_action;
    let notation = action_to_uci_str(action);
    let pv_notation = multi_pv_notation(ctx, action, depth);
    Some(crate::engine_event::principal_variation(
        crate::engine_event::PrincipalVariationEvent {
            rank: 1,
            action,
            score: result.score,
            root_side_to_move: ctx.root_side_to_move,
            notation: &notation,
            pv_notation: &pv_notation,
            nodes: result.nodes,
            nodes_per_second: ctx.nodes_per_second,
            depth,
            cutoff: false,
        },
    ))
}

fn multi_pv_notation(ctx: &MultiPvEventContext<'_>, root_action: Action, depth: i32) -> String {
    let mut line = Vec::<String>::new();
    line.push(action_to_uci_str(root_action));
    if root_action.is_none() {
        return line.join(",");
    }

    let mut wb = ctx.game.build_workbench(ctx.snapshot);
    wb.do_move(root_action);
    let max_tail = multi_pv_ply_limit(depth).saturating_sub(1);
    let mut applied = 1_usize;
    for action in ctx.searcher.principal_variation(&mut wb, max_tail) {
        if action.is_none() {
            break;
        }
        wb.do_move(action);
        applied += 1;
        line.push(action_to_uci_str(action));
    }
    if ctx.complete_tail && line.len() < max_tail + 1 {
        // Keep iterative progress cheap; only final PV events synthesize a
        // shallow continuation when TT move hints do not cover the whole line.
        let remaining_tail = max_tail + 1 - line.len();
        applied += append_shallow_pv_tail(
            &mut wb,
            &mut line,
            ctx.config,
            ctx.search_context,
            remaining_tail,
        );
    }
    for _ in 0..applied {
        wb.undo_move();
    }
    line.join(",")
}

fn multi_pv_ply_limit(depth: i32) -> usize {
    (depth.max(1) as usize).min(MAX_MULTI_PV_PLIES)
}

fn append_shallow_pv_tail(
    wb: &mut tgf_mill::MillWorkbench,
    line: &mut Vec<String>,
    config: &MillEngineConfigPlan,
    search_context: MoveOrderContext,
    max_extra_plies: usize,
) -> usize {
    if max_extra_plies == 0 {
        return 0;
    }

    let mut tail_config = config.clone();
    tail_config.depth = 1;
    tail_config.move_time_ms = 0;
    tail_config.multi_pv = 1;
    tail_config.use_lazy_smp = false;

    let mut tail_searcher = Searcher::new();
    configure_mill_searcher_defaults(&mut tail_searcher);
    tail_searcher.set_options(configured_search_options(&tail_config, search_context));

    let mut applied = 0_usize;
    while applied < max_extra_plies && !wb.is_terminal() {
        let result = run_searcher_algorithm(&mut tail_searcher, wb, tail_config.algorithm, 1, 0);
        let action = result.best_action;
        if action.is_none() {
            break;
        }
        let mut legal = SearchActionList::new();
        MillGame::generate_legal_ctx(wb, &mut legal, &search_context);
        if !legal.contains(&action) {
            break;
        }
        wb.do_move(action);
        line.push(action_to_uci_str(action));
        applied += 1;
    }
    applied
}

struct SearchProgressEmitter<'a> {
    game: &'a MillGame,
    snapshot: &'a GameStateSnapshot,
    sink: &'a StreamSink<EngineEvent>,
    root_side_to_move: i8,
    config: &'a MillEngineConfigPlan,
    started_at: Instant,
}

impl SearchProgressEmitter<'_> {
    fn emit(&self, searcher: &Searcher<MillGame>, depth: i32, result: &SearchResult) {
        let current_nodes_per_second = nodes_per_second(result.nodes, self.started_at.elapsed());
        let _ = self
            .sink
            .add(crate::engine_event::info(depth, result.score, result.nodes));
        let ctx = MultiPvEventContext {
            game: self.game,
            snapshot: self.snapshot,
            searcher,
            root_side_to_move: self.root_side_to_move,
            config: self.config,
            search_context: search_context_for_config(self.config),
            nodes_per_second: current_nodes_per_second,
            complete_tail: false,
        };
        if let Some(event) = single_pv_event(&ctx, depth, result) {
            let _ = self.sink.add(event);
        }
        for event in multi_pv_events(&ctx, depth) {
            let _ = self.sink.add(event);
        }
    }
}

fn mix_lazy_smp_worker_seed(seed: u64, worker_index: u64) -> u64 {
    let mut x = seed ^ worker_index.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    x ^ (x >> 31)
}

#[cfg(not(target_arch = "wasm32"))]
struct LazySmpSearchResult {
    depth: i32,
    result: SearchResult,
    pv_event: Option<EngineEvent>,
}

#[cfg(not(target_arch = "wasm32"))]
fn run_lazy_smp_ab_like_search(
    game: &MillGame,
    snapshot: GameStateSnapshot,
    config: &MillEngineConfigPlan,
    base_depth: i32,
    shared_tt: SharedTt,
    abort: Arc<AtomicBool>,
    sink: &StreamSink<EngineEvent>,
) -> LazySmpSearchResult {
    let base_context = search_context_for_config(config);
    let worker_count = search_threads_for_config(config) as usize;
    let mut handles = Vec::with_capacity(worker_count);
    for worker_index in 0..worker_count {
        let worker_game = game.clone();
        let worker_shared_tt = shared_tt.clone();
        let worker_abort = Arc::clone(&abort);
        let mut worker_context = base_context;
        if worker_index > 0 {
            worker_context.shuffle_seed =
                mix_lazy_smp_worker_seed(base_context.shuffle_seed, worker_index as u64);
        }
        let worker_config = config.clone();
        let worker_depth = if config.move_time_ms > 0 {
            base_depth + (worker_index % 2) as i32
        } else {
            base_depth
        }
        .max(1);
        let worker_sink = (worker_index == 0).then(|| sink.clone());
        handles.push(thread::spawn(move || {
            let mut searcher = mill_searcher_with_shared_tt(worker_shared_tt);
            searcher.set_abort_flag(worker_abort);
            searcher.set_options(configured_search_options(&worker_config, worker_context));
            let mut wb = worker_game.build_workbench(&snapshot);
            let worker_started_at = Instant::now();
            let mut completed_depth = 0;
            let result = run_ab_like_search(
                &mut searcher,
                &mut wb,
                &worker_config,
                worker_context,
                worker_depth,
                |progress_searcher, depth, current| {
                    completed_depth = depth;
                    if let Some(progress_sink) = worker_sink.as_ref() {
                        SearchProgressEmitter {
                            game: &worker_game,
                            snapshot: &snapshot,
                            sink: progress_sink,
                            root_side_to_move: snapshot.side_to_move,
                            config: &worker_config,
                            started_at: worker_started_at,
                        }
                        .emit(progress_searcher, depth, current);
                    }
                },
            );
            let completed_depth = completed_depth.max(1);
            let final_ctx = MultiPvEventContext {
                game: &worker_game,
                snapshot: &snapshot,
                searcher: &searcher,
                root_side_to_move: snapshot.side_to_move,
                config: &worker_config,
                search_context: worker_context,
                nodes_per_second: nodes_per_second(result.nodes, worker_started_at.elapsed()),
                complete_tail: false,
            };
            let pv_event = single_pv_event(&final_ctx, completed_depth, &result);
            LazySmpSearchResult {
                depth: completed_depth,
                result,
                pv_event,
            }
        }));
    }

    let mut best: Option<LazySmpSearchResult> = None;
    let mut total_nodes = 0_u64;
    for handle in handles {
        let candidate = handle
            .join()
            .expect("lazy-SMP Mill worker should return a SearchResult");
        total_nodes = total_nodes.saturating_add(candidate.result.nodes);
        if best.as_ref().is_none_or(|current| {
            lazy_smp_result_is_better(
                (candidate.depth, &candidate.result),
                (current.depth, &current.result),
            )
        }) {
            best = Some(candidate);
        }
    }
    let mut best = best.expect("at least one lazy-SMP worker must run");
    best.result.nodes = total_nodes;
    if let Some(event) = best.pv_event.as_mut() {
        event.nodes = total_nodes;
    }
    best
}

#[cfg(not(target_arch = "wasm32"))]
fn lazy_smp_result_is_better(
    candidate: (i32, &SearchResult),
    current: (i32, &SearchResult),
) -> bool {
    let candidate_valid = !candidate.1.best_action.is_none() || candidate.1.draw_reason.is_some();
    let current_valid = !current.1.best_action.is_none() || current.1.draw_reason.is_some();
    if candidate_valid != current_valid {
        return candidate_valid;
    }
    if candidate.0 != current.0 {
        return candidate.0 > current.0;
    }
    candidate.1.score > current.1.score
}

/// Fallback chain mirroring master `SearchEngine::executeSearch`
/// (`src/search_engine.cpp:643-680`) and `tgf-cli` mill UCI
/// (`mill_uci/mod.rs`).  When the primary search (and optional perfect-DB
/// override) still yields `Action::NONE`, retry at depth 4, then pick a
/// random legal move so Flutter does not surface `EngineNoBestMove` for
/// recoverable engine gaps.
///
/// TODO(search-diagnostics): Replace silent fallback with a hard `assert!`
/// and a user-visible error dialog that invites sending an error report
/// when the primary search (and perfect-DB override) still yields MOVE_NONE.
/// Until then, keep the master/UCI depth-4 + random chain so Flutter does
/// not surface `EngineNoBestMove` for recoverable engine gaps.
fn apply_move_none_fallback(
    result: SearchResult,
    snapshot: GameStateSnapshot,
    options: &NativeMillVariantOptions,
) -> SearchResult {
    if !result.best_action.is_none() {
        return result;
    }

    let mut quick_searcher = mill_searcher_default();
    let mut quick_wb = MillGame::new(options.clone()).build_workbench(&snapshot);
    let quick_result = quick_searcher.search(&mut quick_wb, 4);
    if !quick_result.best_action.is_none() {
        return quick_result;
    }

    let mut rand_searcher = mill_searcher_default();
    rand_searcher.set_random_seed(search_shuffle_seed());
    let mut rand_wb = MillGame::new(options.clone()).build_workbench(&snapshot);
    rand_searcher.random_search(&mut rand_wb)
}

// ---------------------------------------------------------------------------
// Spawn helpers
// ---------------------------------------------------------------------------

/// Run PVS at the requested depth on `snapshot` and stream engine events.
/// Used both by the `native_mill_search_events` smoke entry point and by
/// the kernel-handle search variants once they have resolved the snapshot.
pub(crate) fn spawn_mill_pvs_event_stream(
    snapshot: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    options: NativeMillVariantOptions,
    depth: i32,
    sink: StreamSink<EngineEvent>,
) {
    let config = MillEngineConfigPlan {
        depth,
        ..Default::default()
    };
    spawn_mill_engine_config_event_stream(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        config,
        sink,
    );
}

/// Launch a search thread using the full `MillEngineConfig`. Emits one
/// `info` and principal-variation event per IDS depth, then a final
/// `bestMove` + `stopped`.
pub(crate) fn spawn_mill_engine_config_event_stream(
    snapshot: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    options: NativeMillVariantOptions,
    config: MillEngineConfigPlan,
    sink: StreamSink<EngineEvent>,
) {
    #[cfg(not(target_arch = "wasm32"))]
    thread::spawn(move || {
        run_mill_engine_config_event_stream(
            snapshot,
            root_repetition_history,
            root_position_resets_repetition,
            options,
            config,
            sink,
        );
    });

    #[cfg(target_arch = "wasm32")]
    run_mill_engine_config_event_stream(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        config,
        sink,
    );
}

fn run_mill_engine_config_event_stream(
    snapshot: GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    root_position_resets_repetition: bool,
    options: NativeMillVariantOptions,
    config: MillEngineConfigPlan,
    sink: StreamSink<EngineEvent>,
) {
    if sink.add(crate::engine_event::ready()).is_err() {
        return;
    }

    let rules_options = options.clone();
    let rules = MillRules::new(rules_options.clone());
    if let Err(reason) = validate_root_action_capacity(&snapshot, &rules, &config) {
        let _ = sink.add(crate::engine_event::error(&reason));
        let _ = sink.add(crate::engine_event::stopped());
        return;
    }
    let mut game = MillGame::new_with_repetition_context(
        options,
        root_repetition_history,
        root_position_resets_repetition,
    );
    if let Some(weights) = tgf_mill::MillEvalWeights::from_env() {
        game.set_eval_weights(weights);
    }
    let mut wb = game.build_workbench(&snapshot);
    let mut searcher = mill_searcher_for_config(&config);
    let abort = Arc::new(AtomicBool::new(false));
    let search_context = search_context_for_config(&config);
    searcher.set_abort_flag(Arc::clone(&abort));
    searcher.set_options(configured_search_options(&config, search_context));

    {
        let mut active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
        *active = Some(searcher.abort_handle());
    }

    let requested_depth = if config.depth > 0 {
        config.depth
    } else {
        let state = MillRules::decode_snapshot(snapshot);
        let runtime = EngineRuntimeOptions {
            skill_level: config.skill_level,
            draw_on_human_experience: true,
            developer_mode: true,
        };
        recommended_search_depth(&state, rules.options(), &runtime).max(1)
    };

    // P2-G: AiIsLazy depth adjustment mirroring master executeSearch.
    // np = lastBestValue / VALUE_EACH_PIECE (5); if np > 1 the position
    // is clearly winning from the root side-to-move perspective, so cap
    // origin_depth to 1 or 4.  Do not use abs(): losing positions must
    // not make the AI lazy.
    const VALUE_EACH_PIECE: i32 = 5;
    let origin_depth = if config.ai_is_lazy {
        let np = config.last_best_value / VALUE_EACH_PIECE;
        if np > 1 {
            if requested_depth < 4 { 1 } else { 4 }
        } else {
            requested_depth.max(1)
        }
    } else {
        requested_depth.max(1)
    };
    let max_depth = origin_depth;

    let search_started_at = Instant::now();
    let mut result = match algorithm_to_search(config.algorithm) {
        SearchAlgorithm::Random => {
            // Use time-seeded random to match master's rand()+time() behaviour.
            let seed = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(42);
            searcher.set_random_seed(seed);
            let result = searcher.random_search(&mut wb);
            let _ = sink.add(crate::engine_event::info(1, result.score, result.nodes));
            result
        }
        SearchAlgorithm::AlphaBeta | SearchAlgorithm::Pvs | SearchAlgorithm::Mtdf => {
            let progress = SearchProgressEmitter {
                game: &game,
                snapshot: &snapshot,
                sink: &sink,
                root_side_to_move: snapshot.side_to_move,
                config: &config,
                started_at: search_started_at,
            };
            if multi_thread_search_is_allowed(&config) {
                #[cfg(not(target_arch = "wasm32"))]
                {
                    let lazy_result = run_lazy_smp_ab_like_search(
                        &game,
                        snapshot,
                        &config,
                        max_depth,
                        searcher.shared_tt(),
                        Arc::clone(&abort),
                        &sink,
                    );
                    let _ = sink.add(crate::engine_event::info(
                        lazy_result.depth,
                        lazy_result.result.score,
                        lazy_result.result.nodes,
                    ));
                    if let Some(event) = lazy_result.pv_event {
                        let _ = sink.add(event);
                    }
                    lazy_result.result
                }
                #[cfg(target_arch = "wasm32")]
                {
                    run_ab_like_search(
                        &mut searcher,
                        &mut wb,
                        &config,
                        search_context,
                        max_depth,
                        |progress_searcher, depth, current| {
                            progress.emit(progress_searcher, depth, current);
                        },
                    )
                }
            } else {
                run_ab_like_search(
                    &mut searcher,
                    &mut wb,
                    &config,
                    search_context,
                    max_depth,
                    |progress_searcher, depth, current| {
                        progress.emit(progress_searcher, depth, current);
                    },
                )
            }
        }
        SearchAlgorithm::Mcts => {
            // P2-I: skill_level * 2048 iterations (master ITERATIONS_PER_SKILL_LEVEL).
            // Empty board early stop: max_iterations = 1 when no pieces on board.
            let pieces_on_board = wb.pieces_on_board();
            let all_pieces_on_board = pieces_on_board[0] as u32 + pieces_on_board[1] as u32;
            let skill_iterations = if all_pieces_on_board == 0 {
                1_u32
            } else {
                u32::from(config.skill_level).saturating_mul(2048).max(1)
            };
            // Native targets use the root-parallel driver mirroring master
            // `monte_carlo_tree_search`; wasm runs the same MCTS options
            // through the single-threaded searcher because browser Wasm does
            // not provide native `std::thread::spawn`.
            #[cfg(not(target_arch = "wasm32"))]
            let mcts_result = mcts_search_parallel::<MillGame>(
                &game,
                snapshot,
                MctsOptions {
                    iterations: skill_iterations,
                    playout_depth: 6,
                    time_limit_ms: if config.move_time_ms > 0 {
                        Some(config.move_time_ms as u64)
                    } else {
                        None
                    },
                    exploration: 0.5,
                    ab_assist_depth: 6,
                    num_threads: Some(if multi_thread_search_is_allowed(&config) {
                        search_threads_for_config(&config)
                    } else {
                        1
                    }),
                    move_order_context: mcts_move_order_context(
                        config.skill_level,
                        config.shuffling,
                    ),
                },
                search_shuffle_seed(),
            );
            #[cfg(target_arch = "wasm32")]
            let mcts_result = {
                let mut mcts_searcher = MctsSearcher::<MillGame>::new();
                mcts_searcher.set_policy(SearchPolicy {
                    quiescence_kind_tag: Some(MillActionKind::Remove as i16),
                    ..Default::default()
                });
                mcts_searcher.set_random_seed(search_shuffle_seed());
                mcts_searcher.search_with_options(
                    &mut wb,
                    MctsOptions {
                        iterations: skill_iterations,
                        playout_depth: 6,
                        time_limit_ms: if config.move_time_ms > 0 {
                            Some(config.move_time_ms as u64)
                        } else {
                            None
                        },
                        exploration: 0.5,
                        ab_assist_depth: 6,
                        num_threads: Some(1),
                        move_order_context: mcts_move_order_context(
                            config.skill_level,
                            config.shuffling,
                        ),
                    },
                )
            };
            // mcts_result.score now mirrors master MCTS best_value
            // (piece-count diff * VALUE_EACH_PIECE) via
            // tgf_core::Game::mcts_terminal_score; reuse it instead
            // of recomputing locally so all MCTS callers stay
            // consistent.
            let result = SearchResult {
                best_action: mcts_result.best_action,
                score: mcts_result.score,
                nodes: mcts_result.visits as u64,
                draw_reason: None,
            };
            let _ = sink.add(crate::engine_event::info(
                max_depth,
                result.score,
                result.nodes,
            ));
            result
        }
    };

    if config.multi_pv > 1 {
        let ctx = MultiPvEventContext {
            game: &game,
            snapshot: &snapshot,
            searcher: &searcher,
            root_side_to_move: snapshot.side_to_move,
            config: &config,
            search_context,
            nodes_per_second: nodes_per_second(result.nodes, search_started_at.elapsed()),
            // Reconstructing a missing tail runs additional searches for each
            // root row. Keep timed analysis inside its single move budget;
            // the TT-backed partial PV is sufficient for those callers.
            complete_tail: should_complete_multi_pv_tail(&config),
        };
        for event in multi_pv_events(&ctx, max_depth) {
            let _ = sink.add(event);
        }
    }

    let search_action = result.best_action;
    let mut aimovetype = "traditional";

    if config.use_perfect_database {
        let mut legal = tgf_core::ActionList::<256>::default();
        let rules = MillRules::new(rules_options.clone());
        rules.legal_actions(&snapshot, &mut legal);
        let legal_slice = legal.as_slice();
        // chooseRandom (master perfect_player.h): prefer the search's pick
        // when it is already tied-best in the DB, otherwise shuffle among the
        // tied-best DB moves when Shuffling is on.  This preserves the Random
        // algorithm's randomness instead of always overriding it with the
        // first deterministic DB move.
        //
        // With "make traps" on, the trap-aware variant starts from exactly
        // that chooseRandom baseline (same search_action reference,
        // shuffling flag, and seed) and only deviates to a tied sibling
        // with a strictly higher trap-library score.
        let pd_action = if config.patch_make_traps {
            perfect::try_perfect_best_action_trap_aware(
                &snapshot,
                rules.options(),
                legal_slice,
                perfect_move_ordering(&config),
                search_action,
                config.shuffling,
                search_shuffle_seed(),
            )
        } else {
            perfect::try_perfect_best_action_with_ref(
                &snapshot,
                rules.options(),
                legal_slice,
                perfect_move_ordering(&config),
                search_action,
                config.shuffling,
                search_shuffle_seed(),
            )
        };
        if let Some(pd_action) = pd_action {
            if pd_action == search_action {
                aimovetype = "consensus";
            } else {
                aimovetype = "perfect";
                result.best_action = pd_action;
            }
        }
    }

    result = apply_move_none_fallback(result, snapshot, &rules_options);

    let notation = action_to_uci_str(result.best_action);
    let _ = sink.add(crate::engine_event::best_move_with_notation_and_aimovetype(
        result.best_action,
        result.score,
        snapshot.side_to_move,
        &notation,
        aimovetype,
    ));
    let _ = sink.add(crate::engine_event::stopped());
    let mut active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
    *active = None;
}

/// Request that the currently-running native Mill search aborts.
/// Returns false when no worker is active.
pub(crate) fn request_abort_active_search() -> bool {
    let active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
    if let Some(handle) = active.as_ref() {
        handle.request_abort();
        true
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_mill::MillRules;

    #[test]
    fn move_none_fallback_recovers_legal_move_from_initial_position() {
        let rules = MillRules::default();
        let snapshot = rules.initial_state(&[]);
        let options = NativeMillVariantOptions::default();
        let empty = SearchResult::default_none();
        let recovered = apply_move_none_fallback(empty, snapshot, &options);
        assert!(!recovered.best_action.is_none());
    }

    /// The FRB DTO -> plan conversion must forward the make-traps switch;
    /// dropping it here silently reverts the Perfect-DB main path to the
    /// plain tied-best pick (exactly the review finding this guards).
    #[test]
    fn config_plan_conversion_preserves_patch_make_traps() {
        let cfg = crate::api::simple::MillEngineConfig {
            use_perfect_database: true,
            patch_make_traps: true,
            ..crate::api::simple::MillEngineConfig::default()
        };
        let plan = MillEngineConfigPlan::from(cfg);
        assert!(plan.use_perfect_database);
        assert!(plan.patch_make_traps);
        assert!(
            !MillEngineConfigPlan::from(crate::api::simple::MillEngineConfig::default())
                .patch_make_traps,
            "the switch must default off"
        );
    }

    #[test]
    fn perfect_database_ordering_matches_master_random_lazy_branch() {
        assert_eq!(
            perfect_move_ordering(&MillEngineConfigPlan::default()),
            perfect_db::PerfectMoveOrdering::LegacyWdl
        );
        assert_eq!(
            perfect_move_ordering(&MillEngineConfigPlan {
                algorithm: MillSearchAlgorithmKind::Random,
                ai_is_lazy: false,
                ..MillEngineConfigPlan::default()
            }),
            perfect_db::PerfectMoveOrdering::StrictSteps
        );
        assert_eq!(
            perfect_move_ordering(&MillEngineConfigPlan {
                algorithm: MillSearchAlgorithmKind::Random,
                ai_is_lazy: true,
                ..MillEngineConfigPlan::default()
            }),
            perfect_db::PerfectMoveOrdering::LegacyWdl
        );
    }

    #[test]
    fn multi_pv_events_are_opt_in_and_limited() {
        let game = MillGame::default();
        let snapshot = MillRules::default().initial_state(&[]);
        let mut wb = game.build_workbench(&snapshot);
        let mut searcher = mill_searcher_default();
        assert!(!searcher.tt_move_enabled());
        let default_config_searcher = mill_searcher_for_config(&MillEngineConfigPlan::default());
        assert!(!default_config_searcher.tt_move_enabled());
        assert!(!default_config_searcher.root_move_summaries_enabled());
        let _ = searcher.search(&mut wb, 1);

        let default_config = MillEngineConfigPlan::default();
        let default_ctx = MultiPvEventContext {
            game: &game,
            snapshot: &snapshot,
            searcher: &searcher,
            root_side_to_move: snapshot.side_to_move,
            config: &default_config,
            search_context: search_context_for_config(&default_config),
            nodes_per_second: 0,
            complete_tail: false,
        };
        assert!(multi_pv_events(&default_ctx, 1).is_empty());

        let pv_config = MillEngineConfigPlan {
            multi_pv: 3,
            ..MillEngineConfigPlan::default()
        };
        let mut pv_searcher = mill_searcher_for_config(&pv_config);
        assert!(pv_searcher.tt_move_enabled());
        assert!(pv_searcher.root_move_summaries_enabled());
        let _ = pv_searcher.search(&mut wb, 2);
        let pv_ctx = MultiPvEventContext {
            game: &game,
            snapshot: &snapshot,
            searcher: &pv_searcher,
            root_side_to_move: snapshot.side_to_move,
            config: &pv_config,
            search_context: search_context_for_config(&pv_config),
            nodes_per_second: 2048,
            complete_tail: false,
        };
        let events = multi_pv_events(&pv_ctx, 2);
        assert!(!events.is_empty());
        assert!(events.len() <= 3);
        assert!(events.iter().all(|event| event.kind == "pv"));
        assert!(events[0].reason.contains("rank=1"));
        assert!(events[0].reason.contains("nps=2048"));
        assert!(
            events.iter().all(|event| event.reason.contains(',')),
            "every emitted MultiPV line should include a continuation: {events:?}"
        );
    }

    #[test]
    fn multi_pv_accepts_shared_search_capacity_without_clamping() {
        let rules = MillRules::default();
        let snapshot = rules.initial_state(&[]);
        let config = MillEngineConfigPlan {
            multi_pv: SEARCH_ACTION_CAPACITY as u8,
            ..MillEngineConfigPlan::default()
        };

        assert_eq!(
            validate_root_action_capacity(&snapshot, &rules, &config),
            Ok(24)
        );
        assert_eq!(multi_pv_limit(&config), SEARCH_ACTION_CAPACITY);
    }

    #[test]
    fn multi_pv_over_shared_search_capacity_is_rejected() {
        let rules = MillRules::default();
        let snapshot = rules.initial_state(&[]);
        let config = MillEngineConfigPlan {
            multi_pv: (SEARCH_ACTION_CAPACITY + 1) as u8,
            ..MillEngineConfigPlan::default()
        };

        let error = validate_root_action_capacity(&snapshot, &rules, &config)
            .expect_err("over-capacity Multi-PV must fail explicitly");
        assert!(error.contains("exceeds the shared search action capacity 72"));
    }

    #[test]
    fn legal_root_over_shared_search_capacity_is_rejected_without_truncation() {
        let options = NativeMillVariantOptions {
            piece_count: 9,
            fly_piece_count: 5,
            may_fly: true,
            ..NativeMillVariantOptions::default()
        };
        let rules = MillRules::new(options.clone());
        let mut state = MillState::empty(&options);
        for node in 0..5 {
            state.set_piece(node, 1);
        }
        for node in 5..8 {
            state.set_piece(node, 2);
        }
        state.recompute_aux(&options);
        state.set_pieces_in_hand([0, 0], &options);
        state.set_phase(MillPhase::Moving);
        state.set_side_to_move(0);
        let snapshot = rules.encode_state(state);
        let config = MillEngineConfigPlan {
            multi_pv: SEARCH_ACTION_CAPACITY as u8,
            ..MillEngineConfigPlan::default()
        };

        let error = validate_root_action_capacity(&snapshot, &rules, &config)
            .expect_err("an 80-action root must fail instead of truncating to 72");
        assert!(error.contains("80 legal root actions"));
        assert!(error.contains("capacity 72"));
    }

    #[test]
    fn remaining_time_limit_uses_one_search_budget() {
        assert_eq!(remaining_time_limit_ms(0, 500), None);
        assert_eq!(remaining_time_limit_ms(6000, 0), Some(6000));
        assert_eq!(remaining_time_limit_ms(6000, 2500), Some(3500));
        assert_eq!(remaining_time_limit_ms(6000, 6000), Some(0));
        assert_eq!(remaining_time_limit_ms(6000, 7000), Some(0));
    }

    #[test]
    fn timed_multi_pv_does_not_run_unbudgeted_tail_searches() {
        let timed = MillEngineConfigPlan {
            move_time_ms: 200,
            multi_pv: SEARCH_ACTION_CAPACITY as u8,
            ..MillEngineConfigPlan::default()
        };
        assert!(!should_complete_multi_pv_tail(&timed));

        let untimed = MillEngineConfigPlan {
            move_time_ms: 0,
            multi_pv: SEARCH_ACTION_CAPACITY as u8,
            ..MillEngineConfigPlan::default()
        };
        assert!(should_complete_multi_pv_tail(&untimed));
    }

    #[test]
    fn timed_single_pv_search_reports_iterative_best_moves() {
        let game = MillGame::default();
        let snapshot = MillRules::default().initial_state(&[]);
        let mut wb = game.build_workbench(&snapshot);
        let config = MillEngineConfigPlan {
            algorithm: MillSearchAlgorithmKind::Pvs,
            depth: 4,
            move_time_ms: 500,
            skill_level: 30,
            shuffling: false,
            multi_pv: 1,
            ..MillEngineConfigPlan::default()
        };
        let mut searcher = mill_searcher_for_config(&config);
        let search_context = search_context_for_config(&config);
        searcher.set_options(configured_search_options(&config, search_context));

        let mut reported_depths = Vec::<i32>::new();
        let mut pv_events = Vec::<EngineEvent>::new();
        let result = run_ab_like_search(
            &mut searcher,
            &mut wb,
            &config,
            search_context,
            config.depth,
            |progress_searcher, depth, current| {
                reported_depths.push(depth);
                let ctx = MultiPvEventContext {
                    game: &game,
                    snapshot: &snapshot,
                    searcher: progress_searcher,
                    root_side_to_move: snapshot.side_to_move,
                    config: &config,
                    search_context,
                    nodes_per_second: nodes_per_second(current.nodes, Duration::from_millis(1)),
                    complete_tail: false,
                };
                if let Some(event) = single_pv_event(&ctx, depth, current) {
                    pv_events.push(event);
                }
            },
        );

        assert!(!result.best_action.is_none());
        assert_eq!(pv_events.len(), reported_depths.len());
        assert!(pv_events.iter().all(|event| event.kind == "pv"));
        assert!(
            pv_events
                .iter()
                .all(|event| event.reason.contains("rank=1"))
        );
        assert!(
            pv_events.iter().any(|event| event.depth > 1),
            "single-PV events should report iterative depths: {pv_events:?}"
        );
    }

    #[test]
    fn timed_multi_pv_search_reports_iterative_depths() {
        let game = MillGame::default();
        let snapshot = MillRules::default().initial_state(&[]);
        let mut wb = game.build_workbench(&snapshot);
        let config = MillEngineConfigPlan {
            algorithm: MillSearchAlgorithmKind::Pvs,
            depth: 4,
            move_time_ms: 500,
            skill_level: 30,
            shuffling: false,
            multi_pv: 2,
            ..MillEngineConfigPlan::default()
        };
        let mut searcher = mill_searcher_for_config(&config);
        let search_context = MoveOrderContext {
            algorithm: MoveOrderAlgorithm::Pvs,
            skill_level: config.skill_level,
            shuffling: config.shuffling,
            hash_move: None,
            shuffle_seed: search_shuffle_seed(),
        };
        searcher.set_options(configured_search_options(&config, search_context));

        let mut reported_depths = Vec::<i32>::new();
        let mut pv_depths = Vec::<i32>::new();
        let result = run_ab_like_search(
            &mut searcher,
            &mut wb,
            &config,
            search_context,
            config.depth,
            |progress_searcher, depth, current| {
                reported_depths.push(depth);
                let ctx = MultiPvEventContext {
                    game: &game,
                    snapshot: &snapshot,
                    searcher: progress_searcher,
                    root_side_to_move: snapshot.side_to_move,
                    config: &config,
                    search_context,
                    nodes_per_second: nodes_per_second(current.nodes, Duration::from_millis(1)),
                    complete_tail: false,
                };
                pv_depths.extend(
                    multi_pv_events(&ctx, depth)
                        .into_iter()
                        .map(|event| event.depth),
                );
            },
        );

        assert!(
            !result.best_action.is_none(),
            "timed MultiPV search must find a move"
        );
        assert!(
            reported_depths.iter().any(|depth| *depth > 1),
            "timed search should iterate beyond depth 1: {reported_depths:?}"
        );
        assert!(
            pv_depths.iter().any(|depth| *depth > 1),
            "MultiPV events should report iterative depths: {pv_depths:?}"
        );
    }

    #[test]
    fn final_multi_pv_events_complete_missing_tt_tails() {
        let game = MillGame::default();
        let snapshot = MillRules::default().initial_state(&[]);
        let mut wb = game.build_workbench(&snapshot);
        let config = MillEngineConfigPlan {
            algorithm: MillSearchAlgorithmKind::Pvs,
            depth: 4,
            skill_level: 30,
            shuffling: false,
            multi_pv: 2,
            ..MillEngineConfigPlan::default()
        };
        let search_context = search_context_for_config(&config);
        let mut searcher = mill_searcher_for_config(&config);
        searcher.set_options(configured_search_options(&config, search_context));
        let result = searcher.search(&mut wb, 1);
        assert!(
            !result.best_action.is_none(),
            "root search must produce a move for final PV event completion"
        );

        let ctx = MultiPvEventContext {
            game: &game,
            snapshot: &snapshot,
            searcher: &searcher,
            root_side_to_move: snapshot.side_to_move,
            config: &config,
            search_context,
            nodes_per_second: nodes_per_second(result.nodes, Duration::from_millis(1)),
            complete_tail: true,
        };
        let events = multi_pv_events(&ctx, config.depth);

        assert!(!events.is_empty());
        assert!(
            events.iter().all(|event| event.reason.contains(',')),
            "final MultiPV events should complete shallow tails: {events:?}"
        );
    }

    #[test]
    fn nodes_per_second_handles_empty_and_elapsed_searches() {
        assert_eq!(nodes_per_second(0, Duration::from_millis(1)), 0);
        assert_eq!(nodes_per_second(10, Duration::ZERO), 0);
        assert_eq!(nodes_per_second(2_000, Duration::from_millis(500)), 4_000);
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn multi_pv_only_disables_lazy_smp_when_requested() {
        let base = MillEngineConfigPlan {
            use_lazy_smp: true,
            shuffling: true,
            engine_threads: 4,
            multi_pv: 1,
            ..MillEngineConfigPlan::default()
        };
        assert!(multi_thread_search_is_allowed(&base));
        assert!(!multi_thread_search_is_allowed(&MillEngineConfigPlan {
            multi_pv: 2,
            ..base
        }));
    }

    fn search_startpos(depth: i32, prefetch: bool) -> SearchResult {
        let game = MillGame::default();
        let snap = MillRules::default().initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut s = Searcher::<MillGame>::new();
        s.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(MillActionKind::Remove as i16),
            ..Default::default()
        });
        s.set_options(SearchOptions {
            enable_prefetch: prefetch,
            prefetch_all: prefetch,
            ..SearchOptions::default()
        });
        // Production default for the Mill AI is MTD(f) (see
        // MillEngineConfigPlan::default), which is the TT-probe-heavy path that
        // prefetch targets. Match it here rather than the plain alpha-beta
        // `search()` entry point.
        s.search_mtdf_with_guess(&mut wb, depth, 0)
    }

    #[test]
    fn desktop_build_enables_full_tt_prefetch() {
        let base = mill_base_search_options();
        assert_eq!(base.enable_prefetch, MILL_PREFETCH);
        assert_eq!(base.prefetch_all, MILL_PREFETCH);
        #[cfg(not(any(target_os = "android", target_os = "ios", target_arch = "wasm32")))]
        {
            assert!(
                base.enable_prefetch,
                "desktop builds must enable TT prefetch"
            );
            assert!(base.prefetch_all);
        }
    }

    #[test]
    fn prefetch_is_node_preserving() {
        // Prefetch only issues cache hints on predicted keys; probe/save use
        // the real key, so the searched tree must be identical with it on or
        // off. A small depth keeps this debug-mode test fast.
        let on = search_startpos(6, true);
        let off = search_startpos(6, false);
        assert_eq!(on.nodes, off.nodes, "prefetch changed the node count");
        assert_eq!(on.best_action, off.best_action);
        assert_eq!(on.score, off.score);
    }

    /// Reusable desktop micro-benchmark (skipped by default). Run with:
    /// `cargo test -p rust_lib_sanmill --release prefetch_desktop_speedup --`
    /// ` -- --ignored --nocapture`
    #[test]
    #[ignore = "manual desktop benchmark; prints timing, not a pass/fail gate"]
    fn prefetch_desktop_speedup() {
        use std::time::Instant;
        let depth = 12;
        for &(label, pf) in &[("off", false), ("all", true)] {
            let game = MillGame::default();
            let snap = MillRules::default().initial_state(&[]);
            let mut s = Searcher::<MillGame>::new();
            s.set_policy(SearchPolicy {
                quiescence_kind_tag: Some(MillActionKind::Remove as i16),
                ..Default::default()
            });
            s.set_options(SearchOptions {
                enable_prefetch: pf,
                prefetch_all: pf,
                ..SearchOptions::default()
            });
            // Warm code/data caches, then clear the TT so the measured search
            // starts from an empty table (matching the CLI cold-process A/B).
            {
                let mut wb = game.build_workbench(&snap);
                let _ = s.search_mtdf_with_guess(&mut wb, 4, 0);
            }
            s.clear_tt();
            let mut wb = game.build_workbench(&snap);
            let t = Instant::now();
            let r = s.search_mtdf_with_guess(&mut wb, depth, 0);
            let ms = t.elapsed().as_secs_f64() * 1e3;
            println!(
                "prefetch={label:<3} depth={depth} nodes={} elapsed_ms={ms:.2}",
                r.nodes
            );
        }
    }
}
