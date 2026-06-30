// SPDX-License-Identifier: AGPL-3.0-or-later
// Registry of game front-ends available to tgf-cli.
//
// Adding another game should normally mean adding a sibling module and one
// entry in `GAMES`; command parsing in `main.rs` stays unchanged.

use crate::game_adapter::CliGame;

mod mill;

static GAMES: [&'static dyn CliGame; 1] = [&mill::MILL_GAME];

pub(crate) fn all() -> &'static [&'static dyn CliGame] {
    &GAMES
}

pub(crate) fn default_game() -> &'static dyn CliGame {
    &mill::MILL_GAME
}

pub(crate) fn find(token: &str) -> Option<&'static dyn CliGame> {
    all().iter().copied().find(|game| game.matches_game(token))
}
