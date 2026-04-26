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

    /// Simple iterative deepening scaffold.  It re-searches from depth 1 to
    /// `max_depth` and returns the deepest result.
    ///
    /// Later Phase 5 work will add time control, aspiration windows, TT reuse,
    /// and principal-variation tracking.  The important architectural point is
    /// that every iteration still stays generic over `G: Game` and does not
    /// cross a trait-object boundary.
    pub fn iterative_deepening(
        &mut self,
        wb: &mut G::Workbench,
        max_depth: i32,
    ) -> SearchResult {
        let max_depth = max_depth.max(1);
        let mut result = self.search(wb, 1);
        for depth in 2..=max_depth {
            result = self.search(wb, depth);
        }
        result
    }

    /// Minimal MTD(f) scaffold implemented over alpha-beta zero-window calls.
    ///
    /// This intentionally omits TT integration for now; without a TT, MTD(f)
    /// is not efficient.  The function exists so Phase 5 can grow the exact
    /// algorithmic surface area while keeping current behavior testable.
    pub fn mtdf(
        &mut self,
        wb: &mut G::Workbench,
        first_guess: i32,
        depth: i32,
    ) -> i32 {
        let mut g = first_guess;
        let mut upper_bound = i32::MAX - 1;
        let mut lower_bound = i32::MIN + 1;

        while lower_bound < upper_bound {
            let beta = if g == lower_bound { g + 1 } else { g };
            g = self.alpha_beta(wb, depth, beta - 1, beta);
            if g < beta {
                upper_bound = g;
            } else {
                lower_bound = g;
            }
        }
        g
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

    #[test]
    fn mill_iterative_deepening_returns_deepest_result() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();

        let result = searcher.iterative_deepening(&mut wb, 2);
        assert!(!result.best_action.is_none());
        assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
        assert!(result.nodes > 0);
    }

    #[test]
    fn mill_mtdf_returns_a_finite_score() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();

        let score = searcher.mtdf(&mut wb, 0, 1);
        assert!(score > i32::MIN + 1);
        assert!(score < i32::MAX - 1);
    }
}
