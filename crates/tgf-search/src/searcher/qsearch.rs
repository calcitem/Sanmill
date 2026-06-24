// SPDX-License-Identifier: GPL-3.0-or-later
// Quiescence search and the small TT probe / save helpers it shares
// with `alpha_beta`.  Hosted in a sibling impl block so the main
// `searcher/mod.rs` stays under 1k lines.

use tgf_core::{Action, Evaluator, Game, SearchActionList, Workbench};

use super::Searcher;
use crate::tt::{Bound, TT_MOVE_NONE, TtEntry};

pub(super) enum TtProbe {
    Miss,
    HitNoCutoff,
    Cutoff(i32),
}

pub(super) struct TtProbeResult {
    pub probe: TtProbe,
    pub tt_move: Option<Action>,
}

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
        let mut stand_pat = G::Evaluator::score(wb);
        if stand_pat > 0 {
            stand_pat = stand_pat.saturating_add(depth);
        } else {
            stand_pat = stand_pat.saturating_sub(depth);
        }
        // Master qsearch returns stand-pat at the depth limit before checking
        // gameOver / repetition.  This matters at shallow Skill=1 leaves:
        // a move that completes threefold at the qsearch horizon should be
        // evaluated like master's non-terminal `do_move` child, while the
        // actual rule verdict remains enforced by `apply` in real play.
        if -depth >= self.qsearch_max_depth {
            return stand_pat;
        }
        if stand_pat >= beta {
            return beta;
        }
        if stand_pat > alpha {
            alpha = stand_pat;
        }
        if wb.is_terminal() {
            // Master src/search.cpp:81-83 returns `stand_pat` in this
            // branch (`if (unlikely(pos->phase == Phase::gameOver))
            // return stand_pat;`).  The previous Rust implementation
            // returned `alpha`, which clamps below the depth-adjusted
            // stand-pat when stand_pat had not yet been folded into
            // alpha.  Returning stand_pat keeps the depth-adjusted
            // mate-distance bias visible to the caller.
            return stand_pat;
        }

        let Some(quiescence_kind_tag) = self.policy.quiescence_kind_tag else {
            return alpha;
        };

        let mut moves = SearchActionList::new();
        G::generate_quiescence_ctx(
            wb,
            &mut moves,
            &self.options.move_order_context,
            quiescence_kind_tag,
        );
        if moves.is_empty() {
            return alpha;
        }
        let key = wb.key();
        self.order_moves(wb, key, depth, &mut moves);

        self.prefetch_child_keys(wb, &moves);

        for action in moves.iter().copied() {
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

    /// Probe the TT and narrow the search window in place.
    ///
    /// Mirrors master `Search::search` (src/search.cpp): on a `BOUND_LOWER`
    /// hit it raises `alpha`, on a `BOUND_UPPER` hit it lowers `beta`, and
    /// returns the stored value as a cutoff when `alpha >= beta`. A
    /// depth-sufficient non-cutoff Lower/Upper entry is still a TT hit in
    /// master's diagnostics, so callers must count `HitNoCutoff` as a hit and
    /// then continue searching with the narrowed window. Crucially BOTH
    /// `alpha` and `beta` are taken by `&mut` so that, when there is no
    /// immediate cutoff, the narrowed window propagates back to the caller and
    /// is used for the remaining move loop and the final bound classification.
    /// Dropping the `beta` narrowing (the previous behaviour) left zero-window
    /// MTD(f) searching a wider window than master.
    #[inline]
    pub(super) fn probe_tt(
        &self,
        key: u64,
        depth: i32,
        alpha: &mut i32,
        beta: &mut i32,
    ) -> TtProbeResult {
        let entry = self.tt.probe_entry_at_age(key, depth, self.tt_age);
        let tt_move = entry.tt_move.and_then(G::unpack_tt_action);
        let Some((value, bound)) = entry.value_bound else {
            return TtProbeResult {
                probe: TtProbe::Miss,
                tt_move,
            };
        };
        let probe = match bound {
            Bound::Exact => TtProbe::Cutoff(value),
            Bound::Lower => {
                *alpha = (*alpha).max(value);
                if *alpha >= *beta {
                    TtProbe::Cutoff(value)
                } else {
                    TtProbe::HitNoCutoff
                }
            }
            Bound::Upper => {
                *beta = (*beta).min(value);
                if *alpha >= *beta {
                    TtProbe::Cutoff(value)
                } else {
                    TtProbe::HitNoCutoff
                }
            }
        };
        TtProbeResult { probe, tt_move }
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
        let tt_move = if self.tt.tt_move_enabled() {
            G::pack_tt_action(best_action).unwrap_or(TT_MOVE_NONE)
        } else {
            TT_MOVE_NONE
        };
        self.tt.save_at_age(
            key,
            TtEntry {
                value,
                depth,
                bound,
                tt_move,
            },
            self.tt_age,
        );
    }

    #[inline]
    pub(super) fn prefetch_child_keys(&self, wb: &mut G::Workbench, moves: &SearchActionList) {
        if !self.options.enable_prefetch {
            return;
        }

        // SAFETY INVARIANT: `key_after` is prefetch-quality, not
        // correctness-quality. `predicted_key` must ONLY feed
        // `tt.prefetch` (a cache hint that never touches a TT slot);
        // probe/save use the real `wb.key()`, so a mispredicted key
        // costs at most a wasted prefetch.
        if self.options.prefetch_all {
            for action in moves.iter().copied() {
                let predicted_key = wb.key_after(action);
                self.tt.prefetch(predicted_key);
            }
        } else if let Some(&first_action) = moves.first() {
            let predicted_key = wb.key_after(first_action);
            self.tt.prefetch(predicted_key);
        }
    }
}
