// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.

use std::io::{self, BufRead};
use std::sync::atomic::AtomicBool;
use std::sync::{mpsc, Arc};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use tgf_core::{
    Action, ActionList, BoardTopology, Game, GameRules, GameStateSnapshot, MoveOrderAlgorithm,
    MoveOrderContext, Workbench,
};
use tgf_mill::{
    default_mill_topology, recommended_search_depth, EngineRuntimeOptions, MillActionKind,
    MillGame, MillRules, MillVariantOptions,
};
use tgf_search::{
    lazy_smp_search, perft, LazySmpWorker, MctsOptions, MctsSearcher, SearchAbortHandle,
    SearchOptions, SearchPolicy, SearchResult, Searcher, SharedTt,
};

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
        remove_kind_tag: Some(MillActionKind::Remove as i16),
    });
    s
}

fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("bench") => print_benchmark_toml(),
        Some("uci") => run_uci_loop(),
        Some("--help") | Some("-h") => print_help(),
        _ => print_help(),
    }
}

fn print_help() {
    eprintln!("Usage:");
    eprintln!("  tgf bench    # emit perf_baseline-compatible TOML");
    eprintln!("  tgf uci      # run minimal UCI-like loop backed by Rust Mill");
}

/// Runtime engine configuration (non-variant search/difficulty parameters).
/// These mirror the master `GameOptions` fields that are set via UCI setoption.
#[derive(Clone, Debug)]
struct EngineConfig {
    skill_level: u8,
    algorithm: u8,
    ai_is_lazy: bool,
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

fn run_uci_loop() {
    let mut options = MillVariantOptions::default();
    let mut rules = MillRules::new(options.clone());
    let mut state = rules.initial_state(&[]);
    let mut threads: usize = 1;
    let mut qsearch_max_depth: i32 = 0;
    let mut engine_cfg = EngineConfig::default();
    let mut active_search: Option<ActiveSearch> = None;
    let stdin = io::stdin();
    for line in stdin.lock().lines().map_while(Result::ok) {
        drain_finished_search(&mut active_search);
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
            finish_active_search(&mut active_search);
            state = rules.initial_state(&[]);
        } else if line == "compiler" {
            println!(
                "info string compiler Rust {} target {}",
                env!("CARGO_PKG_VERSION"),
                std::env::consts::ARCH
            );
        } else if line.starts_with("setoption") {
            finish_active_search(&mut active_search);
            match apply_setoption(
                line,
                &mut options,
                &mut threads,
                &mut qsearch_max_depth,
                &mut engine_cfg,
            ) {
                SetoptionResult::Variant => {
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
            finish_active_search(&mut active_search);
            state = parse_position_command(&rules, line);
        } else if line == "d" {
            print_board_ascii(&state);
        } else if line.starts_with("go") {
            finish_active_search(&mut active_search);
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
                join_and_print(active);
            } else {
                // Match legacy single-line SearchEngine::print_bestmove output.
                println!("info score 0 bestmove none");
            }
        } else if line == "ponderhit" {
            // In ponder mode the engine switches from pondering to searching;
            // since tgf-cli doesn't implement ponder, silently ignore.
        } else if line == "quit" {
            finish_active_search(&mut active_search);
            break;
        } else {
            println!("info string unknown command: {line}");
        }
    }
    // Drain on EOF: join any in-flight search and emit its bestmove instead
    // of orphaning the spawned thread or losing the result entirely.
    finish_active_search(&mut active_search);
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
    /// Used by join_and_print to flip the score to White's perspective,
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
        depth_extension: false,
        node_limit: go.node_limit,
        time_limit_ms: go.movetime_ms,
        allow_null_move: false,
        shuffle_root: cfg.shuffling,
        move_order_context: move_order_context(&cfg),
        ..Default::default()
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
            let _ = tx.send(SpawnResult {
                depth,
                result,
                root_side_to_move,
            });
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
            let _ = tx.send(SpawnResult {
                depth,
                result,
                root_side_to_move,
            });
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
    let game = MillGame::new(options);
    let mut wb = game.build_workbench(&state);
    match cfg.algorithm {
        0 | 1 => searcher.search_pvs(&mut wb, depth),
        2 => searcher.search_mtdf(&mut wb, depth),
        3 => {
            let iterations = u32::from(cfg.skill_level).saturating_mul(2048).max(1);
            let mut mcts = MctsSearcher::<MillGame>::new();
            let mcts_result = mcts.search_with_options(
                &mut wb,
                MctsOptions {
                    iterations: iterations.max(1),
                    playout_depth: 6,
                    time_limit_ms: cfg.move_time_secs.checked_mul(1000).map(u64::from),
                    exploration: 0.5,
                    ab_assist_depth: 0,
                },
            );
            SearchResult {
                best_action: mcts_result.best_action,
                score: mill_material_score(&wb),
                nodes: mcts_result.visits as u64,
            }
        }
        4 => searcher.random_search(&mut wb),
        _ => searcher.search_pvs(&mut wb, depth),
    }
}

fn effective_search_depth(
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    requested_depth: i32,
    cfg: &EngineConfig,
) -> i32 {
    if requested_depth > 0 {
        return requested_depth;
    }
    let mill_state = MillRules::decode_snapshot(*state);
    let runtime = EngineRuntimeOptions {
        skill_level: cfg.skill_level,
        draw_on_human_experience: cfg.draw_on_human_experience,
        developer_mode: cfg.developer_mode,
    };
    recommended_search_depth(&mill_state, options, &runtime).max(1)
}

fn move_order_context(cfg: &EngineConfig) -> MoveOrderContext {
    MoveOrderContext {
        algorithm: match cfg.algorithm {
            0 => MoveOrderAlgorithm::AlphaBeta,
            2 => MoveOrderAlgorithm::Mtdf,
            3 => MoveOrderAlgorithm::Mcts,
            4 => MoveOrderAlgorithm::Random,
            _ => MoveOrderAlgorithm::Pvs,
        },
        skill_level: cfg.skill_level,
        shuffling: cfg.shuffling,
        hash_move: None,
    }
}

fn mill_material_score(wb: &tgf_mill::MillWorkbench) -> i32 {
    let pieces = wb.pieces_on_board();
    let side = wb.side_to_move() as usize;
    if side >= 2 {
        return 0;
    }
    let opponent = side ^ 1;
    i32::from(pieces[side]) - i32::from(pieces[opponent])
}

fn finish_active_search(slot: &mut Option<ActiveSearch>) {
    if let Some(active) = slot.take() {
        join_and_print(active);
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

fn drain_finished_search(slot: &mut Option<ActiveSearch>) {
    if let Some(spawn) = take_finished_search(slot) {
        print_spawn_result(spawn);
    }
}

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

fn join_and_print(active: ActiveSearch) {
    let _ = active.handle.join();
    if let Ok(spawn) = active.receiver.recv() {
        print_spawn_result(spawn);
    } else {
        println!("info score 0 bestmove none");
    }
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

fn print_spawn_result(spawn: SpawnResult) {
    println!("{}", format_spawn_result(&spawn));
}

/// ASCII board reproduction matching the layout of `Position::print_board`
/// (no diagonal lines).  Letters mirror the legacy notation: uppercase for
/// White (side 0), lowercase for Black (side 1), `.` for empty.
fn print_board_ascii(state: &GameStateSnapshot) {
    let board: [u8; 24] = {
        let mut b = [0_u8; 24];
        b.copy_from_slice(&state.opaque_payload[..24]);
        b
    };
    let glyph = |node: usize| -> char {
        match board[node] {
            1 => 'W',
            2 => 'B',
            _ => '.',
        }
    };
    let g = |n: usize| glyph(n);
    println!("{} ----- {} ----- {}", g(0), g(1), g(2));
    println!("|       |       |");
    println!("|  {} -- {} -- {}  |", g(8), g(9), g(10));
    println!("|  |     |     |  |");
    println!("|  |  {} {} {}  |  |", g(16), g(17), g(18));
    println!(
        "{} {} {}       {} {} {}",
        g(7),
        g(15),
        g(23),
        g(19),
        g(11),
        g(3)
    );
    println!("|  |  {} {} {}  |  |", g(22), g(21), g(20));
    println!("|  |     |     |  |");
    println!("|  {} -- {} -- {}  |", g(14), g(13), g(12));
    println!("|       |       |");
    println!("{} ----- {} ----- {}", g(6), g(5), g(4));
    println!("side: {}", side_label(state.side_to_move));
    println!("phase_tag: {}", state.phase_tag);
    println!("move_number: {}", state.move_number);
}

fn side_label(side: i8) -> &'static str {
    match side {
        0 => "white",
        1 => "black",
        _ => "none",
    }
}

fn print_uci_options() {
    // Mirrors master src/ucioption.cpp init() ordering (P1-A).
    println!("option name Threads type spin default 1 min 1 max 512");
    println!("option name Hash type spin default 16 min 1 max 33554432");
    println!("option name Clear Hash type button");
    println!("option name Ponder type check default false");
    println!("option name MultiPV type spin default 1 min 1 max 500");
    println!("option name SkillLevel type spin default 1 min 0 max 30");
    println!("option name MoveTime type spin default 1 min 0 max 60");
    println!("option name AiIsLazy type check default false");
    println!("option name Move Overhead type spin default 10 min 0 max 5000");
    println!("option name Slow Mover type spin default 100 min 10 max 1000");
    println!("option name nodestime type spin default 0 min 0 max 10000");
    println!("option name Shuffling type check default true");
    println!("option name UseLazySmp type check default false");
    println!("option name Algorithm type spin default 2 min 0 max 4");
    println!("option name DrawOnHumanExperience type check default true");
    println!("option name ConsiderMobility type check default true");
    println!("option name FocusOnBlockingPaths type check default true");
    println!("option name DeveloperMode type check default true");
    println!("option name MaxQuiescenceDepth type spin default 0 min 0 max 4");
    // Mill rule variant options (P1-A). Prefer master-compatible names.
    println!("option name PiecesCount type spin default 9 min 9 max 12");
    println!("option name flyPieceCount type spin default 3 min 3 max 4");
    println!("option name PiecesAtLeastCount type spin default 3 min 3 max 5");
    println!("option name HasDiagonalLines type check default false");
    println!("option name MillFormationActionInPlacingPhase type spin default 0 min 0 max 5");
    println!("option name MayMoveInPlacingPhase type check default false");
    println!("option name IsDefenderMoveFirst type check default false");
    println!("option name MayRemoveMultiple type check default false");
    println!("option name MayRemoveFromMillsAlways type check default false");
    println!("option name RestrictRepeatedMillsFormation type check default false");
    println!("option name OneTimeUseMill type check default false");
    println!("option name CustodianCaptureEnabled type check default false");
    println!("option name CustodianCaptureOnSquareEdges type check default true");
    println!("option name CustodianCaptureOnCrossLines type check default true");
    println!("option name CustodianCaptureOnDiagonalLines type check default true");
    println!("option name CustodianCaptureInPlacingPhase type check default true");
    println!("option name CustodianCaptureInMovingPhase type check default true");
    println!("option name CustodianCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name InterventionCaptureEnabled type check default false");
    println!("option name InterventionCaptureOnSquareEdges type check default true");
    println!("option name InterventionCaptureOnCrossLines type check default true");
    println!("option name InterventionCaptureOnDiagonalLines type check default true");
    println!("option name InterventionCaptureInPlacingPhase type check default true");
    println!("option name InterventionCaptureInMovingPhase type check default true");
    println!("option name InterventionCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name LeapCaptureEnabled type check default false");
    println!("option name LeapCaptureOnSquareEdges type check default true");
    println!("option name LeapCaptureOnCrossLines type check default true");
    println!("option name LeapCaptureOnDiagonalLines type check default true");
    println!("option name LeapCaptureInPlacingPhase type check default true");
    println!("option name LeapCaptureInMovingPhase type check default true");
    println!("option name LeapCaptureOnlyWhenOwnPiecesLeq3 type check default false");
    println!("option name BoardFullAction type spin default 0 min 0 max 4");
    println!("option name StopPlacingWhenTwoEmptySquares type check default false");
    println!("option name StalemateAction type spin default 0 min 0 max 5");
    println!("option name MayFly type check default true");
    println!("option name NMoveRule type spin default 100 min 10 max 200");
    println!("option name EndgameNMoveRule type spin default 100 min 5 max 200");
    println!("option name ThreefoldRepetitionRule type check default true");
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SetoptionResult {
    Variant,
    Threads,
    ClearHash,
    /// A non-variant search/engine parameter changed (e.g. SkillLevel).
    SearchConfig,
    /// Option is valid and stored but has no side-effect on game rules.
    Acknowledged,
    Unknown,
}

fn apply_setoption(
    line: &str,
    options: &mut MillVariantOptions,
    threads: &mut usize,
    qsearch_max_depth: &mut i32,
    engine_cfg: &mut EngineConfig,
) -> SetoptionResult {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let Some(name_pos) = tokens.iter().position(|t| *t == "name") else {
        return SetoptionResult::Unknown;
    };
    let value_pos = tokens.iter().position(|t| *t == "value");
    let name_end = value_pos.unwrap_or(tokens.len());
    if name_end <= name_pos + 1 {
        return SetoptionResult::Unknown;
    }
    let name = tokens[name_pos + 1..name_end]
        .join(" ")
        .to_ascii_lowercase();
    let value = match value_pos.and_then(|idx| tokens.get(idx + 1).copied()) {
        Some(value) => value,
        None if matches!(name.as_str(), "clear hash" | "clearhash") => "",
        None => return SetoptionResult::Unknown,
    };

    match name.as_str() {
        "threads" => {
            if let Some(n) = value.parse::<usize>().ok().filter(|n| (1..=64).contains(n)) {
                *threads = n;
                SetoptionResult::Threads
            } else {
                SetoptionResult::Unknown
            }
        }
        "maxquiescencedepth" | "max quiescence depth" => value
            .parse::<i32>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .map(|v| {
                *qsearch_max_depth = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Search / difficulty options (P1-A) ---
        "skilllevel" | "skill level" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=30).contains(v))
            .map(|v| {
                engine_cfg.skill_level = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "movetime" | "move time" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (0..=60).contains(v))
            .map(|v| {
                engine_cfg.move_time_secs = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "aiislazy" | "ai is lazy" => parse_bool(value)
            .map(|v| {
                engine_cfg.ai_is_lazy = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "algorithm" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .map(|v| {
                engine_cfg.algorithm = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "shuffling" => parse_bool(value)
            .map(|v| {
                engine_cfg.shuffling = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "uselazysmp" | "use lazy smp" => parse_bool(value)
            .map(|v| {
                engine_cfg.use_lazy_smp = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "drawonhumanexperience" | "draw on human experience" => parse_bool(value)
            .map(|v| {
                engine_cfg.draw_on_human_experience = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "developermode" | "developer mode" => parse_bool(value)
            .map(|v| {
                engine_cfg.developer_mode = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "considermobility" | "consider mobility" => parse_bool(value)
            .map(|v| {
                options.consider_mobility = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "focusonblockingpaths" | "focus on blocking paths" => parse_bool(value)
            .map(|v| {
                options.focus_on_blocking_paths = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "hash" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (1..=33_554_432).contains(v))
            .map(|v| {
                engine_cfg.hash_mb = v;
                SetoptionResult::SearchConfig
            })
            .unwrap_or(SetoptionResult::Unknown),
        "clear hash" | "clearhash" => SetoptionResult::ClearHash,
        "ponder" => parse_bool(value)
            .map(|v| {
                engine_cfg.ponder = v;
                SetoptionResult::Acknowledged
            })
            .unwrap_or(SetoptionResult::Unknown),
        "multipv" | "multi pv" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "move overhead" | "moveoverhead" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "slow mover" | "slowmover" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }
        "nodestime" | "nodes time" => {
            let _ = value.parse::<u32>();
            SetoptionResult::Acknowledged
        }

        // --- Mill variant rule options ---
        "piecescount" | "pieces count" | "piececount" | "piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (9..=12).contains(v))
            .map(|v| {
                options.piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "flypiececount" | "fly piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=4).contains(v))
            .map(|v| {
                options.fly_piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "piecesatleastcount" | "pieces at least count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=5).contains(v))
            .map(|v| {
                options.pieces_at_least_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayfly" | "may fly" => parse_bool(value)
            .map(|v| {
                options.may_fly = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "hasdiagonallines" | "has diagonal lines" => parse_bool(value)
            .map(|v| {
                options.has_diagonal_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "millformationactioninplacingphase" | "mill formation action in placing phase" => value
            .parse::<i16>()
            .ok()
            .filter(|v| (0..=5).contains(v))
            .and_then(|v| {
                use tgf_mill::MillFormationActionInPlacingPhase::*;
                let action = match v {
                    0 => RemoveOpponentsPieceFromBoard,
                    1 => RemoveOpponentsPieceFromHandThenOpponentsTurn,
                    2 => RemoveOpponentsPieceFromHandThenYourTurn,
                    3 => OpponentRemovesOwnPiece,
                    4 => MarkAndDelayRemovingPieces,
                    5 => RemovalBasedOnMillCounts,
                    _ => return None,
                };
                options.mill_formation_action_in_placing_phase = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayremovefrommillsalways" | "may remove from mills always" => parse_bool(value)
            .map(|v| {
                options.may_remove_from_mills_always = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "mayremovemultiple" | "may remove multiple" => parse_bool(value)
            .map(|v| {
                options.may_remove_multiple = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "nmoverule" | "n move rule" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (10..=200).contains(v))
            .map(|v| {
                options.n_move_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "endgamenmoverule" | "endgame n move rule" => value
            .parse::<u32>()
            .ok()
            .filter(|v| (5..=200).contains(v))
            .map(|v| {
                options.endgame_n_move_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "maymoveinplacingphase" | "may move in placing phase" => parse_bool(value)
            .map(|v| {
                options.may_move_in_placing_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "isdefendermovefirst" | "is defender move first" => parse_bool(value)
            .map(|v| {
                options.is_defender_move_first = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "restrictrepeatedmillsformation" | "restrict repeated mills formation" => parse_bool(value)
            .map(|v| {
                options.restrict_repeated_mills_formation = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "onetimeusemill" | "one time use mill" => parse_bool(value)
            .map(|v| {
                options.one_time_use_mill = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "stopplacingwhentwoEmptysquares"
        | "stopplacingwhentwoemptysquares"
        | "stop placing when two empty squares" => parse_bool(value)
            .map(|v| {
                options.stop_placing_when_two_empty_squares = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "boardfullaction" | "board full action" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=4).contains(v))
            .and_then(|v| {
                use tgf_mill::MillBoardFullAction::*;
                let action = match v {
                    0 => FirstPlayerLose,
                    1 => FirstAndSecondPlayerRemovePiece,
                    2 => SecondAndFirstPlayerRemovePiece,
                    3 => SideToMoveRemovePiece,
                    4 => AgreeToDraw,
                    _ => return None,
                };
                options.board_full_action = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "stalemateaction" | "stalemate action" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (0..=5).contains(v))
            .and_then(|v| {
                use tgf_mill::StalemateAction::*;
                let action = match v {
                    0 => EndWithStalemateLoss,
                    1 => ChangeSideToMove,
                    2 => RemoveOpponentsPieceAndMakeNextMove,
                    3 => RemoveOpponentsPieceAndChangeSideToMove,
                    4 => EndWithStalemateDraw,
                    5 => BothPlayersRemoveOpponentsPiece,
                    _ => return None,
                };
                options.stalemate_action = action;
                Some(SetoptionResult::Variant)
            })
            .unwrap_or(SetoptionResult::Unknown),
        "threefoldrepetitionrule" | "threefold repetition rule" => parse_bool(value)
            .map(|v| {
                options.threefold_repetition_rule = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Custodian capture sub-options ---
        "custodiancaptureenabled" | "custodian capture enabled" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureonsquareedges" | "custodian capture on square edges" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.on_square_edges = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureoncrosslines" | "custodian capture on cross lines" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.on_cross_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureondiagonallines" | "custodian capture on diagonal lines" => {
            parse_bool(value)
                .map(|v| {
                    options.custodian_capture.on_diagonal_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "custodiancaptureinplacingphase" | "custodian capture in placing phase" => {
            parse_bool(value)
                .map(|v| {
                    options.custodian_capture.in_placing_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "custodiancaptureinmovingphase" | "custodian capture in moving phase" => parse_bool(value)
            .map(|v| {
                options.custodian_capture.in_moving_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "custodiancaptureonlywhenownpiecesleq3"
        | "custodian capture only when own pieces leq 3" => parse_bool(value)
            .map(|v| {
                options
                    .custodian_capture
                    .only_available_when_own_pieces_leq3 = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Intervention capture sub-options ---
        "interventioncaptureenabled" | "intervention capture enabled" => parse_bool(value)
            .map(|v| {
                options.intervention_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "interventioncaptureonsquareedges" | "intervention capture on square edges" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_square_edges = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureoncrosslines" | "intervention capture on cross lines" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_cross_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureondiagonallines" | "intervention capture on diagonal lines" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.on_diagonal_lines = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureinplacingphase" | "intervention capture in placing phase" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.in_placing_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureinmovingphase" | "intervention capture in moving phase" => {
            parse_bool(value)
                .map(|v| {
                    options.intervention_capture.in_moving_phase = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        "interventioncaptureonlywhenownpiecesleq3"
        | "intervention capture only when own pieces leq 3" => parse_bool(value)
            .map(|v| {
                options
                    .intervention_capture
                    .only_available_when_own_pieces_leq3 = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),

        // --- Leap capture sub-options ---
        "leapcaptureenabled" | "leap capture enabled" => parse_bool(value)
            .map(|v| {
                options.leap_capture.enabled = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureonsquareedges" | "leap capture on square edges" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_square_edges = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureoncrosslines" | "leap capture on cross lines" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_cross_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureondiagonallines" | "leap capture on diagonal lines" => parse_bool(value)
            .map(|v| {
                options.leap_capture.on_diagonal_lines = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureinplacingphase" | "leap capture in placing phase" => parse_bool(value)
            .map(|v| {
                options.leap_capture.in_placing_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureinmovingphase" | "leap capture in moving phase" => parse_bool(value)
            .map(|v| {
                options.leap_capture.in_moving_phase = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "leapcaptureonlywhenownpiecesleq3" | "leap capture only when own pieces leq 3" => {
            parse_bool(value)
                .map(|v| {
                    options.leap_capture.only_available_when_own_pieces_leq3 = v;
                    SetoptionResult::Variant
                })
                .unwrap_or(SetoptionResult::Unknown)
        }
        _ => SetoptionResult::Unknown,
    }
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn parse_position_command(rules: &MillRules, line: &str) -> GameStateSnapshot {
    let tokens = line.split_whitespace().collect::<Vec<_>>();

    let moves_idx = tokens.iter().position(|t| *t == "moves");
    let mut state = match tokens.get(1).copied() {
        Some("startpos") => rules.initial_state(&[]),
        Some("fen") => {
            let fen_end = moves_idx.unwrap_or(tokens.len());
            let fen = tokens[2..fen_end].join(" ");
            match rules.set_from_fen(&fen) {
                Ok(state) => rules.encode_state(state),
                Err(e) => {
                    println!("info string invalid fen ignored: {e}");
                    rules.initial_state(&[])
                }
            }
        }
        _ => rules.initial_state(&[]),
    };

    let Some(moves_idx) = moves_idx else {
        return state;
    };
    for mv in tokens.iter().skip(moves_idx + 1) {
        if let Some(action) = action_from_uci(rules, &state, mv) {
            state = rules.apply(&state, action);
        } else {
            println!("info string illegal move ignored: {mv}");
            break;
        }
    }
    state
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GoOptions {
    depth: i32,
    movetime_ms: Option<u64>,
    node_limit: Option<u64>,
}

/// Parse a `go …` invocation supporting the full UCI `go` subcommand set:
/// `wtime`, `btime`, `winc`, `binc`, `movetime`, `depth`, `nodes`,
/// `infinite`, `ponder`.
///
/// P1-D: `wtime`/`btime` selection is now based on `root_side_to_move`
/// (0=white, 1=black), matching master's time-management semantics.
/// When no explicit `movetime` is given in the `go` command and no
/// wtime/btime is present, `move_time_secs` from `setoption MoveTime`
/// is used as a fallback (master's primary time-control mechanism).
fn parse_go_options(line: &str, root_side_to_move: i8, engine_cfg: &EngineConfig) -> GoOptions {
    let tokens = line.split_whitespace().collect::<Vec<_>>();

    let find_u64 = |key: &str| -> Option<u64> {
        tokens
            .windows(2)
            .find(|w| w[0] == key)
            .and_then(|w| w[1].parse::<u64>().ok())
    };
    let find_i32 = |key: &str| -> Option<i32> {
        tokens
            .windows(2)
            .find(|w| w[0] == key)
            .and_then(|w| w[1].parse::<i32>().ok())
    };

    if tokens.contains(&"infinite") || tokens.contains(&"ponder") {
        return GoOptions {
            depth: 64,
            movetime_ms: None,
            node_limit: None,
        };
    }

    let depth = find_i32("depth").unwrap_or(0).max(0);
    let node_limit = find_u64("nodes");

    // Explicit go movetime takes highest priority.
    let movetime_ms = if let Some(ms) = find_u64("movetime") {
        Some(ms)
    } else {
        // P1-D: select wtime/btime based on side_to_move (matching master
        // SearchEngine time-management which uses the correct clock for
        // the player to move).
        let (time_key, inc_key) = if root_side_to_move == 1 {
            ("btime", "binc")
        } else {
            ("wtime", "winc")
        };
        let remaining = find_u64(time_key);
        if let Some(r) = remaining {
            let increment = find_u64(inc_key).unwrap_or(0);
            Some((r / 30).saturating_add(increment).max(100))
        } else if engine_cfg.move_time_secs > 0 {
            // Fall back to setoption MoveTime (master's primary mechanism).
            Some(engine_cfg.move_time_secs as u64 * 1000)
        } else {
            None
        }
    };

    GoOptions {
        depth,
        movetime_ms,
        node_limit,
    }
}

fn action_from_uci(rules: &MillRules, state: &GameStateSnapshot, move_uci: &str) -> Option<Action> {
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(state, &mut actions);
    actions
        .into_iter()
        .find(|a| action_to_uci(*a).as_deref() == Some(move_uci))
}

fn action_to_uci(action: Action) -> Option<String> {
    let topo = default_mill_topology();
    match action.kind_tag {
        x if x == MillActionKind::Place as i16 => {
            Some(topo.label_of(action.to_node as u16).to_owned())
        }
        x if x == MillActionKind::Move as i16 => Some(format!(
            "{}-{}",
            topo.label_of(action.from_node as u16),
            topo.label_of(action.to_node as u16)
        )),
        x if x == MillActionKind::Remove as i16 => {
            Some(format!("x{}", topo.label_of(action.to_node as u16)))
        }
        _ => None,
    }
}

fn print_benchmark_toml() {
    let git_commit = option_env!("GIT_COMMIT").unwrap_or("");
    let platform = format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH);

    let rules = MillRules::default();
    let game = MillGame::default();
    let snap = rules.initial_state(&[]);

    let mut wb = game.build_workbench(&snap);
    let start_d1 = perft::<MillGame>(&mut wb, 1);
    let mut wb = game.build_workbench(&snap);
    let start_d2 = perft::<MillGame>(&mut wb, 2);
    let mid_snap = rules.no_mill_moving_phase_snapshot();
    let mut wb = game.build_workbench(&mid_snap);
    let mid_d3 = perft::<MillGame>(&mut wb, 3);

    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher();
    let start = Instant::now();
    let result = searcher.search(&mut wb, 4);
    let _ = searcher.search(&mut wb, 4);
    let elapsed = start.elapsed().max(Duration::from_micros(1));
    let depth_ms = elapsed.as_millis() as u64;
    let nps = (result.nodes as f64 / elapsed.as_secs_f64()).round() as u64;
    let tt_hit_rate_pct = searcher.tt_hit_rate_pct();
    let tt_age_bumps = searcher.tt_age_bumps();
    let tt_current_age = searcher.tt_current_age();

    let cold_start_begin = Instant::now();
    let mut wb = game.build_workbench(&snap);
    let mut searcher = mill_searcher();
    let _ = searcher.search(&mut wb, 1);
    let first_move_ms = cold_start_begin.elapsed().as_millis() as u64;

    let smp_workers = vec![
        LazySmpWorker { extra_depth: 0 },
        LazySmpWorker { extra_depth: 1 },
    ];
    let smp_shared_tt = SharedTt::new(tt_cluster_bits_from_env());
    let smp_start = Instant::now();
    let smp_result = lazy_smp_search::<MillGame>(
        game.clone(),
        snap,
        4,
        &smp_workers,
        SearchOptions::default(),
        smp_shared_tt,
        None,
    );
    let smp_elapsed = smp_start.elapsed().max(Duration::from_micros(1));
    let smp_ms = smp_elapsed.as_millis() as u64;
    let smp_nps = (smp_result.nodes as f64 / smp_elapsed.as_secs_f64()).round() as u64;

    println!("[meta]");
    println!("locked_at   = \"\"");
    println!("git_commit  = \"{}\"", git_commit);
    println!("platform    = \"{}\"", platform);
    println!(
        "tt_cluster_bits = {}  # set TGF_TT_CLUSTER_BITS to override",
        tt_cluster_bits_from_env()
    );
    println!("build_flags = \"cargo bench scaffold\"");
    println!("tt_age_bumps   = {}", tt_age_bumps);
    println!("tt_current_age = {}", tt_current_age);
    println!();
    println!("[baseline]");
    println!("nps = {}", nps);
    println!("depth10_ms = {}", depth_ms);
    println!();
    println!("[baseline.perft]");
    println!("start_d1 = {}", start_d1);
    println!("start_d2 = {}", start_d2);
    println!("mid_d3 = {}", mid_d3);
    println!();
    println!("[baseline.tt]");
    println!("hit_rate_pct = {:.3}", tt_hit_rate_pct);
    println!("age_bumps = {}", tt_age_bumps);
    println!("current_age = {}", tt_current_age);
    println!();
    println!("[baseline.startup]");
    println!("first_move_ms = {}", first_move_ms);
    println!();
    println!("[baseline.smp]");
    println!("workers = {}", smp_workers.len());
    println!("base_depth = 4");
    println!("nps = {}", smp_nps);
    println!("depth_ms = {}", smp_ms);

    // MCTS baseline: 50 self-play games, fixed seed, compare random rollout
    // vs α-β-assisted simulation at depth 1.
    const MCTS_GAMES: u32 = 50;
    const MCTS_SEED: u64 = 0xBEEF_CAFE_0123_4567;
    let mcts_ab0_wins = run_mcts_self_play(MCTS_GAMES, MCTS_SEED, 0);
    let mcts_ab1_wins = run_mcts_self_play(MCTS_GAMES, MCTS_SEED, 1);
    println!();
    println!("[baseline.mcts]");
    println!("games = {}", MCTS_GAMES);
    println!("iterations_per_move = 32");
    println!("ab_assist_depth_0_wins = {}", mcts_ab0_wins);
    println!("ab_assist_depth_1_wins = {}", mcts_ab1_wins);
}

/// Play `games` self-play games using MCTS where both sides use
/// `ab_assist_depth`.  Returns the number of wins for side 0 (White).
/// Both sides share the same options; the AB-assist advantage is symmetric
/// so the win-rate measures absolute quality vs random rollout (ab_depth=0).
fn run_mcts_self_play(games: u32, seed: u64, ab_assist_depth: i32) -> u32 {
    let rules = MillRules::default();
    let game = MillGame::default();
    let policy = SearchPolicy {
        remove_kind_tag: Some(MillActionKind::Remove as i16),
    };
    let mut wins = 0u32;
    for g in 0..games {
        let mut snap = rules.initial_state(&[]);
        let mut mcts = MctsSearcher::<MillGame>::new();
        mcts.set_random_seed(seed.wrapping_add(u64::from(g)));
        mcts.set_policy(policy);
        let options = MctsOptions {
            iterations: 32,
            playout_depth: 4,
            time_limit_ms: None,
            exploration: 0.5,
            ab_assist_depth,
        };
        for _ in 0..120 {
            use tgf_core::GameRules;
            let outcome = rules.outcome(&snap);
            if matches!(
                outcome.kind,
                tgf_core::OutcomeKind::Win(_) | tgf_core::OutcomeKind::Draw
            ) {
                if let tgf_core::OutcomeKind::Win(w) = outcome.kind {
                    if w == 0 {
                        wins += 1;
                    }
                }
                break;
            }
            let mut wb = game.build_workbench(&snap);
            let result = mcts.search_with_options(&mut wb, options);
            if result.best_action.is_none() {
                break;
            }
            snap = rules.apply(&snap, result.best_action);
        }
    }
    wins
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_position_fen_loads_board() {
        let rules = MillRules::default();
        let state = parse_position_command(
            &rules,
            "position fen O@******/********/******** w p p 1 8 1 8 0 0 0 0 0 0 0 0 1",
        );

        // FEN position 0/1 are legacy sq 8/9, which map to dense nodes 17/18.
        assert_eq!(state.opaque_payload[17], 1);
        assert_eq!(state.opaque_payload[18], 2);
        assert_eq!(state.side_to_move, 0);
    }

    #[test]
    fn parse_position_fen_with_moves_applies_tail_moves() {
        let rules = MillRules::default();
        let state = parse_position_command(
            &rules,
            "position fen ********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1 moves d7",
        );

        assert_eq!(state.opaque_payload[1], 1); // d7 / node 1
        assert_eq!(state.side_to_move, 1);
    }

    #[test]
    fn setoption_accepts_legacy_piece_count_names() {
        let mut options = MillVariantOptions::default();
        let mut threads = 1;
        let mut qsearch = 0;
        let mut ecfg = EngineConfig::default();

        assert!(matches!(
            apply_setoption(
                "setoption name PiecesCount value 12",
                &mut options,
                &mut threads,
                &mut qsearch,
                &mut ecfg,
            ),
            SetoptionResult::Variant
        ));
        assert_eq!(options.piece_count, 12);

        assert!(matches!(
            apply_setoption(
                "setoption name flyPieceCount value 4",
                &mut options,
                &mut threads,
                &mut qsearch,
                &mut ecfg,
            ),
            SetoptionResult::Variant
        ));
        assert_eq!(options.fly_piece_count, 4);
    }

    #[test]
    fn engine_config_algorithm_routes_search() {
        let rules = MillRules::default();
        let snap = rules.initial_state(&[]);
        let cfg = EngineConfig {
            algorithm: 4,
            shuffling: false,
            ..EngineConfig::default()
        };
        let mut searcher = mill_searcher();
        let result =
            run_configured_search(MillVariantOptions::default(), snap, 1, &cfg, &mut searcher);

        assert!(
            !result.best_action.is_none(),
            "random algorithm path must still return a best move"
        );
        assert_eq!(result.score, 0, "random path returns a neutral score");
    }

    #[test]
    fn default_go_depth_uses_recommended_depth() {
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.initial_state(&[]);
        let cfg = EngineConfig {
            skill_level: 5,
            draw_on_human_experience: false,
            developer_mode: false,
            ..EngineConfig::default()
        };

        let go = parse_go_options("go", snap.side_to_move, &cfg);
        assert_eq!(go.depth, 0, "missing depth is represented as auto");
        let depth = effective_search_depth(&options, &snap, go.depth, &cfg);
        assert_eq!(depth, 5);
    }

    #[test]
    fn clear_hash_button_does_not_require_value() {
        let mut options = MillVariantOptions::default();
        let mut threads = 1;
        let mut qsearch = 0;
        let mut ecfg = EngineConfig::default();

        assert_eq!(
            apply_setoption(
                "setoption name Clear Hash",
                &mut options,
                &mut threads,
                &mut qsearch,
                &mut ecfg,
            ),
            SetoptionResult::ClearHash
        );
    }

    #[test]
    fn lazy_smp_requires_explicit_option() {
        let mut cfg = EngineConfig::default();
        assert!(!cfg.use_lazy_smp);

        let mut options = MillVariantOptions::default();
        let mut threads = 1;
        let mut qsearch = 0;
        assert_eq!(
            apply_setoption(
                "setoption name UseLazySmp value true",
                &mut options,
                &mut threads,
                &mut qsearch,
                &mut cfg,
            ),
            SetoptionResult::SearchConfig
        );
        assert!(cfg.use_lazy_smp);
    }

    #[test]
    fn active_search_try_take_finished_emits_without_followup_command() {
        let (tx, rx) = mpsc::channel();
        let handle = thread::spawn(move || {
            tx.send(SpawnResult {
                depth: 1,
                result: SearchResult {
                    best_action: Action {
                        kind_tag: MillActionKind::Place as i16,
                        from_node: -1,
                        to_node: 0,
                        aux: -1,
                        payload_bits: 0,
                    },
                    score: 5,
                    nodes: 1,
                },
                root_side_to_move: 0,
            })
            .unwrap();
        });
        let mut active = Some(ActiveSearch {
            handle,
            abort_handle: SearchAbortHandle::from_arc(Arc::new(AtomicBool::new(false))),
            receiver: rx,
        });

        let mut result = None;
        for _ in 0..100 {
            if let Some(spawn) = take_finished_search(&mut active) {
                result = Some(format_spawn_result(&spawn));
                break;
            }
            thread::sleep(Duration::from_millis(1));
        }

        assert!(active.is_none(), "finished search must be drained");
        assert_eq!(
            result.as_deref(),
            Some("info depth 1 score cp 5 nodes 1 bestmove a7")
        );
    }
}
