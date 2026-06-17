// SPDX-License-Identifier: GPL-3.0-or-later
// Move-ordering / killer / history / TT-best-action shuffling helpers.
// These are pure `Searcher<G>` methods; they live in a sibling impl
// block so the main `searcher/mod.rs` does not have to host them too.

use tgf_core::{Action, ActionList, Game};

use super::Searcher;

impl<G: Game> Searcher<G> {
    #[inline]
    pub(super) fn order_moves(
        &self,
        wb: &G::Workbench,
        key: u64,
        depth: i32,
        moves: &mut ActionList<256>,
    ) {
        let moves = moves.as_mut_slice();
        let mut scores = [0_i32; 256];
        assert!(moves.len() <= scores.len());
        for (i, action) in moves.iter().copied().enumerate() {
            scores[i] = self.move_score(wb, key, depth, action);
        }

        // Stable descending insertion sort.  This preserves the generated
        // move order for equal scores, matching master's partial insertion
        // sort, while computing the expensive Mill move score exactly once
        // per candidate.
        for i in 1..moves.len() {
            let action = moves[i];
            let score = scores[i];
            let mut j = i;
            while j > 0 && scores[j - 1] < score {
                moves[j] = moves[j - 1];
                scores[j] = scores[j - 1];
                j -= 1;
            }
            moves[j] = action;
            scores[j] = score;
        }
    }

    /// Shuffle the root move list using the internal xorshift RNG (P2-K).
    /// Mirrors master's MoveList<LEGAL>::shuffle() which is called at the
    /// start of executeSearch when Shuffling is enabled.
    pub(super) fn shuffle_moves(&mut self, moves: &mut ActionList<256>) {
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
        depth: i32,
        action: Action,
    ) -> i32 {
        // Master MovePicker::score (src/movepick.cpp:46-52) only adds
        // RATING_TT (=100) when ttMove is non-NONE, but TT_MOVE_ENABLE
        // is undefined in the default master config so ttMove always
        // stays MOVE_NONE and the bonus never fires.  The Rust port
        // mirrors that no-op by intentionally NOT consulting the TT for
        // a best-action bonus here.  TT lookups remain available
        // through `Searcher::search_mtdf_with_guess` for root move
        // recovery.  Killer / history bonuses stay gated on their own
        // toggles and default to off.
        let mut score = G::move_order_bias_ctx(wb, action, &self.options.move_order_context);
        if self.options.enable_killers
            && self
                .killers
                .get(&depth)
                .is_some_and(|killer| *killer == action)
        {
            score += 100_000;
        }
        if self.options.enable_history {
            score = score.saturating_add(self.history.get(&action).copied().unwrap_or_default());
        }
        score
    }

    #[inline]
    pub(super) fn record_cutoff(&mut self, depth: i32, action: Action) {
        if self.options.enable_killers {
            self.killers.insert(depth, action);
        }
        if self.options.enable_history {
            let bonus = depth.max(1).saturating_mul(depth.max(1));
            let entry = self.history.entry(action).or_insert(0);
            *entry = entry.saturating_add(bonus);
        }
    }

    #[allow(dead_code)]
    fn order_moves_by_tt(&self, key: u64, moves: &mut ActionList<256>) {
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
