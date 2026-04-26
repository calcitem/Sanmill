// SPDX-License-Identifier: GPL-3.0-or-later
// Generic monomorphised game-tree searcher.
//
// The hot path is generic over `G: Game`; it never stores `dyn GameRules` or
// `dyn Workbench`.  This mirrors the C++ CRTP design in the migration plan and
// keeps do/undo/evaluate calls statically dispatchable.

use std::{
    collections::HashMap,
    marker::PhantomData,
    time::{Duration, Instant},
};

use tgf_core::{Action, ActionList, Evaluator, Game, Workbench};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchResult {
    pub best_action: Action,
    pub score: i32,
    pub nodes: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Bound {
    Exact,
    Lower,
    Upper,
}

#[derive(Clone, Copy, Debug)]
struct TtEntry {
    value: i32,
    depth: i32,
    bound: Bound,
    best_action: Action,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchPolicy {
    pub remove_kind_tag: Option<i16>,
}

impl Default for SearchPolicy {
    fn default() -> Self {
        Self {
            remove_kind_tag: None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchOptions {
    pub depth_extension: bool,
    pub node_limit: Option<u64>,
    pub time_limit_ms: Option<u64>,
}

impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            depth_extension: false,
            node_limit: None,
            time_limit_ms: None,
        }
    }
}

pub struct Searcher<G: Game> {
    nodes: u64,
    rng_state: u64,
    tt: HashMap<u64, TtEntry>,
    killers: HashMap<i32, Action>,
    history: HashMap<Action, i32>,
    policy: SearchPolicy,
    options: SearchOptions,
    search_started_at: Option<Instant>,
    aborted: bool,
    _phantom: PhantomData<G>,
}

impl<G: Game> Default for Searcher<G> {
    fn default() -> Self {
        Self {
            nodes: 0,
            rng_state: 0x9E37_79B9_7F4A_7C15,
            tt: HashMap::new(),
            killers: HashMap::new(),
            history: HashMap::new(),
            policy: SearchPolicy::default(),
            options: SearchOptions::default(),
            search_started_at: None,
            aborted: false,
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

    pub fn clear_tt(&mut self) {
        self.tt.clear();
        self.killers.clear();
        self.history.clear();
    }

    pub fn tt_len(&self) -> usize {
        self.tt.len()
    }

    pub fn set_random_seed(&mut self, seed: u64) {
        self.rng_state = if seed == 0 {
            0x9E37_79B9_7F4A_7C15
        } else {
            seed
        };
    }

    pub fn set_policy(&mut self, policy: SearchPolicy) {
        self.policy = policy;
    }

    pub fn set_options(&mut self, options: SearchOptions) {
        self.options = options;
    }

    pub fn was_aborted(&self) -> bool {
        self.aborted
    }

    pub fn search(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.begin_root_search();
        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        self.order_moves(wb.key(), depth, &mut moves);
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
            if self.should_abort() {
                break;
            }
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
        self.begin_root_search();
        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        self.order_moves(wb.key(), depth, &mut moves);
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
            if self.should_abort() {
                break;
            }
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
        if self.should_abort() {
            return G::Evaluator::score(wb);
        }
        if depth <= 0 || wb.is_terminal() {
            return self.qsearch(wb, alpha, beta);
        }

        let old_alpha = alpha;
        let key = wb.key();
        if let Some(value) = self.probe_tt(key, depth, &mut alpha, beta) {
            return value;
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        self.order_moves(key, depth, &mut moves);
        if moves.is_empty() {
            return G::Evaluator::score(wb);
        }

        let mut best_value = i32::MIN + 1;
        let mut best_action = Action::NONE;
        let depth_extension = if self.options.depth_extension && moves.len() == 1 {
            1
        } else {
            0
        };
        for action in moves {
            if self.should_abort() {
                return best_value.max(alpha);
            }
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let score =
                self.search_after_move(wb, depth - 1 + depth_extension, alpha, beta, before, after);
            wb.undo_move();
            if score > best_value {
                best_value = score;
                best_action = action;
            }
            if score >= beta {
                self.record_cutoff(depth, action);
                self.save_tt(key, depth, beta, Bound::Lower, action);
                return beta;
            }
            if score > alpha {
                alpha = score;
            }
        }
        let bound = if best_value <= old_alpha {
            Bound::Upper
        } else {
            Bound::Exact
        };
        self.save_tt(key, depth, alpha, bound, best_action);
        alpha
    }

    #[inline]
    fn should_abort(&mut self) -> bool {
        if let Some(limit) = self.options.node_limit {
            if self.nodes >= limit {
                self.aborted = true;
            }
        }
        if let (Some(start), Some(limit_ms)) =
            (self.search_started_at, self.options.time_limit_ms)
        {
            if start.elapsed() >= Duration::from_millis(limit_ms) {
                self.aborted = true;
            }
        }
        self.aborted
    }

    #[inline]
    fn begin_root_search(&mut self) {
        self.nodes = 0;
        self.aborted = false;
        self.search_started_at = Some(Instant::now());
    }

    /// Quiescence search scaffold matching the C++ shape: evaluate the current
    /// position, then extend only remove/capture actions when the game policy
    /// tells us which action kind represents a removal.
    pub fn qsearch(&mut self, wb: &mut G::Workbench, mut alpha: i32, beta: i32) -> i32 {
        self.nodes += 1;
        if self.should_abort() {
            return G::Evaluator::score(wb);
        }
        let stand_pat = G::Evaluator::score(wb);
        if stand_pat >= beta {
            return beta;
        }
        if stand_pat > alpha {
            alpha = stand_pat;
        }
        if wb.is_terminal() {
            return alpha;
        }

        let Some(remove_kind_tag) = self.policy.remove_kind_tag else {
            return alpha;
        };

        let mut moves = ActionList::<256>::new();
        G::generate_legal(wb, &mut moves);
        for action in moves.into_iter().filter(|a| a.kind_tag == remove_kind_tag) {
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = if after != before {
                -self.qsearch(wb, -beta, -alpha)
            } else {
                self.qsearch(wb, alpha, beta)
            };
            wb.undo_move();
            if value > alpha {
                alpha = value;
                if alpha >= beta {
                    return beta;
                }
            }
        }
        alpha
    }

    #[inline]
    fn probe_tt(&self, key: u64, depth: i32, alpha: &mut i32, mut beta: i32) -> Option<i32> {
        if key == 0 {
            return None;
        }
        let entry = self.tt.get(&key)?;
        if entry.depth < depth {
            return None;
        }
        match entry.bound {
            Bound::Exact => Some(entry.value),
            Bound::Lower => {
                *alpha = (*alpha).max(entry.value);
                (*alpha >= beta).then_some(entry.value)
            }
            Bound::Upper => {
                beta = beta.min(entry.value);
                (*alpha >= beta).then_some(entry.value)
            }
        }
    }

    #[inline]
    fn save_tt(&mut self, key: u64, depth: i32, value: i32, bound: Bound, best_action: Action) {
        if key == 0 {
            return;
        }
        if let Some(old) = self.tt.get(&key) {
            if old.depth > depth {
                return;
            }
        }
        self.tt.insert(
            key,
            TtEntry {
                value,
                depth,
                bound,
                best_action,
            },
        );
    }

    #[inline]
    fn order_moves(&self, key: u64, depth: i32, moves: &mut ActionList<256>) {
        moves.as_mut_slice().sort_by_key(|m| -self.move_score(key, depth, *m));
    }

    #[inline]
    fn move_score(&self, key: u64, depth: i32, action: Action) -> i32 {
        let mut score = 0;
        if key != 0
            && self
                .tt
                .get(&key)
                .is_some_and(|entry| entry.best_action == action)
        {
            score += 1_000_000;
        }
        if self
            .killers
            .get(&depth)
            .is_some_and(|killer| *killer == action)
        {
            score += 100_000;
        }
        score + self.history.get(&action).copied().unwrap_or_default()
    }

    #[inline]
    fn record_cutoff(&mut self, depth: i32, action: Action) {
        self.killers.insert(depth, action);
        *self.history.entry(action).or_insert(0) += depth.max(1) * depth.max(1);
    }

    #[allow(dead_code)]
    fn order_moves_by_tt(&self, key: u64, moves: &mut ActionList<256>) {
        if key == 0 {
            return;
        }
        let Some(entry) = self.tt.get(&key) else {
            return;
        };
        if let Some(index) = moves.iter().position(|m| *m == entry.best_action) {
            moves.as_mut_slice().swap(0, index);
        }
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

    #[derive(Clone, Copy, Debug)]
    struct KeyedWorkbench {
        ply: u8,
        side: i8,
    }

    impl Workbench for KeyedWorkbench {
        fn snapshot(&self) -> GameStateSnapshot {
            GameStateSnapshot::default()
        }

        fn key(&self) -> u64 {
            // Same root key every time; child key depends on ply.  This is
            // enough to prove TT probe/save without tying the test to Mill's
            // future Zobrist implementation.
            100 + u64::from(self.ply)
        }

        fn side_to_move(&self) -> i8 {
            self.side
        }

        fn is_terminal(&self) -> bool {
            self.ply >= 2
        }

        fn do_move(&mut self, _a: Action) {
            self.ply += 1;
            self.side ^= 1;
        }

        fn undo_move(&mut self) {
            self.ply -= 1;
            self.side ^= 1;
        }
    }

    struct KeyedEvaluator;

    impl Evaluator<KeyedWorkbench> for KeyedEvaluator {
        fn score(wb: &KeyedWorkbench) -> i32 {
            i32::from(wb.ply) * 10
        }
    }

    struct KeyedGame;

    impl tgf_core::Game for KeyedGame {
        type Workbench = KeyedWorkbench;
        type Evaluator = KeyedEvaluator;

        fn build_workbench(&self, _snap: &GameStateSnapshot) -> Self::Workbench {
            KeyedWorkbench { ply: 0, side: 0 }
        }

        fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
            if wb.ply < 2 {
                out.push(Action {
                    kind_tag: 0,
                    from_node: -1,
                    to_node: 0,
                    aux: -1,
                    payload_bits: 0,
                });
                out.push(Action {
                    kind_tag: 0,
                    from_node: -1,
                    to_node: 1,
                    aux: -1,
                    payload_bits: 0,
                });
            }
        }
    }

    #[test]
    fn transposition_table_saves_and_reuses_entries() {
        let game = KeyedGame;
        let mut wb = game.build_workbench(&GameStateSnapshot::default());
        let mut searcher = Searcher::<KeyedGame>::new();

        let first = searcher.search(&mut wb, 2);
        assert!(searcher.tt_len() > 0);
        assert!(first.nodes > 0);

        let before = searcher.nodes();
        let second = searcher.search(&mut wb, 2);
        assert_eq!(first.best_action, second.best_action);
        assert!(searcher.nodes() <= before.max(1));
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

    #[test]
    fn mill_qsearch_accepts_remove_policy() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_policy(SearchPolicy {
            remove_kind_tag: Some(MillActionKind::Remove as i16),
        });

        let score = searcher.qsearch(&mut wb, i32::MIN + 1, i32::MAX - 1);
        assert!(score > i32::MIN + 1);
        assert!(score < i32::MAX - 1);
    }

    #[test]
    fn node_limit_marks_search_as_aborted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: false,
            node_limit: Some(1),
            time_limit_ms: None,
        });

        let _ = searcher.search(&mut wb, 3);
        assert!(searcher.was_aborted());
    }

    #[test]
    fn depth_extension_option_is_accepted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: true,
            node_limit: None,
            time_limit_ms: None,
        });

        let result = searcher.search(&mut wb, 1);
        assert!(!result.best_action.is_none());
    }

    #[test]
    fn wall_clock_time_limit_marks_search_as_aborted() {
        let rules = MillRules::default();
        let game = MillGame::default();
        let snap = rules.initial_state(&[]);
        let mut wb = game.build_workbench(&snap);
        let mut searcher = Searcher::<MillGame>::new();
        searcher.set_options(SearchOptions {
            depth_extension: false,
            node_limit: None,
            time_limit_ms: Some(0),
        });

        let _ = searcher.search(&mut wb, 3);
        assert!(searcher.was_aborted());
    }
}
