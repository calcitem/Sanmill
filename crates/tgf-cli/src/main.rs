// SPDX-License-Identifier: GPL-3.0-or-later
// tgf-cli – command-line utilities for the Rust TGF engine.
//
// `main.rs` is intentionally game-neutral.  Concrete games register their
// command surface under `games/`, so adding a new game should not require
// touching this entry point.

mod cli;
mod game_adapter;
mod games;
mod mill_tune;
mod mill_uci;
mod selfplay;

fn main() {
    cli::run(std::env::args().skip(1));
}
