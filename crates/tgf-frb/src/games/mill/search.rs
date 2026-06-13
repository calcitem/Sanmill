// SPDX-License-Identifier: GPL-3.0-or-later
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

use std::sync::Mutex;
use std::thread;

use once_cell::sync::Lazy;

use tgf_core::{Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext};
use tgf_mill::{
    EngineRuntimeOptions, MillActionKind, MillGame, MillRules, MillSearchAlgorithmKind,
    MillVariantOptions as NativeMillVariantOptions, recommended_search_depth,
};
use tgf_search::{
    MctsOptions, MctsSearcher, SearchAbortHandle, SearchAlgorithm, SearchOptions, SearchPolicy,
    SearchResult, Searcher,
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
        }
    }
}

// ---------------------------------------------------------------------------
// Searcher / move-ordering helpers
// ---------------------------------------------------------------------------

/// Construct a `Searcher<MillGame>` configured with the Mill removal
/// qsearch policy.  Used by every native_mill_* smoke entry point.
pub(crate) fn mill_searcher_default() -> Searcher<MillGame> {
    let mut s = Searcher::new();
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s
}

/// Move-order context used for the MCTS path.
pub(crate) fn mcts_move_order_context(skill_level: u8) -> MoveOrderContext {
    MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mcts,
        skill_level,
        shuffling: true,
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
    options: NativeMillVariantOptions,
    depth: i32,
    sink: StreamSink<EngineEvent>,
) {
    let config = MillEngineConfigPlan {
        depth,
        ..Default::default()
    };
    spawn_mill_engine_config_event_stream(snapshot, options, config, sink);
}

/// Launch a search thread using the full `MillEngineConfig`.  Emits one
/// `info` event per IDS depth, then a final `bestMove` + `stopped`.
pub(crate) fn spawn_mill_engine_config_event_stream(
    snapshot: GameStateSnapshot,
    options: NativeMillVariantOptions,
    config: MillEngineConfigPlan,
    sink: StreamSink<EngineEvent>,
) {
    thread::spawn(move || {
        if sink.add(crate::engine_event::ready()).is_err() {
            return;
        }

        let rules_options = options.clone();
        let game = MillGame::new(options);
        let mut wb = game.build_workbench(&snapshot);
        let mut searcher = mill_searcher_default();
        let search_context = MoveOrderContext {
            algorithm: match algorithm_to_search(config.algorithm) {
                SearchAlgorithm::AlphaBeta => MoveOrderAlgorithm::AlphaBeta,
                SearchAlgorithm::Pvs => MoveOrderAlgorithm::Pvs,
                SearchAlgorithm::Mtdf => MoveOrderAlgorithm::Mtdf,
                SearchAlgorithm::Mcts => MoveOrderAlgorithm::Mcts,
                SearchAlgorithm::Random => MoveOrderAlgorithm::Random,
            },
            skill_level: config.skill_level,
            shuffling: true,
            hash_move: None,
            shuffle_seed: search_shuffle_seed(),
        };
        searcher.set_move_order_context(search_context);

        // Apply time limit if requested.
        if config.move_time_ms > 0 {
            searcher.set_options(SearchOptions {
                time_limit_ms: Some(config.move_time_ms as u64),
                move_order_context: search_context,
                ..SearchOptions::default()
            });
        }

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
        let mut result = SearchResult::default_none();
        let run_ids = config.move_time_ms > 0;
        let mut first_guess = 0;

        match algorithm_to_search(config.algorithm) {
            SearchAlgorithm::Random => {
                // Use time-seeded random to match master's rand()+time() behaviour.
                let seed = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(42);
                searcher.set_random_seed(seed);
                result = searcher.random_search(&mut wb);
                let _ = sink.add(crate::engine_event::info(1, result.score, result.nodes));
            }
            SearchAlgorithm::AlphaBeta | SearchAlgorithm::Pvs => {
                if run_ids {
                    for d in 2..max_depth {
                        if searcher.was_aborted() {
                            break;
                        }
                        result = searcher.search(&mut wb, d);
                        // first_guess is consumed by the MTD(f) branch only;
                        // Pvs / AlphaBeta still update it for symmetry but
                        // never read it back.
                        let _ = first_guess;
                        first_guess = result.score;
                        let _ = sink.add(crate::engine_event::info(d, result.score, result.nodes));
                    }
                }
                if !searcher.was_aborted() || result.best_action.is_none() {
                    // Master executeSearch routes Algorithm 0 and 1 to
                    // the same Search::search path; search_pvs remains
                    // available as a Rust implementation but is not used
                    // for parity.
                    result = searcher.search(&mut wb, max_depth);
                    let _ = sink.add(crate::engine_event::info(
                        max_depth,
                        result.score,
                        result.nodes,
                    ));
                }
            }
            SearchAlgorithm::Mtdf => {
                if run_ids {
                    for d in 2..max_depth {
                        if searcher.was_aborted() {
                            break;
                        }
                        result = searcher.search_mtdf_with_guess(&mut wb, d, first_guess);
                        first_guess = result.score;
                        let _ = sink.add(crate::engine_event::info(d, result.score, result.nodes));
                    }
                }
                if !searcher.was_aborted() || result.best_action.is_none() {
                    result = searcher.search_mtdf_with_guess(&mut wb, max_depth, first_guess);
                    let _ = sink.add(crate::engine_event::info(
                        max_depth,
                        result.score,
                        result.nodes,
                    ));
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
                let mut mcts = MctsSearcher::<MillGame>::new();
                let mcts_result = mcts.search_with_options(
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
                        // FRB engine search runs on a worker thread that
                        // already isolates one search per session; keep
                        // MCTS single-threaded inside that worker.  UI
                        // callers wanting parallel MCTS should switch to
                        // tgf_search::mcts_search_parallel.
                        num_threads: Some(1),
                        move_order_context: mcts_move_order_context(config.skill_level),
                    },
                );
                // mcts_result.score now mirrors master MCTS best_value
                // (piece-count diff * VALUE_EACH_PIECE) via
                // tgf_core::Game::mcts_terminal_score; reuse it instead
                // of recomputing locally so all MCTS callers stay
                // consistent.
                result = SearchResult {
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
            }
        }

        let search_action = result.best_action;
        let mut aimovetype = "traditional";

        if config.use_perfect_database {
            let mut legal = tgf_core::ActionList::<256>::default();
            let rules = MillRules::new(rules_options.clone());
            rules.legal_actions(&snapshot, &mut legal);
            let legal_slice = legal.as_slice();
            if let Some(pd_action) =
                perfect::try_perfect_best_action(&snapshot, rules.options(), legal_slice)
            {
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
    });
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
}
