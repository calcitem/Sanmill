// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// The hot path is generic over `G: Game`; it never stores `dyn GameRules` or
// `dyn Workbench`.  This mirrors the C++ CRTP design in the migration plan and
// keeps do/undo/evaluate calls statically dispatchable.

use std::marker::PhantomData;

use tgf_core::{Action, ActionList, Evaluator, Game, Workbench};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchResult {
    pub best_action: Action,
    pub score: i32,
    pub nodes: u64,
}

pub struct Searcher<G: Game> {
    nodes: u64,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self {
            nodes: 0,
            _phantom: PhantomData,
        }
    }
}

impl<G: Game> Searcher<G> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn nodes(&self) -> u64 {
        self.nodes
    }

    pub fn search(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.nodes = 0;
        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }

        let mut best_action = moves[0];
        let mut best_score = i32::MIN + 1;
        for action in moves {
            wb.do_move(action);
            let score = -self.alpha_beta(wb, depth - 1, i32::MIN + 1, i32::MAX - 1);
            wb.undo_move();
            if score > best_score {
                best_score = score;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: best_score,
            nodes: self.nodes,
        }
    }

    #[inline]
    pub fn alpha_beta(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        mut alpha: i32,
        beta: i32,
    ) -> i32 {
        self.nodes += 1;
        if depth <= 0 || wb.is_terminal() {
            return G::Evaluator::score(wb);
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        if moves.is_empty() {
            return G::Evaluator::score(wb);
        }

        for action in moves {
            wb.do_move(action);
            let score = -self.alpha_beta(wb, depth - 1, -beta, -alpha);
            wb.undo_move();
            if score >= beta {
                return beta;
            }
            if score > alpha {
                alpha = score;
            }
        }
        alpha
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::GameRules;
    use tgf_mill::{MillActionKind, MillGame, MillRules};

    #[test]
    fn mill_searcher_finds_a_legal_opening_action() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();

        let result = searcher.search(&mut wb, 1);
        assert!(!result.best_action.is_none());
        assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
        assert!(result.nodes > 0);
    }
}
