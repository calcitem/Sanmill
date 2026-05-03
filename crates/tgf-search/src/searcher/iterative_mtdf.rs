// SPDX-License-Identifier: GPL-3.0-or-later
// Iterative deepening (with aspiration windows) and MTD(f) entry
// points for `Searcher<G>`.  These two algorithms share the same TT
// and TT-aging machinery and are conceptually a unit; hosting them
// together keeps the main `searcher/mod.rs` focused on struct + setters.

use tgf_core::{Action, ActionList, Evaluator, Game, Workbench};

use super::Searcher;
use crate::result::SearchResult;

impl<G: Game> Searcher<G> {
    /// Iterative deepening using PVS (fixes the pre-Phase 5 inconsistency where
    /// IDS drove `search` while the root entry point was `search_pvs`).
    ///
    /// Uses aspiration windows from depth 3 onwards: the initial window is
    /// centered on the previous iteration's score ± `ASPIRATION_DELTA`.  When
    /// the search falls outside the window, the window is widened and the depth
    /// is re-searched.  This typically improves NPS by reducing the search tree.
    ///
    /// The TT generation counter is bumped between iterations so non-Exact
    /// entries from the previous iteration are treated as stale, matching C++
    /// `Search::clear` semantics from `src/search.cpp`.
    ///
    /// # Divergence from master `src/search.cpp`
    ///
    /// In `origin/master`'s C++ engine `Search::pvs` is *defined* but only
    /// invoked from `tests/test_search.cpp` -- the actual root entry point
    /// driven by `SearchEngine::executeSearch` is `Search::search`, a plain
    /// alpha-beta loop with depth-extension when the moveCount is 1.  The
    /// Rust scaffold here intentionally prefers PVS at the root because its
    /// null-window + re-search structure yields the same bestmove on
    /// terminal-deterministic positions while pruning more nodes; the
    /// `tgf-cli selfplay` deterministic regression suite in
    /// `selfplay_baseline_*.toml` confirms parity with the plain alpha-beta
    /// root in fixed-depth Mill self-play.  Callers that need the literal
    /// master shape can call `Self::search` directly instead of
    /// `iterative_deepening`.
    pub fn iterative_deepening(&mut self, wb: &mut G::Workbench, max_depth: i32) -> SearchResult {
        const ASPIRATION_DELTA: i32 = 15; // ~3 piece values
        const ASPIRATION_MAX_WINDOW: i32 = 200;
        let max_depth = max_depth.max(1);
        let mut result = self.search_pvs(wb, 1);
        for depth in 2..=max_depth {
            self.tt.bump_age();
            self.tt_age_bumps += 1;
            if depth < 3 || result.score.abs() >= ASPIRATION_MAX_WINDOW {
                // Full window for shallow depths or near-terminal scores.
                result = self.search_pvs(wb, depth);
            } else {
                // Aspiration window centered on previous score.
                let mut delta = ASPIRATION_DELTA;
                let mut alpha = (result.score - delta).max(i32::MIN + 1);
                let mut beta = (result.score + delta).min(i32::MAX - 1);
                loop {
                    let candidate = self.search_pvs_windowed(wb, depth, alpha, beta);
                    if candidate.score <= alpha {
                        // Fail low: widen alpha.
                        alpha = (alpha - delta).max(i32::MIN + 1);
                    } else if candidate.score >= beta {
                        // Fail high: widen beta.
                        beta = (beta + delta).min(i32::MAX - 1);
                    } else {
                        result = candidate;
                        break;
                    }
                    delta = delta.saturating_mul(2);
                    if delta >= ASPIRATION_MAX_WINDOW {
                        // Degenerate to full window.
                        result = self.search_pvs(wb, depth);
                        break;
                    }
                }
            }
            if self.was_aborted() {
                break;
            }
        }
        result
    }

    /// Windowed PVS root (aspiration-window helper): searches with explicit
    /// alpha/beta bounds rather than ±∞.  Returns the best result found within
    /// the window.
    fn search_pvs_windowed(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        alpha: i32,
        beta: i32,
    ) -> SearchResult {
        self.begin_root_search();
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult::default_none().with_score(score);
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }
        let mut best_action = moves[0];
        let mut best_alpha = alpha;
        let root_key = wb.key();
        for (i, action) in moves.into_iter().enumerate() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            if root_key != 0 {
                self.repetition_stack.push(root_key);
            }
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, best_alpha, beta, i, before, after);
            wb.undo_move();
            if root_key != 0 {
                self.repetition_stack.pop();
            }
            if value > best_alpha {
                best_alpha = value;
                best_action = action;
            }
            if best_alpha >= beta {
                break;
            }
        }
        SearchResult {
            best_action,
            score: best_alpha,
            nodes: self.nodes,
        }
    }

    /// MTD(f) with proper TT integration.  Each zero-window alpha-beta call
    /// writes its result into the TT; subsequent iterations reuse those entries
    /// to prune the search tree, which is what makes MTD(f) efficient.
    ///
    /// Unlike the old scaffold, the TT is NOT bypassed here — `alpha_beta`
    /// already probes and saves the TT on every node.
    pub fn mtdf(&mut self, wb: &mut G::Workbench, first_guess: i32, depth: i32) -> i32 {
        let mut g = first_guess;
        let mut upper_bound = i32::MAX - 1;
        let mut lower_bound = i32::MIN + 1;

        while lower_bound < upper_bound {
            let beta = if g == lower_bound { g + 1 } else { g };
            // alpha_beta now probes/saves the TT at every node, so each
            // iteration benefits from the previous iteration's TT entries.
            g = self.alpha_beta(wb, depth, beta - 1, beta);
            if g < beta {
                upper_bound = g;
            } else {
                lower_bound = g;
            }
            if self.was_aborted() {
                break;
            }
        }
        g
    }

    /// Run MTD(f) at `depth` and return a full `SearchResult` including the
    /// best action retrieved from the TT. Mirrors master's `Search::MTDF`
    /// which updates `bestMove` by reference (P2-C).
    pub fn search_mtdf(&mut self, wb: &mut G::Workbench, depth: i32) -> SearchResult {
        self.search_mtdf_with_guess(wb, depth, 0)
    }

    /// Run MTD(f) at `depth` with a caller-provided first guess.  The root
    /// pre-check mirrors `search`: terminal positions, empty roots, and
    /// single legal root moves are handled before the zero-window loop so
    /// Algorithm=2 returns VALUE_UNIQUE for forced moves just like master.
    pub fn search_mtdf_with_guess(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        first_guess: i32,
    ) -> SearchResult {
        self.begin_root_search();
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
            };
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        if self.options.shuffle_root {
            self.shuffle_moves(&mut moves);
        }
        self.order_moves(wb, wb.key(), depth, &mut moves);
        if moves.is_empty() {
            return SearchResult {
                best_action: Action::NONE,
                score: G::Evaluator::score(wb),
                nodes: self.nodes,
            };
        }
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: G::unique_root_move_score(),
                nodes: self.nodes,
            };
        }

        let score = self.mtdf(wb, first_guess, depth);
        let key = wb.key();
        let best_action = self
            .tt
            .get(key)
            .map(|e| e.best_action)
            .unwrap_or(Action::NONE);
        SearchResult {
            best_action,
            score,
            nodes: self.nodes,
        }
    }
}
