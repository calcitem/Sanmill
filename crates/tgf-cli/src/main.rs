// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.

use std::io::{self, BufRead};
use std::time::{Duration, Instant};

use tgf_core::{Action, ActionList, BoardTopology, Game, GameRules, GameStateSnapshot};
use tgf_mill::{default_mill_topology, MillActionKind, MillGame, MillRules};
use tgf_search::{perft, SearchOptions, Searcher};

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
    let rules = MillRules::default();
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
            println!("uciok");
        } else if line == "isready" {
            println!("readyok");
        } else if line == "ucinewgame" {
            state = rules.initial_state(&[]);
        } else if line.starts_with("position") {
            state = parse_position_command(&rules, line);
        } else if line.starts_with("go") {
            let go = parse_go_options(line);
            let game = MillGame::default();
            let mut wb = game.build_workbench(&state);
            let mut searcher = Searcher::<MillGame>::new();
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
    let mut searcher = Searcher::<MillGame>::new();
    let start = Instant::now();
    let result = searcher.search(&mut wb, 4);
    let _ = searcher.search(&mut wb, 4);
    let elapsed = start.elapsed().max(Duration::from_micros(1));
    let depth_ms = elapsed.as_millis() as u64;
    let nps = (result.nodes as f64 / elapsed.as_secs_f64()).round() as u64;
    let tt_hit_rate_pct = searcher.tt_hit_rate_pct();

    let cold_start_begin = Instant::now();
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    let _ = searcher.search(&mut wb, 1);
    let first_move_ms = cold_start_begin.elapsed().as_millis() as u64;

    println!("[meta]");
    println!("locked_at   = \"\"");
    println!("git_commit  = \"{}\"", git_commit);
    println!("platform    = \"{}\"", platform);
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
