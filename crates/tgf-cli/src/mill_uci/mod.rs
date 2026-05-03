// SPDX-License-Identifier: GPL-3.0-or-later
// Mill UCI adapter for tgf-cli.
//
// Owns every Mill-specific piece of the CLI:
//   * the UCI main loop and `setoption` table for all Mill rule variants
//   * Mill FEN parsing and ASCII board printing
//   * Mill action ↔ UCI string codec
//   * `Searcher<MillGame>` factory tuned for Mill (Remove qsearch policy)
//   * the bench harness used by `tgf bench` and the perf-baseline pipeline
//
// `main.rs` only routes the subcommand.  Adding a new game (e.g. Othello)
// is a matter of dropping a new sibling module here and wiring it into
// the dispatch in `main.rs`; nothing else in this file generalises.

use std::io::{self, BufRead};
use std::sync::atomic::AtomicBool;
use std::sync::{mpsc, Arc};
use std::thread::{self, JoinHandle};
use tgf_core::{
    Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm, MoveOrderContext, Workbench,
};
use tgf_mill::{
    recommended_search_depth, EngineRuntimeOptions, MillActionKind, MillGame, MillRules,
    MillVariantOptions,
};
use tgf_search::{
    lazy_smp_search, LazySmpWorker, MctsOptions, MctsSearcher, SearchAbortHandle, SearchOptions,
    SearchPolicy, SearchResult, Searcher, SharedTt,
};

mod bench;
mod board;
mod setoption;

pub use bench::print_benchmark_toml;
#[cfg(test)]
use board::board_ascii_lines;
use board::{
    action_to_uci, parse_go_options, parse_position_command, print_board_ascii, print_uci_options,
    GoOptions,
};
use setoption::{apply_setoption, SetoptionResult};

/// `TGF_TT_CLUSTER_BITS` (10–18) selects `2^(bits+1)` TT slots; see
/// `tgf_search::Searcher::new_with_tt_cluster_bits`.
fn tt_cluster_bits_from_env() -> u32 {
    std::env::var("TGF_TT_CLUSTER_BITS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(14)
        .clamp(10, 18)
}

fn mill_searcher() -> Searcher<MillGame> {
    let mut s = Searcher::new_with_tt_cluster_bits(tt_cluster_bits_from_env());
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s
}

/// Runtime engine configuration (non-variant search/difficulty parameters).
/// These mirror the master `GameOptions` fields that are set via UCI setoption.
#[derive(Clone, Debug)]
struct EngineConfig {
    skill_level: u8,
    algorithm: u8,
    ai_is_lazy: bool,
    ids_enabled: bool,
    depth_extension: bool,
    last_best_value: i32,
    move_time_secs: u32,
    shuffling: bool,
    draw_on_human_experience: bool,
    developer_mode: bool,
    hash_mb: u32,
    ponder: bool,
    use_lazy_smp: bool,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            skill_level: 1,
            algorithm: 2,
            ai_is_lazy: false,
            ids_enabled: false,
            depth_extension: true,
            last_best_value: 0,
            move_time_secs: 1,
            shuffling: true,
            draw_on_human_experience: true,
            developer_mode: true,
            hash_mb: 16,
            ponder: false,
            use_lazy_smp: std::env::var("TGF_USE_LAZY_SMP")
                .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
        }
    }
}

