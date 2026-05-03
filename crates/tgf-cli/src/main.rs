// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.
//
// The binary is currently a Mill-only UCI / benchmark front-end; the
// implementation lives in `mill_uci.rs` so adding a second game (e.g.
// Othello) is a matter of dropping in a sibling module and extending the
// dispatch below.  Keeping `main.rs` thin keeps that future migration
// from touching the entry point.

mod mill_uci;
mod selfplay;
mod uci_adapter;

fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("bench") => mill_uci::print_benchmark_toml(),
        Some("uci") => mill_uci::run_uci_loop(),
        Some("selfplay") => selfplay::run_selfplay(),
        Some("--help") | Some("-h") => print_help(),
        _ => print_help(),
    }
}

fn print_help() {
    eprintln!("Usage:");
    eprintln!("  tgf bench       # emit perf_baseline-compatible TOML");
    eprintln!("  tgf uci         # run minimal UCI-like loop backed by Rust Mill");
    eprintln!("  tgf selfplay    # deterministic self-play harness for regressions");
    eprintln!("                  # args: --depth N --max-games N --algorithm pvs|alphabeta");
}
