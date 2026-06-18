// SPDX-License-Identifier: GPL-3.0-or-later
// Iterative deepening (with aspiration windows) and MTD(f) entry
// points for `Searcher<G>`.  These two algorithms share the same TT
// and TT-aging machinery and are conceptually a unit; hosting them
// together keeps the main `searcher/mod.rs` focused on struct + setters.

use tgf_core::{Action, ActionList, Evaluator, Game, Workbench};

use super::Searcher;
use crate::result::SearchResult;
use crate::tt::Bound;

impl<G: Game> Searcher<G> {
    /// Iterative deepening using PVS (fixes the earlier inconsistency where
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
    /// Rust implementation here intentionally prefers PVS at the root because
    /// its null-window + re-search structure yields the same bestmove on
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
        // Pre-search short-circuit (mirrors master executeSearch
        // return-50/10/3 path before IDS): when the game is already a
        // rule draw, do not waste search time.
        if let Some(short_circuit_reason) = G::root_short_circuit_draw(wb) {
            return SearchResult::draw_short_circuit(short_circuit_reason);
        }
        let mut result = self.search_pvs(wb, 1);
        let aspiration_enabled = self.options.enable_aspiration_window;
        for depth in 2..=max_depth {
            self.tt.bump_age();
            self.tt_age_bumps += 1;
            if !aspiration_enabled || depth < 3 || result.score.abs() >= ASPIRATION_MAX_WINDOW {
                // Master shape: full window for every IDS iteration.
                result = self.search_pvs(wb, depth);
            } else {
                // Optional aspiration window centered on previous score.
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
        self.begin_root_search_at(wb);
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
                draw_reason: None,
            };
        }
        let mut best_action = moves[0];
        let mut best_alpha = alpha;
        let root_key = wb.key();
        for (i, action) in moves.iter().copied().enumerate() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(root_key, action);
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.pvs_after_move(wb, depth - 1, best_alpha, beta, i, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(root_key, previous_incoming_reset);
            // Keep the FIRST move on ties (strict `value > best_alpha`),
            // matching master's strict root update.
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
            draw_reason: None,
        }
    }

    /// MTD(f) with proper TT integration.  Each zero-window alpha-beta call
    /// writes its result into the TT; subsequent iterations reuse those entries
    /// to prune the search tree, which is what makes MTD(f) efficient.
    ///
    /// Unlike the earlier implementation, the TT is NOT bypassed here —
    /// `alpha_beta`
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
        self.search_mtdf_with_guess_traced(wb, depth, first_guess, &mut |_, _, _, _, _| {})
    }

    /// Run MTD(f) and report each zero-window probe through `on_iteration`.
    /// This is intentionally the same implementation used by
    /// [`Self::search_mtdf_with_guess`], so CLI diagnostics cannot diverge
    /// from production search behavior.
    pub fn search_mtdf_with_guess_traced<F>(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        first_guess: i32,
        on_iteration: &mut F,
    ) -> SearchResult
    where
        F: FnMut(usize, i32, i32, Action, u64),
    {
        self.begin_root_search_at(wb);
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return SearchResult {
                best_action: Action::NONE,
                score,
                nodes: self.nodes,
                draw_reason: None,
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
                draw_reason: None,
            };
        }
        if moves.len() == 1 {
            return SearchResult {
                best_action: moves[0],
                score: G::unique_root_move_score(),
                nodes: self.nodes,
                draw_reason: None,
            };
        }

        // Persistent best root move threaded through every MTD(f) probe,
        // mirroring master `Search::MTDF`'s `Move &bestMove` reference
        // (src/search.cpp).  A converging fail-low (all-node) probe never
        // raises alpha and therefore must NOT change the move chosen by the
        // fail-high probe that established the score.  Recovering the move
        // from the TT after the loop is unreliable: the final all-node probe
        // stores the first-ordered move with an Upper bound, clobbering the
        // genuinely best move and making MTD(f) ignore the evaluator.
        let mut best_action = moves[0];
        let mut g = first_guess;
        let mut lower_bound = i32::MIN + 1;
        let mut upper_bound = i32::MAX - 1;
        let mut iteration = 0;
        while lower_bound < upper_bound {
            let beta = if g == lower_bound { g + 1 } else { g };
            g = self.mtdf_root(wb, depth, beta - 1, beta, &mut best_action);
            on_iteration(iteration, beta, g, best_action, self.nodes);
            iteration += 1;
            if g < beta {
                upper_bound = g;
            } else {
                lower_bound = g;
            }
            if self.was_aborted() {
                break;
            }
        }
        SearchResult {
            best_action,
            score: g,
            nodes: self.nodes,
            draw_reason: None,
        }
    }

    /// Root driver for one MTD(f) zero-window probe.
    ///
    /// Mirrors the root of master `Search::search` (src/search.cpp): it
    /// iterates the ordered root moves, recurses through the shared
    /// [`Self::alpha_beta`] for children (so every child still probes and
    /// saves the TT), and updates `best_action` ONLY when a move raises
    /// alpha (`value > alpha`).  The caller threads the same `best_action`
    /// through every probe of the bound loop, exactly like master's
    /// `Move &bestMove` reference, so a converging all-node probe cannot
    /// overwrite the move chosen by the fail-high probe that pinned down
    /// the score.
    fn mtdf_root(
        &mut self,
        wb: &mut G::Workbench,
        depth: i32,
        mut alpha: i32,
        mut beta: i32,
        best_action: &mut Action,
    ) -> i32 {
        // Master `Search::search` counts the root zero-window probe itself
        // before terminal checks, TT probing, or child generation.  MTD(f)
        // calls this root probe once per bound iteration, so the node counter
        // must include those entries for exact legacy parity.
        self.nodes += 1;
        let root_key = wb.key();
        let old_alpha = alpha;
        // Master `Search::search` probes the TT at EVERY node, including the
        // root (depth == originDepth).  On a TT cutoff it returns the probed
        // value WITHOUT updating `bestMove`, so the threaded `best_action` is
        // preserved across MTD(f) iterations.  Reusing the root entry the same
        // way mirrors master's deterministic deep MTD(f) behaviour.
        if let Some(value) = self.probe_tt(root_key, depth, &mut alpha, &mut beta) {
            self.tt_hits += 1;
            return value;
        }
        if root_key != 0 {
            self.tt_misses += 1;
        }
        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        self.order_moves(wb, root_key, depth, &mut moves);
        let mut best_value = i32::MIN + 1;
        let mut best_local = Action::NONE;
        for action in moves.iter().copied() {
            if self.should_abort() {
                break;
            }
            let before = wb.side_to_move();
            let previous_incoming_reset = self.push_repetition_ancestor(root_key, action);
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = self.search_after_move(wb, depth - 1, alpha, beta, before, after);
            wb.undo_move();
            self.pop_repetition_ancestor(root_key, previous_incoming_reset);
            // Mirror master `Search::search`'s root update exactly: the best
            // move only changes on a strict `value > alpha` improvement, so
            // the FIRST move is kept on ties.
            if value > best_value {
                best_value = value;
                if value > alpha {
                    *best_action = action;
                    best_local = action;
                    if value >= beta {
                        break; // fail high
                    }
                    alpha = value;
                }
            }
        }
        // Master saves bestValue + bound at every node (src/search.cpp:372).
        // TT_MOVE is undefined in master, so the stored move is unused by move
        // ordering and does not affect the search; we keep `best_local` for
        // symmetry with `alpha_beta`.
        let bound = if best_value <= old_alpha {
            Bound::Upper
        } else if best_value >= beta {
            Bound::Lower
        } else {
            Bound::Exact
        };
        self.save_tt(root_key, depth, best_value, bound, best_local);
        best_value
    }
}
