// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.

use std::io::{self, BufRead};
use std::time::{Duration, Instant};

use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules, GameStateSnapshot};
use tgf_mill::{default_mill_topology, MillActionKind, MillGame, MillRules, MillVariantOptions};
use tgf_search::{perft, SearchOptions, SearchPolicy, Searcher};

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
            state = rules.initial_state(&[]);
        } else if line.starts_with("setoption") {
            if apply_setoption(line, &mut options) {
                rules = MillRules::new(options.clone());
                state = rules.initial_state(&[]);
            } else {
                println!("info string unsupported setoption: {line}");
            }
        } else if line.starts_with("position") {
            state = parse_position_command(&rules, line);
        } else if line.starts_with("go") {
            let go = parse_go_options(line);
            let game = MillGame::new(options.clone());
            let mut wb = game.build_workbench(&state);
            let mut searcher = mill_searcher();
            searcher.set_options(SearchOptions {
                depth_extension: false,
                node_limit: None,
                time_limit_ms: go.movetime_ms,
            });
            let result = searcher.search_pvs(&mut wb, go.depth);
            println!(
                "info depth {} score cp {} nodes {}",
                go.depth, result.score, result.nodes
            );
            println!(
                "bestmove {}",
                action_to_uci(result.best_action).unwrap_or_else(|| "(none)".to_owned())
            );
        } else if line == "stop" {
            println!("bestmove (none)");
        } else if line == "quit" {
            break;
        } else {
            println!("info string unknown command: {line}");
        }
    }
}

fn print_uci_options() {
    println!("option name PieceCount type spin default 9 min 3 max 12");
    println!("option name FlyPieceCount type spin default 3 min 3 max 3");
    println!("option name PiecesAtLeastCount type spin default 3 min 2 max 3");
    println!("option name MayFly type check default true");
    println!("option name HasDiagonalLines type check default false");
}

fn apply_setoption(line: &str, options: &mut MillVariantOptions) -> bool {
    let tokens = line.split_whitespace().collect::<Vec<_>>();
    let Some(name_pos) = tokens.iter().position(|t| *t == "name") else {
        return false;
    };
    let Some(value_pos) = tokens.iter().position(|t| *t == "value") else {
        return false;
    };
    if value_pos <= name_pos + 1 || value_pos + 1 >= tokens.len() {
        return false;
    }
    let name = tokens[name_pos + 1..value_pos]
        .join(" ")
        .to_ascii_lowercase();
    let value = tokens[value_pos + 1];
    match name.as_str() {
        "piececount" | "piece count" => value
            .parse::<u8>()
            .ok()
            .filter(|v| (3..=12).contains(v))
            .is_some_and(|v| {
                options.piece_count = v;
                true
            }),
        "flypiececount" | "fly piece count" => value.parse::<u8>().ok().is_some_and(|v| {
            options.fly_piece_count = v;
            true
        }),
        "piecesatleastcount" | "pieces at least count" => {
            value.parse::<u8>().ok().is_some_and(|v| {
                options.pieces_at_least_count = v;
                true
            })
        }
        "mayfly" | "may fly" => parse_bool(value).is_some_and(|v| {
            options.may_fly = v;
            true
        }),
        "hasdiagonallines" | "has diagonal lines" => parse_bool(value).is_some_and(|v| {
            options.has_diagonal_lines = v;
            true
        }),
        _ => false,
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
}

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
    GoOptions { depth, movetime_ms }
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
}
