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
    rng_state: u64,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self {
            nodes: 0,
            rng_state: 0x9E37_79B9_7F4A_7C15,
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

    pub fn set_random_seed(&mut self, seed: u64) {
        self.rng_state = if seed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            seed
        };
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
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let score = self.search_after_move(
                wb,
                depth - 1,
                i32::MIN + 1,
                i32::MAX - 1,
                before,
                after,
            );
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

    /// Principal Variation Search root entry.  The first move is searched with
    /// a full window; later moves use a null window and are re-searched on
    /// fail-high inside the original alpha/beta window.  This mirrors the
    /// shape of `Search::pvs` in the mature C++ engine.
    pub fn search_pvs(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
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
        let mut alpha = i32::MIN + 1;
        let beta = i32::MAX - 1;

        for (i, action) in moves.into_iter().enumerate() {
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, alpha, beta, i, before, after);
            wb.undo_move();

            if value > alpha {
                alpha = value;
                best_action = action;
            }
        }

        SearchResult {
            best_action,
            score: alpha,
            nodes: self.nodes,
        }
    }

    /// Deterministic random-search equivalent.  Production callers can seed
    /// this from time; tests pass a fixed seed to keep results reproducible.
    pub fn random_search(&mut self, wb: &mut G::Workbench) -> SearchResult {
        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: 0,
                nodes: 0,
            };
        }
        let index = self.next_random_index(moves.len());
        SearchResult {
            best_action: moves[index],
            score: 0,
            nodes: 0,
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
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let score = self.search_after_move(wb, depth - 1, alpha, beta, before, after);
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

    #[inline]
    fn search_after_move(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
        before: i8,
        after: i8,
    ) -> i32 {
        if after != before {
            -self.alpha_beta(wb, depth, -beta, -alpha)
        } else {
            self.alpha_beta(wb, depth, alpha, beta)
        }
    }

    #[inline]
    fn pvs_after_move(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
        move_index: usize,
        before: i8,
        after: i8,
    ) -> i32 {
        if move_index == 0 {
            return self.search_after_move(wb, depth, alpha, beta, before, after);
        }

        const PVS_WINDOW: i32 = 1;
        let mut value = if after != before {
            -self.alpha_beta(wb, depth, -alpha - PVS_WINDOW, -alpha)
        } else {
            self.alpha_beta(wb, depth, alpha, alpha + PVS_WINDOW)
        };

        if value > alpha && value < beta {
            value = self.search_after_move(wb, depth, alpha, beta, before, after);
        }
        value
    }

    #[inline]
    fn next_random_index(&mut self, len: usize) -> usize {
        debug_assert!(len > 0);
        // xorshift64*: tiny deterministic PRNG, adequate for random-search
        // move selection and reproducible tests.
        let mut x = self.rng_state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng_state = x;
        let value = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
        (value as usize) % len
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tgf_core::{Evaluator, GameRules, GameStateSnapshot, Workbench};
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
    fn mill_pvs_finds_a_legal_opening_action() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();

        let result = searcher.search_pvs(&mut wb, 1);
        assert!(!result.best_action.is_none());
        assert_eq!(result.best_action.kind_tag, MillActionKind::Place as i16);
        assert!(result.nodes > 0);
    }

    #[test]
    fn mill_random_search_is_seeded_and_deterministic() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb1 = game.build_workbench(&snap);
        let mut wb2 = game.build_workbench(&snap);
        let mut a = Searcher::<MillGame>::new();
        let mut b = Searcher::<MillGame>::new();
        a.set_random_seed(1234);
        b.set_random_seed(1234);

        assert_eq!(
            a.random_search(&mut wb1).best_action,
            b.random_search(&mut wb2).best_action
        );
    }

    #[derive(Clone, Copy, Debug)]
    struct SameSideWorkbench {
        moved: bool,
        side: i8,
    }

    impl Workbench for SameSideWorkbench {
        fn snapshot(&self) -> GameStateSnapshot {
            GameStateSnapshot::default()
        }

        fn key(&self) -> u64 {
            0
        }

        fn side_to_move(&self) -> i8 {
            self.side
        }

        fn is_terminal(&self) -> bool {
            false
        }

        fn do_move(&mut self, _a: Action) {
            self.moved = true;
            // Intentionally keep side unchanged to model a mill-removal
            // obligation.  The search must NOT negate this branch.
            self.side = 0;
        }

        fn undo_move(&mut self) {
            self.moved = false;
            self.side = 0;
        }
    }

    struct SameSideEvaluator;

    impl Evaluator<SameSideWorkbench> for SameSideEvaluator {
        fn score(wb: &SameSideWorkbench) -> i32 {
            if wb.moved { 42 } else { 0 }
        }
    }

    struct SameSideGame;

    impl tgf_core::Game for SameSideGame {
        type Workbench = SameSideWorkbench;
        type Evaluator = SameSideEvaluator;

        fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
            SameSideWorkbench { moved: false, side: 0 }
        }

        fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
            if !wb.moved {
                out.push(Action {
                    kind_tag: 0,
                    from_node: -1,
                    to_node: 0,
                    aux: -1,
                    payload_bits: 0,
                });
            }
        }
    }

    #[test]
    fn same_side_move_result_is_not_negated() {
        let game = SameSideGame;
        let mut wb = game.build_workbench(&GameStateSnapshot::default());
        let mut searcher = Searcher::<SameSideGame>::new();

        let result = searcher.search(&mut wb, 1);
        assert_eq!(result.score, 42);
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
