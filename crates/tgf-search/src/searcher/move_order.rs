// SPDX-License-Identifier: GPL-3.0-or-later
// Move-ordering / TT-best-action shuffling helpers.
// These are pure `Searcher<G>` methods; they live in a sibling impl
// block so the main `searcher/mod.rs` does not have to host them too.

use tgf_core::{Game, MoveOrderScore, SEARCH_ACTION_CAPACITY, SearchActionList};

use super::Searcher;
use std::mem::MaybeUninit;

impl<G: Game> Searcher<G> {
    #[inline]
    pub(super) fn order_moves(
        &self,
        wb: &G::Workbench,
        _key: u64,
        _depth: i32,
        moves: &mut SearchActionList,
    ) {
        let moves = moves.as_mut_slice();
        if moves.len() < 2 {
            return;
        }
        let mut scores: [MaybeUninit<MoveOrderScore>; SEARCH_ACTION_CAPACITY] =
            [MaybeUninit::uninit(); SEARCH_ACTION_CAPACITY];
        assert!(moves.len() <= scores.len());
        // Master only adds a TT-move bonus when TT_MOVE_ENABLE is compiled in.
        // The default legacy build leaves it disabled, so this scorer remains
        // a pure static move-order bias path and does not probe the TT.
        let needs_sort =
            G::move_order_scores_ctx(wb, moves, &self.options.move_order_context, &mut scores);
        if !needs_sort {
            return;
        }

        // Stable descending insertion sort.  This preserves the generated
        // move order for equal scores, matching master's partial insertion
        // sort, while computing the expensive Mill move score exactly once
        // per candidate.
        for i in 1..moves.len() {
            let action = moves[i];
            // SAFETY: indices below `moves.len()` were initialized in the
            // scoring loop above, and insertion sort only reads / writes
            // within that initialized prefix.
            let score = unsafe { scores[i].assume_init() };
            let mut j = i;
            while j > 0 && unsafe { scores[j - 1].assume_init() } < score {
                moves[j] = moves[j - 1];
                scores[j].write(unsafe { scores[j - 1].assume_init() });
                j -= 1;
            }
            moves[j] = action;
            scores[j].write(score);
        }
    }

    /// Shuffle the root move list using the internal xorshift RNG (P2-K).
    /// Mirrors master's MoveList<LEGAL>::shuffle() which is called at the
    /// start of executeSearch when Shuffling is enabled.
    pub(super) fn shuffle_moves(&mut self, moves: &mut SearchActionList) {
        let n = moves.len();
        if n < 2 {
            return;
        }
        for i in (1..n).rev() {
            let j = self.next_random_index(i + 1);
            moves.as_mut_slice().swap(i, j);
        }
    }
}
