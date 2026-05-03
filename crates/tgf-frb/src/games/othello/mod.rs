// SPDX-License-Identifier: GPL-3.0-or-later
// Othello-specific FRB adapter helpers.  Currently a thin set of smoke
// helpers used by the FRB entry points in `crate::api::simple`.

use tgf_core::{ActionList, Game, GameRules};
use tgf_othello::{OthelloGame, OthelloRules};
use tgf_search::Searcher;

/// Number of legal actions from the Rust-native Othello initial position.
pub(crate) fn initial_legal_count() -> u32 {
    let rules = OthelloRules::default();
    let snap = rules.initial_state(&[]);
    let mut actions = ActionList::<256>::new();
    rules.legal_actions(&snap, &mut actions);
    actions.len() as u32
}

/// Run the generic Rust `Searcher<OthelloGame>` for one ply and return
/// the selected destination node id.
pub(crate) fn search_depth_one_best_to_node() -> i32 {
    let rules = OthelloRules::default();
    let game = OthelloGame;
    let snap = rules.initial_state(&[]);
    let mut wb = game.build_workbench(&snap);
    let mut searcher = Searcher::<OthelloGame>::new();
    searcher.search(&mut wb, 1).best_action.to_node as i32
}