pub fn run_uci_loop() {
    let mut options = MillVariantOptions::default();
    let mut rules = MillRules::new(options.clone());
    let mut state = rules.initial_state(&[]);
    let mut threads: usize = 1;
    let mut qsearch_max_depth: i32 = 0;
    let mut engine_cfg = EngineConfig::default();
    let mut active_search: Option<ActiveSearch> = None;
    let stdin = io::stdin();
    for line in stdin.lock().lines().map_while(Result::ok) {
        drain_finished_search(&mut active_search, &mut engine_cfg);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if line == "uci" {
            println!("id name TGF Mill Rust");
            println!("id author The Sanmill developers");
            print_uci_options();
            println!("uciok");
        } else if line == "isready" {
            println!("readyok");
        } else if line == "ucinewgame" {
            finish_active_search(&mut active_search, &mut engine_cfg);
            state = rules.initial_state(&[]);
        } else if line == "compiler" {
            println!(
                "info string compiler Rust {} target {}",
                env!("CARGO_PKG_VERSION"),
                std::env::consts::ARCH
            );
        } else if line.starts_with("setoption") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            match apply_setoption(
                line,
                &mut options,
                &mut threads,
                &mut qsearch_max_depth,
                &mut engine_cfg,
            ) {
                SetoptionResult::Variant => {
                    // NOTE: intentional deviation from master src/ucioption.cpp.
                    // master only updates the global rule table when a variant
                    // option changes.  Rust resets the position because a
                    // mid-game variant switch can invalidate MillState counts;
                    // callers can re-issue `position fen ...` afterwards.
                    rules = MillRules::new(options.clone());
                    state = rules.initial_state(&[]);
                }
                SetoptionResult::ClearHash => {
                    // Mirror master src/ucioption.cpp:357 Clear Hash button.
                    // The CLI creates a fresh searcher per `go`, so there is
                    // no live TT handle outside an active search.  Treat the
                    // button as an acknowledged hard-clear request; the next
                    // search starts from a fresh table.
                }
                SetoptionResult::Threads
                | SetoptionResult::SearchConfig
                | SetoptionResult::Acknowledged => {}
                SetoptionResult::Unknown => {
                    println!("info string unsupported setoption: {line}");
                }
            }
        } else if line.starts_with("bench") {
            println!("info string bench is a separate subcommand; run: tgf bench");
        } else if line.starts_with("position") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            state = parse_position_command(&rules, line);
        } else if line == "d" {
            print_board_ascii(&state, &options);
        } else if line.starts_with("go") {
            finish_active_search(&mut active_search, &mut engine_cfg);
            let go = parse_go_options(line, state.side_to_move, &engine_cfg);
            active_search = Some(spawn_search(
                options.clone(),
                state,
                go,
                threads,
                qsearch_max_depth,
                engine_cfg.hash_mb,
                engine_cfg.clone(),
            ));
        } else if line == "stop" {
            if let Some(active) = active_search.take() {
                active.abort_handle.request_abort();
                join_and_update(active, &mut engine_cfg);
            } else {
                // Match legacy single-line SearchEngine::print_bestmove output.
                println!("info score 0 bestmove none");
            }
        } else if line == "ponderhit" {
            // In ponder mode the engine switches from pondering to searching;
            // since tgf-cli doesn't implement ponder, silently ignore.
        } else if line == "quit" {
            finish_active_search(&mut active_search, &mut engine_cfg);
            break;
        } else {
            println!("info string unknown command: {line}");
        }
    }
    // Drain on EOF: join any in-flight search and emit its bestmove instead
    // of orphaning the spawned thread or losing the result entirely.
    finish_active_search(&mut active_search, &mut engine_cfg);
}

struct ActiveSearch {
    handle: JoinHandle<()>,
    abort_handle: SearchAbortHandle,
    receiver: mpsc::Receiver<SpawnResult>,
}

struct SpawnResult {
    depth: i32,
    result: SearchResult,
    /// Side to move at the root of the search tree (0=white, 1=black).
    /// Used by format_spawn_result to flip the score to White's perspective,
    /// matching master SearchEngine::emitCommand (P1-C.1).
    root_side_to_move: i8,
}

