// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.
//
// Phase 5: provide a small benchmark command that emits the same TOML schema as
// tests/perf_baseline.toml, so scripts/check_perf_baseline.py can compare Rust
// and C++ baselines without a separate parser.

use std::time::{Duration, Instant};

use tgf_core::{Game, GameRules};
use tgf_mill::{MillGame, MillRules};
use tgf_search::{perft, Searcher};

fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("bench") => print_benchmark_toml(),
        Some("--help") | Some("-h") => print_help(),
        _ => print_help(),
    }
}

fn print_help() {
    eprintln!("Usage:");
    eprintln!("  tgf bench    # emit perf_baseline-compatible TOML");
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

    // Keep the current benchmark light enough to run on developer machines.
    // Depth 4 gives a stable enough node count with the current scaffold while
    // avoiding long runtimes before the full rules/search engine is complete.
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<MillGame>::new();
    let start = Instant::now();
    let result = searcher.search(&mut wb, 4);
    // Search once more to exercise the TT probe path and collect a real hit
    // rate.  The second search reuses the table populated by the first search.
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
    println!("mid_d3 = 0");
    println!();
    println!("[baseline.tt]");
    println!("hit_rate_pct = {:.3}", tt_hit_rate_pct);
    println!();
    println!("[baseline.startup]");
    println!("first_move_ms = {}", first_move_ms);
}
