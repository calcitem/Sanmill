// SPDX-License-Identifier: AGPL-3.0-or-later
// `OthelloGame` plus its `Workbench` / `Evaluator` / `Game` trait
// implementations — the search-side compile-time monomorphisation
// surface that the generic `Searcher<G: Game>` consumes.

use tgf_core::{ActionList, Evaluator, Game, GameStateSnapshot, SearchActionList, Workbench};

use crate::rules::OthelloRules;
use crate::state::{OthelloState, apply_othello_action, decode, encode, othello_key};

#[derive(Clone, Debug, Default)]
pub struct OthelloGame;

#[derive(Clone, Debug)]
pub struct OthelloWorkbench {
    state: OthelloState,
    undo_stack: Vec<OthelloState>,
}

pub struct OthelloEvaluator;

impl Workbench for OthelloWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        encode(self.state)
    }

    fn key(&self) -> u64 {
        othello_key(&self.state)
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        let mut list = ActionList::<256>::new();
        OthelloRules::legal_actions_for(&self.state, &mut list);
        list.is_empty()
    }

    fn do_move(&mut self, a: tgf_core::Action) {
        self.undo_stack.push(self.state);
        apply_othello_action(&mut self.state, a);
    }

    fn undo_move(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.state = prev;
        }
    }
}

impl Evaluator<OthelloWorkbench> for OthelloEvaluator {
    fn score(wb: &OthelloWorkbench) -> i32 {
        let own = wb.state.side_to_move + 1;
        let opp = (wb.state.side_to_move ^ 1) + 1;
        let own_count = wb.state.board.iter().filter(|p| **p == own).count() as i32;
        let opp_count = wb.state.board.iter().filter(|p| **p == opp).count() as i32;
        (own_count - opp_count) * 100
    }
}

impl Game for OthelloGame {
    type Workbench = OthelloWorkbench;
    type Evaluator = OthelloEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        OthelloWorkbench {
            state: decode(snap),
            undo_stack: Vec::new(),
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut SearchActionList) {
        OthelloRules::legal_actions_for(&wb.state, out);
    }
}