fn spawn_search(
    options: MillVariantOptions,
    state: GameStateSnapshot,
    go: GoOptions,
    threads: usize,
    qsearch_max_depth: i32,
    hash_mb: u32,
    cfg: EngineConfig,
) -> ActiveSearch {
    let search_options = SearchOptions {
        depth_extension: cfg.depth_extension,
        node_limit: go.node_limit,
        time_limit_ms: go.movetime_ms,
        allow_null_move: false,
        // Master shuffles the global movePriorityList before generation.
        // Mill's generate_legal_ctx already mirrors that list, so do not
        // additionally shuffle the root action list here.
        shuffle_root: false,
        // Mill's full-state position_key makes Workbench::key_after a
        // do/undo round-trip, so prefetch's overhead exceeds its
        // benefit until the planned incremental Zobrist migration.
        enable_prefetch: false,
        move_order_context: move_order_context(&cfg),
    };
    let depth = effective_search_depth(&options, &state, go.depth, &cfg);
    let root_side_to_move = state.side_to_move;
    let (tx, rx) = mpsc::channel();
    let abort = Arc::new(AtomicBool::new(false));
    let abort_handle = SearchAbortHandle::from_arc(Arc::clone(&abort));

    // NOTE: master C++ keeps `Threads` for the engine commander pool only.
    // Mill search itself stays single-threaded. We mirror that default here;
    // set `UseLazySmp = true` (or TGF_USE_LAZY_SMP=1) to opt into Rust's
    // lazy-SMP variant for higher NPS.
    let use_lazy_smp = cfg.use_lazy_smp && threads > 1;

    let handle = if !use_lazy_smp {
        let abort_for_worker = Arc::clone(&abort);
        thread::spawn(move || {
            let mut searcher = mill_searcher();
            // P2-L plan-C: resize TT when Hash setoption specifies a size.
            if hash_mb > 0 {
                searcher.resize_tt_by_mb(hash_mb);
            }
            searcher.set_abort_flag(abort_for_worker);
            searcher.set_options(search_options);
            searcher.set_qsearch_max_depth(qsearch_max_depth);
            let result = run_configured_search(options, state, depth, &cfg, &mut searcher);
            let spawn = SpawnResult {
                depth,
                result,
                root_side_to_move,
            };
            println!("{}", format_spawn_result(&spawn));
            let _ = tx.send(spawn);
        })
    } else {
        let abort_for_workers = Arc::clone(&abort);
        thread::spawn(move || {
            let workers: Vec<LazySmpWorker> = (0..threads)
                .map(|i| LazySmpWorker {
                    extra_depth: (i % 2) as i32,
                })
                .collect();
            let shared_tt = SharedTt::with_capacity_mb(hash_mb, tt_cluster_bits_from_env());
            let game = MillGame::new(options);
            let result = lazy_smp_search::<MillGame>(
                game,
                state,
                depth,
                &workers,
                search_options,
                shared_tt,
                Some(abort_for_workers),
            );
            let spawn = SpawnResult {
                depth,
                result,
                root_side_to_move,
            };
            println!("{}", format_spawn_result(&spawn));
            let _ = tx.send(spawn);
        })
    };

    ActiveSearch {
        handle,
        abort_handle,
        receiver: rx,
    }
}

fn run_configured_search(
    options: MillVariantOptions,
    state: GameStateSnapshot,
    depth: i32,
    cfg: &EngineConfig,
    searcher: &mut Searcher<MillGame>,
) -> SearchResult {
    // Mirror master src/search_engine.cpp:381 executeSearch: route the
    // user-visible Algorithm option into the actual search implementation.
    let game = MillGame::new(options.clone());
    let mut wb = game.build_workbench(&state);
    let mut value = 0;
    let mut best_so_far = SearchResult::default_none();
    let run_ids = cfg.move_time_secs > 0 || cfg.ids_enabled;
    if run_ids {
        for d in 2..depth {
            let result = run_algorithm_at_depth(searcher, &mut wb, cfg, d, value);
            value = result.score;
            if !searcher.was_aborted() {
                best_so_far = result;
            }
            if searcher.was_aborted() {
                break;
            }
        }
    }
    if !searcher.was_aborted() || best_so_far.best_action.is_none() {
        run_algorithm_at_depth(searcher, &mut wb, cfg, depth, value)
    } else {
        best_so_far
    }
}

