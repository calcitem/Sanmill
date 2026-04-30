// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.

use std::io::{self, BufRead};
use std::sync::atomic::AtomicBool;
use std::sync::{mpsc, Arc};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules, GameStateSnapshot};
use tgf_mill::{default_mill_topology, MillActionKind, MillGame, MillRules, MillVariantOptions};
use tgf_search::{
    lazy_smp_search, perft, LazySmpWorker, SearchAbortHandle, SearchOptions, SearchPolicy,
    SearchResult, Searcher, SharedTt,
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

fn run_uci_loop() {
    let mut options = MillVariantOptions::default();
    let mut rules = MillRules::new(options.clone());
    let mut state = rules.initial_state(&[]);
    let mut threads: usize = 1;
    let mut active_search: Option<ActiveSearch> = None;
    let stdin = io::stdin();
    for line in stdin.lock().lines().map_while(Result::ok) {
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
        } else if line.starts_with("setoption") {
            finish_active_search(&mut active_search);
            match apply_setoption(line, &mut options, &mut threads) {
                SetoptionResult::Variant => {
                    rules = MillRules::new(options.clone());
                    state = rules.initial_state(&[]);
                }
                SetoptionResult::Threads => {}
                SetoptionResult::Unknown => {
                    println!("info string unsupported setoption: {line}");
                }
            }
        } else if line.starts_with("position") {
            finish_active_search(&mut active_search);
            state = parse_position_command(&rules, line);
        } else if line == "d" {
            print_board_ascii(&state);
        } else if line.starts_with("go") {
            finish_active_search(&mut active_search);
            let go = parse_go_options(line);
            active_search = Some(spawn_search(options.clone(), state, go, threads));
        } else if line == "stop" {
            if let Some(active) = active_search.take() {
                active.abort_handle.request_abort();
                join_and_print(active);
            } else {
                println!("bestmove (none)");
            }
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
}

fn spawn_search(
    options: MillVariantOptions,
    state: GameStateSnapshot,
    go: GoOptions,
    threads: usize,
) -> ActiveSearch {
    let search_options = SearchOptions {
        depth_extension: false,
        node_limit: go.node_limit,
        time_limit_ms: go.movetime_ms,
    };
    let depth = go.depth;
    let (tx, rx) = mpsc::channel();
    let abort = Arc::new(AtomicBool::new(false));
    let abort_handle = SearchAbortHandle::from_arc(Arc::clone(&abort));

    let handle = if threads <= 1 {
        let abort_for_worker = Arc::clone(&abort);
        thread::spawn(move || {
            let mut searcher = mill_searcher();
            searcher.set_abort_flag(abort_for_worker);
            searcher.set_options(search_options);
            let game = MillGame::new(options);
            let mut wb = game.build_workbench(&state);
            let result = searcher.search_pvs(&mut wb, depth);
            let _ = tx.send(SpawnResult { depth, result });
        })
    } else {
        let abort_for_workers = Arc::clone(&abort);
        thread::spawn(move || {
            let workers: Vec<LazySmpWorker> = (0..threads)
                .map(|i| LazySmpWorker {
                    extra_depth: (i % 2) as i32,
                })
                .collect();
            let shared_tt = SharedTt::new(tt_cluster_bits_from_env());
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
            let _ = tx.send(SpawnResult { depth, result });
        })
    };

    ActiveSearch {
        handle,
        abort_handle,
        receiver: rx,
    }
}

fn finish_active_search(slot: &mut Option<ActiveSearch>) {
    if let Some(active) = slot.take() {
        join_and_print(active);
    }
}

fn join_and_print(active: ActiveSearch) {
    let _ = active.handle.join();
    if let Ok(spawn) = active.receiver.recv() {
        println!(
            "info depth {} score cp {} nodes {}",
            spawn.depth, spawn.result.score, spawn.result.nodes
        );
        println!(
            "bestmove {}",
            action_to_uci(spawn.result.best_action).unwrap_or_else(|| "(none)".to_owned())
        );
    } else {
        println!("bestmove (none)");
    }
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
    println!("option name PieceCount type spin default 9 min 3 max 12");
    println!("option name FlyPieceCount type spin default 3 min 3 max 3");
    println!("option name PiecesAtLeastCount type spin default 3 min 2 max 3");
    println!("option name MayFly type check default true");
    println!("option name HasDiagonalLines type check default false");
    println!("option name Threads type spin default 1 min 1 max 64");
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SetoptionResult {
    Variant,
    Threads,
    Unknown,
}

fn apply_setoption(
    line: &str,
    options: &mut MillVariantOptions,
    threads: &mut usize,
) -> SetoptionResult {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let Some(name_pos) = tokens.iter().position(|t| *t == "name") else {
        return SetoptionResult::Unknown;
    };
    let Some(value_pos) = tokens.iter().position(|t| *t == "value") else {
        return SetoptionResult::Unknown;
    };
    if value_pos <= name_pos + 1 || value_pos + 1 >= tokens.len() {
        return SetoptionResult::Unknown;
    }
    let name = tokens[name_pos + 1..value_pos]
        .join(" ")
        .to_ascii_lowercase();
    let value = tokens[value_pos + 1];

    match name.as_str() {
        "threads" => {
            if let Some(n) = value.parse::<usize>().ok().filter(|n| (1..=64).contains(n)) {
                *threads = n;
                SetoptionResult::Threads
            } else {
                SetoptionResult::Unknown
            }
        }
        "piececount" | "piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=12).contains(v))
            .map(|v| {
                options.piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "flypiececount" | "fly piece count" => value
            .parse::<u8>()
            .ok()
            .map(|v| {
                options.fly_piece_count = v;
                SetoptionResult::Variant
            })
            .unwrap_or(SetoptionResult::Unknown),
        "piecesatleastcount" | "pieces at least count" => value
            .parse::<u8>()
            .ok()
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
    let mut state = rules.initial_state(&[]);
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    if tokens.get(1).copied() != Some("startpos") {
        return state;
    }
    let Some(moves_idx) = tokens.iter().position(|t| *t == "moves") else {
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

/// Parse a `go [depth N] [movetime MS] [nodes N] [infinite]` invocation.
///
/// `infinite` selects the largest representable depth and clears any time /
/// node limits, so the caller is expected to send `stop` to terminate the
/// search via the abort handle exposed on [`Searcher`].
fn parse_go_options(line: &str) -> GoOptions {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let depth = tokens
        .windows(2)
        .find(|w| w[0] == "depth")
        .and_then(|w| w[1].parse::<i32>().ok())
        .unwrap_or(1)
        .max(1);
    let movetime_ms = tokens
        .windows(2)
        .find(|w| w[0] == "movetime")
        .and_then(|w| w[1].parse::<u64>().ok());
    let node_limit = tokens
        .windows(2)
        .find(|w| w[0] == "nodes")
        .and_then(|w| w[1].parse::<u64>().ok());
    if tokens.contains(&"infinite") {
        // Cap "infinite" at a depth far beyond any practical Mill search so
        // recursion stays bounded; cancellation comes from the `stop` command
        // through the abort handle rather than reaching the depth limit.
        return GoOptions {
            depth: 64,
            movetime_ms: None,
            node_limit: None,
        };
    }
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
    println!();
    println!("[baseline.startup]");
    println!("first_move_ms = {}", first_move_ms);
    println!();
    println!("[baseline.smp]");
    println!("workers = {}", smp_workers.len());
    println!("base_depth = 4");
    println!("nps = {}", smp_nps);
    println!("depth_ms = {}", smp_ms);
}
