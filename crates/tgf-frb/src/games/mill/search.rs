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

use once_cell::sync::Lazy;

use tgf_core::{Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext};
use tgf_mill::{
    EngineRuntimeOptions, MillActionKind, MillGame, MillRules, MillSearchAlgorithmKind,
    MillVariantOptions as NativeMillVariantOptions, recommended_search_depth,
};
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
    /// Randomise the order of equally-ranked root moves so the AI does not
    /// always pick the same line.  Maps to master's `Shuffling` UCI option;
    /// disable for deterministic play.
    pub shuffling: bool,
    /// Enable multi-threaded native search where supported.  This is gated by
    /// `shuffling` so fixed-position deterministic play remains single-threaded.
    pub use_lazy_smp: bool,
    /// Requested worker/thread count for multi-threaded search.
    pub engine_threads: u32,
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
            shuffling: true,
            use_lazy_smp: false,
            engine_threads: 4,
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
    max_depth: i32,
    mut on_info: impl FnMut(i32, &SearchResult),
) -> SearchResult {
    let mut result = SearchResult::default_none();
    let mut first_guess = 0;
    if config.move_time_ms > 0 {
        for d in 2..max_depth {
            if searcher.was_aborted() {
                break;
            }
            result = run_searcher_algorithm(searcher, wb, config.algorithm, d, first_guess);
            first_guess = result.score;
            on_info(d, &result);
        }
    }
    if !searcher.was_aborted() || result.best_action.is_none() {
        result = run_searcher_algorithm(searcher, wb, config.algorithm, max_depth, first_guess);
        on_info(max_depth, &result);
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
        config.use_lazy_smp && config.shuffling && search_threads_for_config(config) > 1
    }
}

fn mix_lazy_smp_worker_seed(seed: u64, worker_index: u64) -> u64 {
    let mut x = seed ^ worker_index.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    x ^ (x >> 31)
}

#[cfg(not(target_arch = "wasm32"))]
fn run_lazy_smp_ab_like_search(
    game: &MillGame,
    snapshot: GameStateSnapshot,
    config: &MillEngineConfigPlan,
    base_depth: i32,
    base_context: MoveOrderContext,
    shared_tt: SharedTt,
    abort: Arc<AtomicBool>,
) -> SearchResult {
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
        handles.push(thread::spawn(move || {
            let mut searcher = mill_searcher_with_shared_tt(worker_shared_tt);
            searcher.set_abort_flag(worker_abort);
            searcher.set_options(configured_search_options(&worker_config, worker_context));
            let mut wb = worker_game.build_workbench(&snapshot);
            let result = run_ab_like_search(
                &mut searcher,
                &mut wb,
                &worker_config,
                worker_depth,
                |_, _| {},
            );
            (worker_depth, result)
        }));
    }

    let mut best: Option<(i32, SearchResult)> = None;
    let mut total_nodes = 0_u64;
    for handle in handles {
        let (depth, result) = handle
            .join()
            .expect("lazy-SMP Mill worker should return a SearchResult");
        total_nodes = total_nodes.saturating_add(result.nodes);
        if best.as_ref().is_none_or(|current| {
            lazy_smp_result_is_better((depth, &result), (current.0, &current.1))
        }) {
            best = Some((depth, result));
        }
    }
    let (_, mut result) = best.expect("at least one lazy-SMP worker must run");
    result.nodes = total_nodes;
    result
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

/// Launch a search thread using the full `MillEngineConfig`.  Emits one
/// `info` event per IDS depth, then a final `bestMove` + `stopped`.
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
    let mut game = MillGame::new_with_repetition_context(
        options,
        root_repetition_history,
        root_position_resets_repetition,
    );
    if let Some(weights) = tgf_mill::MillEvalWeights::from_env() {
        game.set_eval_weights(weights);
    }
    let mut wb = game.build_workbench(&snapshot);
    let mut searcher = mill_searcher_default();
    let abort = Arc::new(AtomicBool::new(false));
    let search_context = MoveOrderContext {
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
    };
    searcher.set_abort_flag(Arc::clone(&abort));
    searcher.set_options(configured_search_options(&config, search_context));

    {
        let mut active = ACTIVE_SEARCH.lock().expect("active search mutex poisoned");
        *active = Some(searcher.abort_handle());
    }

    let requested_depth = if config.depth > 0 {
        config.depth
    } else {
        let rules = MillRules::new(rules_options.clone());
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
            if multi_thread_search_is_allowed(&config) {
                #[cfg(not(target_arch = "wasm32"))]
                {
                    let result = run_lazy_smp_ab_like_search(
                        &game,
                        snapshot,
                        &config,
                        max_depth,
                        search_context,
                        searcher.shared_tt(),
                        Arc::clone(&abort),
                    );
                    let _ = sink.add(crate::engine_event::info(
                        max_depth,
                        result.score,
                        result.nodes,
                    ));
                    result
                }
                #[cfg(target_arch = "wasm32")]
                {
                    run_ab_like_search(
                        &mut searcher,
                        &mut wb,
                        &config,
                        max_depth,
                        |depth, current| {
                            let _ = sink.add(crate::engine_event::info(
                                depth,
                                current.score,
                                current.nodes,
                            ));
                        },
                    )
                }
            } else {
                run_ab_like_search(
                    &mut searcher,
                    &mut wb,
                    &config,
                    max_depth,
                    |depth, current| {
                        let _ = sink.add(crate::engine_event::info(
                            depth,
                            current.score,
                            current.nodes,
                        ));
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
        if let Some(pd_action) = perfect::try_perfect_best_action_with_ref(
            &snapshot,
            rules.options(),
            legal_slice,
            perfect_move_ordering(&config),
            search_action,
            config.shuffling,
            search_shuffle_seed(),
        ) {
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