fn run_algorithm_at_depth(
    searcher: &mut Searcher<MillGame>,
    wb: &mut tgf_mill::MillWorkbench,
    cfg: &EngineConfig,
    depth: i32,
    first_guess: i32,
) -> SearchResult {
    match cfg.algorithm {
        // Master executeSearch currently routes both Algorithm 0 and 1 to
        // Search::search; Rust search_pvs remains available but is not the
        // master-equivalent route here.
        0 | 1 => searcher.search(wb, depth),
        2 => searcher.search_mtdf_with_guess(wb, depth, first_guess),
        3 => run_mcts_search(wb, cfg),
        4 => {
            searcher.set_random_seed(search_shuffle_seed());
            searcher.random_search(wb)
        }
        _ => searcher.search(wb, depth),
    }
}

fn run_mcts_search(wb: &mut tgf_mill::MillWorkbench, cfg: &EngineConfig) -> SearchResult {
    let pieces_on_board = wb.pieces_on_board();
    let all_on_board = u32::from(pieces_on_board[0]) + u32::from(pieces_on_board[1]);
    let iterations = if all_on_board == 0 {
        1
    } else {
        u32::from(cfg.skill_level).saturating_mul(2048).max(1)
    };
    let mut mcts = MctsSearcher::<MillGame>::new();
    mcts.set_random_seed(search_shuffle_seed());
    mcts.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    let mcts_result = mcts.search_with_options(
        wb,
        MctsOptions {
            iterations,
            playout_depth: 6,
            time_limit_ms: cfg.move_time_secs.checked_mul(1000).map(u64::from),
            exploration: 0.5,
            ab_assist_depth: 6,
            // CLI go path runs in the foreground UCI loop; keep MCTS
            // single-threaded here.  Multi-thread MCTS is exposed via
            // tgf_search::mcts_search_parallel for callers that own
            // their own scheduling.
            num_threads: Some(1),
            move_order_context: move_order_context_with_algorithm(cfg, MoveOrderAlgorithm::Mcts),
        },
    );
    SearchResult {
        best_action: mcts_result.best_action,
        score: mill_material_score(wb),
        nodes: mcts_result.visits as u64,
    }
}

fn effective_search_depth(
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    requested_depth: i32,
    cfg: &EngineConfig,
) -> i32 {
    let requested_depth = if requested_depth > 0 {
        requested_depth
    } else {
        let mill_state = MillRules::decode_snapshot(*state);
        let runtime = EngineRuntimeOptions {
            skill_level: cfg.skill_level,
            draw_on_human_experience: cfg.draw_on_human_experience,
            developer_mode: cfg.developer_mode,
        };
        recommended_search_depth(&mill_state, options, &runtime).max(1)
    };
    if cfg.ai_is_lazy {
        const VALUE_EACH_PIECE: i32 = 5;
        let np = cfg.last_best_value / VALUE_EACH_PIECE;
        if np > 1 {
            return if requested_depth < 4 { 1 } else { 4 };
        }
    }
    requested_depth.max(1)
}

fn move_order_context(cfg: &EngineConfig) -> MoveOrderContext {
    move_order_context_with_algorithm(
        cfg,
        match cfg.algorithm {
            0 => MoveOrderAlgorithm::AlphaBeta,
            2 => MoveOrderAlgorithm::Mtdf,
            3 => MoveOrderAlgorithm::Mcts,
            4 => MoveOrderAlgorithm::Random,
            _ => MoveOrderAlgorithm::Pvs,
        },
    )
}

fn move_order_context_with_algorithm(
    cfg: &EngineConfig,
    algorithm: MoveOrderAlgorithm,
) -> MoveOrderContext {
    MoveOrderContext {
        algorithm,
        skill_level: cfg.skill_level,
        shuffling: cfg.shuffling,
        hash_move: None,
        shuffle_seed: search_shuffle_seed(),
    }
}

