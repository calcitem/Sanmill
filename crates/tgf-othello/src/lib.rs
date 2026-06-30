// SPDX-License-Identifier: AGPL-3.0-or-later
// Othello/Reversi pressure-test implementation for TGF.
//
// This crate exists so the framework's hot-path traits (`Game`,
// `Workbench`, `Evaluator`) and FRB session machinery have a second
// concrete game beyond Mill — adding a third game is then mostly a
// matter of copying the file layout below:
//
//   - `topology`    — `OthelloTopology` plus `idx` / `in_bounds` helpers.
//   - `state`       — `OthelloState` POD + encode / decode / apply
//                     (`apply_othello_action`) + Zobrist key.
//   - `rules`       — `OthelloRules` and the `GameRules` trait impl.
//   - `game`        — `OthelloGame` / `OthelloWorkbench` / `OthelloEvaluator`
//                     and the `Game` / `Workbench` / `Evaluator` trait
//                     implementations (the search-hot-path surface).
//
// Only one piece of public API leaks across modules: `OthelloActionKind`,
// which is needed by both `rules` (legal action emission) and any
// future external action codec.

mod game;
mod rules;
mod state;
mod topology;

pub use game::{OthelloEvaluator, OthelloGame, OthelloWorkbench};
pub use rules::OthelloRules;
pub use topology::OthelloTopology;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i16)]
pub enum OthelloActionKind {
    Place = 0,
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::{ActionList, Game, GameRules};
    use tgf_search::{Searcher, perft};

    #[test]
    fn initial_othello_has_four_legal_actions() {
        let rules = OthelloRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        assert_eq!(actions.len(), 4);
    }

    #[test]
    fn applying_opening_action_flips_one_disc() {
        let rules = OthelloRules::default();
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let next = rules.apply(&snap, actions[0]);
        let state = crate::state::decode(&next);
        let black = state.board.iter().filter(|p| **p == 1).count();
        let white = state.board.iter().filter(|p| **p == 2).count();
        assert_eq!(black, 4);
        assert_eq!(white, 1);
    }

    #[test]
    fn searcher_works_with_othello_game() {
        let rules = OthelloRules::default();
        let game = OthelloGame;
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        assert_eq!(perft::<OthelloGame>(&mut wb, 1), 4);
        let mut searcher = Searcher::<OthelloGame>::new();
        let result = searcher.search(&mut wb, 1);
        assert!(!result.best_action.is_none());
    }

    #[test]
    fn topology_chess_labels_round_trip() {
        let t = OthelloTopology::default();
        let topo: &dyn tgf_core::BoardTopology = &t;
        assert_eq!(topo.label_of(0), "a8");
        assert_eq!(topo.node_from_label("a8"), Some(0));
        assert_eq!(topo.node_from_label("e4"), Some(36));
        assert_eq!(topo.label_of(36), "e4");
        assert_eq!(topo.neighbors(0).len(), 3);
        assert_eq!(topo.line_groups().len(), 16);
        assert_eq!(topo.line_groups()[0].len(), 8);
    }
}
