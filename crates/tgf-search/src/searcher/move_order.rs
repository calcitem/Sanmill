// SPDX-License-Identifier: GPL-3.0-or-later
// Move-ordering / TT-best-action shuffling helpers.
// These are pure `Searcher<G>` methods; they live in a sibling impl
// block so the main `searcher/mod.rs` does not have to host them too.

use tgf_core::{Action, Game, MoveOrderScore, SEARCH_ACTION_CAPACITY, SearchActionList};

use super::Searcher;
use std::mem::MaybeUninit;

impl<G: Game> Searcher<G> {
    #[inline]
    pub(super) fn order_moves(
        &self,
        wb: &G::Workbench,
        key: u64,
        _depth: i32,
        moves: &mut SearchActionList,
    ) {
        self.order_moves_impl(wb, key, moves, None, true);
    }

    #[inline]
    pub(super) fn order_moves_with_tt_move(
        &self,
        wb: &G::Workbench,
        key: u64,
        _depth: i32,
        moves: &mut SearchActionList,
        tt_move: Option<Action>,
    ) {
        self.order_moves_impl(wb, key, moves, tt_move, false);
    }

    #[inline]
    fn order_moves_impl(
        &self,
        wb: &G::Workbench,
        key: u64,
        moves: &mut SearchActionList,
        tt_move: Option<Action>,
        probe_tt_move: bool,
    ) {
        let moves = moves.as_mut_slice();
        if moves.len() < 2 {
            return;
        }
        let mut scores: [MaybeUninit<MoveOrderScore>; SEARCH_ACTION_CAPACITY] =
            [MaybeUninit::uninit(); SEARCH_ACTION_CAPACITY];
        assert!(moves.len() <= scores.len());
        let mut needs_sort =
            G::move_order_scores_ctx(wb, moves, &self.options.move_order_context, &mut scores);
        if let Some(index) = self.legal_hash_move_index(key, moves, tt_move, probe_tt_move) {
            if needs_sort {
                // A TT/hash move is a move-order hint only. It must still be
                // legal in the current node, and assigning the maximum score
                // preserves the existing stable ordering among every other
                // candidate.
                scores[index].write(MoveOrderScore::MAX);
            } else if index != 0 {
                moves.swap(0, index);
                return;
            }
            needs_sort = true;
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

    #[inline]
    fn legal_hash_move_index(
        &self,
        key: u64,
        moves: &[Action],
        tt_move: Option<Action>,
        probe_tt_move: bool,
    ) -> Option<usize> {
        if let Some(action) = self.options.move_order_context.hash_move
            && let Some(index) = moves.iter().position(|candidate| *candidate == action)
        {
            return Some(index);
        }
        if let Some(action) = tt_move
            && let Some(index) = moves.iter().position(|candidate| *candidate == action)
        {
            return Some(index);
        }
        if !probe_tt_move {
            return None;
        }
        self.tt
            .probe_tt_move_at_age(key, self.tt_age)
            .and_then(G::unpack_tt_action)
            .and_then(|action| moves.iter().position(|candidate| *candidate == action))
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