fn mill_material_score(wb: &tgf_mill::MillWorkbench) -> i32 {
    let pieces = wb.pieces_on_board();
    let in_hand = wb.pieces_in_hand();
    let side = wb.side_to_move() as usize;
    if side >= 2 {
        return 0;
    }
    let opponent = side ^ 1;
    (i32::from(pieces[side]) + i32::from(in_hand[side])
        - i32::from(pieces[opponent])
        - i32::from(in_hand[opponent]))
        * 5
}

fn search_shuffle_seed() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

fn finish_active_search(slot: &mut Option<ActiveSearch>, cfg: &mut EngineConfig) {
    if let Some(active) = slot.take() {
        join_and_update(active, cfg);
    }
}

fn take_finished_search(slot: &mut Option<ActiveSearch>) -> Option<SpawnResult> {
    let active = slot.as_ref()?;
    match active.receiver.try_recv() {
        Ok(spawn) => {
            let active = slot.take().expect("active search present");
            let _ = active.handle.join();
            Some(spawn)
        }
        Err(mpsc::TryRecvError::Empty) => None,
        Err(mpsc::TryRecvError::Disconnected) => {
            let active = slot.take().expect("active search present");
            let _ = active.handle.join();
            Some(SpawnResult {
                depth: 0,
                result: SearchResult::default_none(),
                root_side_to_move: 0,
            })
        }
    }
}

fn drain_finished_search(slot: &mut Option<ActiveSearch>, cfg: &mut EngineConfig) {
    if let Some(spawn) = take_finished_search(slot) {
        update_last_best_value(cfg, &spawn);
    }
}

// NOTE: intentional deviation from master src/search_engine.cpp:64.
// Rust emits standard UCI ("info depth ... score cp|mate ... nodes ...
// bestmove ...") instead of the legacy "info score N bestmove M" string.
// Flutter's parser accepts both shapes.
/// Format the score as a UCI score string (P2-M).
/// Scores in the mate range (|score| > VALUE_MATE_IN_MAX_PLY) are
/// formatted as "score mate N" (positive = we win, negative = we lose).
/// Other scores are formatted as "score cp N" (centipawn-style).
/// VALUE_MATE = 80, MAX_PLY = 32 → VALUE_MATE_IN_MAX_PLY = 80 - 32 = 48.
fn format_score(output_score: i32) -> String {
    const VALUE_MATE: i32 = 80;
    const MAX_PLY: i32 = 32;
    const VALUE_MATE_IN_MAX_PLY: i32 = VALUE_MATE - MAX_PLY;
    if output_score.abs() > VALUE_MATE_IN_MAX_PLY {
        let mate_in = if output_score > 0 {
            (VALUE_MATE - output_score + 1) / 2
        } else {
            -(VALUE_MATE + output_score + 1) / 2
        };
        format!("score mate {mate_in}")
    } else {
        format!("score cp {output_score}")
    }
}

fn join_and_update(active: ActiveSearch, cfg: &mut EngineConfig) {
    let _ = active.handle.join();
    if let Ok(spawn) = active.receiver.recv() {
        update_last_best_value(cfg, &spawn);
    }
}

fn update_last_best_value(cfg: &mut EngineConfig, spawn: &SpawnResult) {
    cfg.last_best_value = spawn.result.score;
}

fn format_spawn_result(spawn: &SpawnResult) -> String {
    // Mirror master SearchEngine::emitCommand (P1-C.1): the UCI score is
    // always from White's perspective.  When Black is to move the raw
    // search score (from the mover's perspective) is negated.
    let output_score = if spawn.root_side_to_move == 1 {
        -spawn.result.score
    } else {
        spawn.result.score
    };
    let score_str = format_score(output_score);
    let uci = action_to_uci(spawn.result.best_action).unwrap_or_else(|| "none".to_owned());
    format!(
        "info depth {} {} nodes {} bestmove {}",
        spawn.depth, score_str, spawn.result.nodes, uci
    )
}

#[cfg(test)]
mod tests;
