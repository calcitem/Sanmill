// SPDX-License-Identifier: GPL-3.0-or-later
// Quiescence search and the small TT probe / save helpers it shares
// with `alpha_beta`.  Hosted in a sibling impl block so the main
// `searcher/mod.rs` stays under 1k lines.

use tgf_core::{Action, ActionList, Evaluator, Game, Workbench};

use super::Searcher;
use crate::tt::{Bound, TtEntry};

impl<G: Game> Searcher<G> {
    /// Quiescence search entry point preserved for external callers.  Equivalent
    /// to invoking [`Self::qsearch_with_depth`] at depth 0; alpha-beta callers
    /// should prefer the depth-aware variant so the stand-pat mate-distance
    /// decay matches `src/search.cpp::qsearch`.
    pub fn qsearch(&mut self, wb: &mut G::Workbench, alpha: i32, beta: i32) -> i32 {
        self.qsearch_with_depth(wb, 0, alpha, beta)
    }

    /// Depth-aware quiescence search mirroring `Search::qsearch` in
    /// `src/search.cpp`.  Adjusts the static stand-pat by `depth` (which is
    /// always non-positive at this entry) so deeper extensions prefer faster
    /// wins / slower losses, then extends only the action kind that the game
    /// policy identifies as a removal.  Removal candidates are ordered
    /// through the same MovePicker-style scoring used in the main search.
    pub fn qsearch_with_depth(
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
        if let Some(score) = G::terminal_score(wb, wb.side_to_move(), depth) {
            return score;
        }
        let mut stand_pat = G::Evaluator::score(wb);
        if stand_pat > 0 {
            stand_pat = stand_pat.saturating_add(depth);
        } else {
            stand_pat = stand_pat.saturating_sub(depth);
        }
        if stand_pat >= beta {
            return beta;
        }
        if stand_pat > alpha {
            alpha = stand_pat;
        }
        if wb.is_terminal() {
            return alpha;
        }

        let Some(quiescence_kind_tag) = self.policy.quiescence_kind_tag else {
            return alpha;
        };

        // Enforce the MaxQuiescenceDepth gate: do not recurse deeper than
        // `qsearch_max_depth` plies past the main search horizon (depth == 0).
        // `depth` is <= 0 here; -depth is how many plies we have extended.
        if -depth >= self.qsearch_max_depth {
            return alpha;
        }

        let mut moves = ActionList::<256>::new();
        G::generate_legal_ctx(wb, &mut moves, &self.options.move_order_context);
        moves.retain(|a| a.kind_tag == quiescence_kind_tag);
        if moves.is_empty() {
            return alpha;
        }
        let key = wb.key();
        self.order_moves(wb, key, depth, &mut moves);

        for action in moves {
            if self.should_abort() {
                return alpha;
            }
            let before = wb.side_to_move();
            wb.do_move(action);
            let after = wb.side_to_move();
            let value = if after != before {
                -self.qsearch_with_depth(wb, depth - 1, -beta, -alpha)
            } else {
                self.qsearch_with_depth(wb, depth - 1, alpha, beta)
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
    pub(super) fn probe_tt(
        &self,
        key: u64,
        depth: i32,
        alpha: &mut i32,
        mut beta: i32,
    ) -> Option<i32> {
        if key == 0 {
            return None;
        }
        let entry = self.tt.get(key)?;
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
    pub(super) fn save_tt(
        &mut self,
        key: u64,
        depth: i32,
        value: i32,
        bound: Bound,
        best_action: Action,
    ) {
        self.tt.save(
            key,
            TtEntry {
                value,
                depth,
                bound,
                best_action,
            },
        );
    }
}
