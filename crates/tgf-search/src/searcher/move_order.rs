// SPDX-License-Identifier: GPL-3.0-or-later
// Move-ordering / TT-best-action shuffling helpers.
// These are pure `Searcher<G>` methods; they live in a sibling impl
// block so the main `searcher/mod.rs` does not have to host them too.

use tgf_core::{Action, Game, SEARCH_ACTION_CAPACITY, SearchActionList};

use super::Searcher;
use std::mem::MaybeUninit;

impl<G: Game> Searcher<G> {
    #[inline]
    pub(super) fn order_moves(
        &self,
        wb: &G::Workbench,
        key: u64,
        depth: i32,
        moves: &mut SearchActionList,
    ) {
        let moves = moves.as_mut_slice();
        if moves.len() < 2 {
            return;
        }
        let mut scores: [MaybeUninit<i32>; SEARCH_ACTION_CAPACITY] =
            [MaybeUninit::uninit(); SEARCH_ACTION_CAPACITY];
        assert!(moves.len() <= scores.len());
        let mut previous_score = 0_i32;
        let mut has_previous = false;
        let mut needs_sort = false;
        for (i, action) in moves.iter().copied().enumerate() {
            let score = self.move_score(wb, key, depth, action);
            scores[i].write(score);
            if has_previous && previous_score < score {
                needs_sort = true;
            }
            previous_score = score;
            has_previous = true;
        }
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

    #[inline]
    pub(super) fn move_score(
        &self,
        wb: &G::Workbench,
        _key: u64,
        _depth: i32,
        action: Action,
    ) -> i32 {
        // Master MovePicker::score (src/movepick.cpp:46-52) only adds
        // RATING_TT (=100) when ttMove is non-NONE, but TT_MOVE_ENABLE
        // is undefined in the default master config so ttMove always
        // stays MOVE_NONE and the bonus never fires.  The Rust port
        // mirrors that no-op by intentionally NOT consulting the TT for
        // a best-action bonus here.  TT lookups remain available
        // through `Searcher::search_mtdf_with_guess` for root move
        // recovery.
        G::move_order_bias_ctx(wb, action, &self.options.move_order_context)
    }

    #[allow(dead_code)]
    fn order_moves_by_tt(&self, key: u64, moves: &mut SearchActionList) {
        if key == 0 {
            return;
        }
        let Some(entry) = self.tt.get(key) else {
            return;
        };
        if let Some(index) = moves.iter().position(|m| *m == entry.best_action) {
            moves.as_mut_slice().swap(0, index);
        }
    }
}
