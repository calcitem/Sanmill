// SPDX-License-Identifier: GPL-3.0-or-later
// `Workbench` / `Evaluator` / `Game` trait implementations for the
// CRTP search-hot-path types — `MillWorkbench`, `MillEvaluator`, and
// `MillGame`.  Hosting these here keeps `rules/mod.rs` focused on
// state / configuration rather than search-side wiring.

use std::mem::MaybeUninit;
use tgf_core::{
    Action, Evaluator, Game, GameStateSnapshot, MoveOrderContext, MoveOrderScore, SearchActionList,
    Workbench, pack_move_order_score,
};

use super::evaluation::{
    gameover_value, mills_pieces_count_difference, mobility_diff, remove_move_score,
    should_consider_mobility, should_focus_on_blocking_paths, surrounded_pieces_count,
};
use super::fen::position_key;
use super::move_priority::{
    RATING_BLOCK_ONE_MILL, RATING_ONE_MILL, RATING_STAR_SQUARE, is_star_square,
    move_priority_list_for_search, static_move_priority_for_search,
};
use super::potential_mills_count_at;
use super::types::{MillActionKind, MillActionState};
use super::{
    MILL_SEARCH_STACK_CAPACITY, MILL_TERMINAL_WIN_SCORE, MillEvaluator,
    MillFormationActionInPlacingPhase, MillGame, MillOutcomeReason, MillPhase, MillRules,
    MillState, MillVariantOptions, MillWorkbench, board_occupied_bitboard,
};
use super::{
    potential_mills_count_standard_unrestricted, potential_mills_count_standard_unrestricted_pair,
};

impl Workbench for MillWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state.clone())
    }

    fn key(&self) -> u64 {
        // Fast path: zobrist_key is cached on every state that goes
        // through MillRules::encode / decode round-trip.  We only fall
        // back to a full recompute when the workbench was built from
        // a hand-synthesised state (tests, FEN setup) that bypassed
        // encode.  position_key handles that fallback transparently.
        let cached = self.state.zobrist_key;
        if cached != 0 {
            cached
        } else {
            position_key(&self.state)
        }
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        self.state.phase == MillPhase::GameOver
    }

    fn do_move(&mut self, a: Action) {
        // Hot path: mutate the owned `MillState` in place via
        // `apply_to_state`, skipping the `snapshot()->encode->apply->decode`
        // round-trip the legacy path performed on every tree edge.  Undo uses
        // a compact scalar snapshot and only clones repetition history when
        // an irreversible action must restore a non-empty history window.
        // `apply_to_state` refreshes the cached Zobrist key incrementally, so
        // no `recompute_zobrist` is needed here.
        assert!(
            self.undo_stack.len() < MILL_SEARCH_STACK_CAPACITY,
            "Mill workbench undo stack capacity exceeded"
        );
        let undo = super::MillUndoState::capture(
            &self.state,
            a,
            &self.rules.options,
            self.rules.standard_fast_path,
        );
        // Search path: do NOT terminalise threefold (master `do_move` never
        // does).  Repetitions inside the tree are handled by the searcher's
        // `has_repeated` cut; a position that completes a threefold is scored
        // by its heuristic here, exactly like master.  The N-move rule is
        // likewise not adjudicated by do_move: terminal_score mirrors master's
        // search-time `> nMoveRule` / `>= endgameNMoveRule` thresholds.  The
        // The pre-root repetition history is kept unchanged; master stores
        // searched path nodes only in `ss`, which `Searcher` mirrors with its
        // own repetition stack.
        self.rules.apply_search_to_state(&mut self.state, a);
        self.undo_stack.push(undo);
    }

    fn undo_move(&mut self) {
        if let Some(undo) = self.undo_stack.pop() {
            undo.restore(&mut self.state);
        }
    }

    /// O(1) Zobrist-based prediction of the post-move key, used by
    /// the searcher's TT prefetch hints (see master
    /// `Position::key_after` in src/position.cpp).
    ///
    /// We predict only the dominant XOR contributions per action
    /// kind:
    ///
    ///   * Place  : key ^ side ^ psq[stm][to]
    ///   * Move   : key ^ side ^ psq[stm][from] ^ psq[stm][to]
    ///   * Remove : key ^ side ^ psq[opp][to]
    ///
    /// What we deliberately do NOT model here:
    ///
    ///   * Mill formation triggering pending_removals -> the misc
    ///     bits in the top KEY_MISC_BIT may not match the post-apply
    ///     value.  Since master's TT cluster index is taken from the
    ///     low bits and the prefetch is only a hint (the actual TT
    ///     save / probe re-validates via the 32-bit signature),
    ///     mispredicting the misc bits costs at most one wasted
    ///     prefetch.
    ///   * Capture-state target/count toggles (custodian /
    ///     intervention / leap activations).  These are rare relative
    ///     to total node count and reproducing the master apply
    ///     branching here would dwarf the prefetch savings.
    ///
    /// The result is therefore a *prefetch-quality* key, not a
    /// correctness-quality one.  Callers MUST NOT use it for TT save
    /// or repetition tracking; only the cache-line address matters.
    fn key_after(&mut self, action: Action) -> u64 {
        use super::types::MillActionKind;
        use super::zobrist::MILL_ZOBRIST;

        // Prerequisite: the cached key reflects the current state.
        // It always does on workbenches built via build_workbench,
        // because that path goes through MillRules::encode ->
        // recompute_zobrist.  The fallback path (state.zobrist_key
        // == 0) computes once and caches inline.
        let mut key = if self.state.zobrist_key != 0 {
            self.state.zobrist_key
        } else {
            super::zobrist::full_state_key(&self.state)
        };

        let stm = self.state.side_to_move;
        if !(0..2).contains(&stm) {
            // Side-to-move is undefined (e.g. GameOver); fall back to
            // do/undo round-trip so we never publish a wrong key.
            self.do_move(action);
            let next = self.key();
            self.undo_move();
            return next;
        }
        let stm = stm as usize;
        let opp = stm ^ 1;
        let to = action.to_node;
        let from = action.from_node;

        // Side-to-move flips on most apply branches.  The main
        // exceptions are the "stay-on-same-side" continuations after
        // a Place that activated pending_removals (where the active
        // side keeps the turn for the upcoming Remove).  Master's
        // key_after also flips Zobrist::side unconditionally and lets
        // the next apply correct it; we follow the same convention.
        key ^= MILL_ZOBRIST.side;

        match action.kind_tag {
            x if x == MillActionKind::Place as i16 => {
                if (0..24).contains(&to) {
                    key ^= MILL_ZOBRIST.psq[stm + 1][to as usize];
                }
            }
            x if x == MillActionKind::Move as i16 => {
                if (0..24).contains(&from) {
                    key ^= MILL_ZOBRIST.psq[stm + 1][from as usize];
                }
                if (0..24).contains(&to) {
                    key ^= MILL_ZOBRIST.psq[stm + 1][to as usize];
                }
            }
            x if x == MillActionKind::Remove as i16 => {
                if (0..24).contains(&to) {
                    key ^= MILL_ZOBRIST.psq[opp + 1][to as usize];
                }
            }
            _ => {
                // Unknown kind tag (e.g. Action::NONE).  Fall back to
                // the do/undo + key default.
                self.do_move(action);
                let next = self.key();
                self.undo_move();
                return next;
            }
        }

        if key == 0 { 1 } else { key }
    }

    #[inline]
    fn current_repetition_count(&self) -> usize {
        let key = self.key();
        if key == 0 {
            return 0;
        }
        self.state
            .key_history
            .iter()
            .take(self.state.key_history.len().saturating_sub(1))
            .filter(|k| **k == key)
            .count()
    }

    #[inline]
    fn has_current_repetition(&self) -> bool {
        let key = self.key();
        if key == 0 {
            return false;
        }
        self.state
            .key_history
            .iter()
            .take(self.state.key_history.len().saturating_sub(1))
            .any(|k| *k == key)
    }

    #[inline]
    fn current_position_resets_repetition(&self) -> bool {
        self.root_position_resets_repetition
    }
}

impl Evaluator<MillWorkbench> for MillEvaluator {
    /// Static evaluator translated from `src/evaluate.cpp::Evaluation::value`
    /// in the legacy C++ engine.
    ///
    /// The constants are scaled to the same units as `VALUE_EACH_PIECE`
    /// (`PieceValue = 5`) and `VALUE_MATE = 80`, so search scores stay
    /// numerically compatible with the legacy `MTDF` aspiration windows.
    /// A perspective swap at the end mirrors C++ "value from the side to
    /// move" convention.
    fn score(wb: &MillWorkbench) -> i32 {
        // Terminal score constants are fixed by the TT mate-distance encoding
        // and UCI `score mate` output; do NOT make these tunable.
        const VALUE_MATE: i32 = 80;
        const VALUE_DRAW: i32 = 0;

        let state = &wb.state;
        let options = &wb.rules.options;
        let weights = &wb.rules.eval_weights;
        let mut value: i32 = 0;

        let effective_on_board = legacy_removal_count_view(state, options);
        let removals_diff = signed_pending_removals_diff(state);
        let in_hand_diff = i32::from(state.pieces_in_hand[0]) - i32::from(state.pieces_in_hand[1]);
        let on_board_diff = i32::from(effective_on_board[0]) - i32::from(effective_on_board[1]);
        let action_is_remove = state.pending_removals[0] > 0 || state.pending_removals[1] > 0;

        match state.phase {
            MillPhase::Ready => {}
            MillPhase::Placing
                if matches!(
                    options.mill_formation_action_in_placing_phase,
                    MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
                ) =>
            {
                if action_is_remove {
                    value += weights.piece_value * removals_diff;
                } else {
                    value += weights.mill_count * mills_pieces_count_difference(state, options);
                }
            }
            MillPhase::Placing | MillPhase::Moving => {
                if should_consider_mobility(options) {
                    value += weights.mobility * mobility_diff(state, options);
                }
                if !should_focus_on_blocking_paths(state, options) {
                    value += weights.piece_value * in_hand_diff;
                    value += weights.piece_value * on_board_diff;
                    if action_is_remove {
                        value += weights.piece_value * removals_diff;
                    }
                }
            }
            MillPhase::GameOver => {
                value = gameover_value(state, options, VALUE_MATE, VALUE_DRAW);
            }
        }

        if state.side_to_move == 1 {
            value = -value;
        }
        value
    }
}

fn legacy_removal_count_view(state: &MillState, options: &MillVariantOptions) -> [u8; 2] {
    let mut counts = state.pieces_on_board;
    if !matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
    ) {
        return counts;
    }
    if state.phase != MillPhase::Moving {
        return counts;
    }

    let own_pending = [
        state.remove_own_piece(0) && state.pending_removals[0] > 0,
        state.remove_own_piece(1) && state.pending_removals[1] > 0,
    ];
    let pending_side = match own_pending {
        [true, false] => 0_usize,
        [false, true] => 1_usize,
        _ => return counts,
    };
    let completed_side = pending_side ^ 1;
    if state.pending_removals[completed_side] != 0 || state.remove_own_piece(completed_side) {
        return counts;
    }

    // Legacy C++ negative `pieceToRemoveCount` requires the mover to pick
    // an own piece, but `remove_piece()` still decrements `pieceOnBoardCount`
    // for `them`. Keep Rust's board/count invariants intact and reproduce
    // that transient count view only for evaluation until the other side's
    // own-removal quota clears and the legacy counts become consistent again.
    counts[pending_side] = counts[pending_side].saturating_sub(1);
    counts[completed_side] = counts[completed_side].saturating_add(1);
    counts
}

fn signed_pending_removals_diff(state: &MillState) -> i32 {
    let signed = |side: usize| -> i32 {
        let count = i32::from(state.pending_removals[side]);
        if state.remove_own_piece(side) {
            -count
        } else {
            count
        }
    };
    signed(0) - signed(1)
}

struct MillMoveOrderScorer<'a> {
    state: &'a MillState,
    options: &'a MillVariantOptions,
    side: i8,
    valid_side: bool,
    opponent: i8,
    side_bb: u32,
    opponent_bb: u32,
    side_piece_count: u32,
    opponent_piece_count: u32,
    black_piece_count: u32,
    standard_place_no_move: bool,
    standard_no_diagonal_no_one_time: bool,
    algorithm_is_mcts: bool,
}

impl<'a> MillMoveOrderScorer<'a> {
    #[inline]
    fn new(wb: &'a MillWorkbench, ctx: &'a MoveOrderContext) -> Self {
        let state = &wb.state;
        let options = &wb.rules.options;
        let side = state.side_to_move;
        let valid_side = (0..2).contains(&side);
        let side_idx = if valid_side { side as usize } else { 0 };
        let opponent = side ^ 1;
        let opponent_idx = side_idx ^ 1;
        let side_bb = state.by_color_bb[side_idx];
        let opponent_bb = state.by_color_bb[opponent_idx];
        let [white_piece_count, black_piece_count] = if state.delayed_marked_pieces == 0 {
            debug_assert_eq!(
                state.by_color_bb[0].count_ones() as u8,
                state.pieces_on_board[0],
                "white piece count must match the white bitboard"
            );
            debug_assert_eq!(
                state.by_color_bb[1].count_ones() as u8,
                state.pieces_on_board[1],
                "black piece count must match the black bitboard"
            );
            [
                u32::from(state.pieces_on_board[0]),
                u32::from(state.pieces_on_board[1]),
            ]
        } else {
            // Delayed-marked pieces remain on the board but are deliberately
            // absent from by-color live bitboards. Count live pieces from the
            // bitboards only for that uncommon variant path.
            [
                state.by_color_bb[0].count_ones(),
                state.by_color_bb[1].count_ones(),
            ]
        };
        let piece_counts = [white_piece_count, black_piece_count];
        let standard_no_diagonal_no_one_time =
            !options.has_diagonal_lines && !options.one_time_use_mill;
        Self {
            state,
            options,
            side,
            valid_side,
            opponent,
            side_bb,
            opponent_bb,
            side_piece_count: piece_counts[side_idx],
            opponent_piece_count: piece_counts[opponent_idx],
            black_piece_count,
            standard_place_no_move: state.phase == MillPhase::Placing
                && !options.has_diagonal_lines
                && !options.may_move_in_placing_phase
                && !options.one_time_use_mill
                && ctx.algorithm != tgf_core::MoveOrderAlgorithm::Mcts,
            standard_no_diagonal_no_one_time,
            algorithm_is_mcts: ctx.algorithm == tgf_core::MoveOrderAlgorithm::Mcts,
        }
    }

    #[inline]
    fn score(&self, action: Action) -> i32 {
        let to = action.to_node as usize;
        if to >= 24 {
            return 0;
        }
        let kind = action.kind_tag;

        if kind == MillActionKind::Remove as i16 {
            return remove_move_score(self.state, self.options, to);
        }

        if kind != MillActionKind::Place as i16 && kind != MillActionKind::Move as i16 {
            return 0;
        }

        if !self.valid_side {
            return 0;
        }

        let can_form_mill = if kind == MillActionKind::Place as i16 {
            self.side_piece_count >= 2
        } else {
            self.side_piece_count >= 3
        };
        let can_block_mill = self.opponent_piece_count >= 2;
        if kind == MillActionKind::Place as i16 && self.standard_place_no_move {
            if !can_form_mill && !can_block_mill {
                return 0;
            }
            let (our_mills, their_mills) = if can_form_mill && can_block_mill {
                potential_mills_count_standard_unrestricted_pair(
                    self.side_bb,
                    self.opponent_bb,
                    to,
                    None,
                )
            } else if can_form_mill {
                (
                    potential_mills_count_standard_unrestricted(self.side_bb, to, None),
                    0,
                )
            } else {
                (
                    0,
                    potential_mills_count_standard_unrestricted(self.opponent_bb, to, None),
                )
            };
            let our_mills = our_mills as i32;
            if our_mills > 0 {
                return RATING_ONE_MILL * our_mills;
            }
            return RATING_BLOCK_ONE_MILL * their_mills as i32;
        }
        let from = if kind == MillActionKind::Move as i16 {
            Some(action.from_node as usize)
        } else {
            None
        };

        if self.standard_no_diagonal_no_one_time {
            let our_mills = if can_form_mill {
                potential_mills_count_standard_unrestricted(self.side_bb, to, from) as i32
            } else {
                0
            };
            let mut score = 0_i32;
            if our_mills > 0 {
                score += RATING_ONE_MILL * our_mills;
            } else if self.state.phase == MillPhase::Placing
                && !self.options.may_move_in_placing_phase
            {
                if can_block_mill {
                    let their_mills =
                        potential_mills_count_standard_unrestricted(self.opponent_bb, to, None)
                            as i32;
                    score += RATING_BLOCK_ONE_MILL * their_mills;
                }
            } else if can_block_mill
                && (self.state.phase == MillPhase::Moving
                    || (self.state.phase == MillPhase::Placing
                        && self.options.may_move_in_placing_phase))
            {
                let their_mills =
                    potential_mills_count_standard_unrestricted(self.opponent_bb, to, None) as i32;
                if their_mills > 0 {
                    let (_, theirs, _) = surrounded_pieces_count(self.state, self.options, to);
                    // Master keys this branch off legacy `Square` parity.
                    // The master-normalized node is `Square - 8`, so parity
                    // is preserved.
                    let parity_match = if to.is_multiple_of(2) {
                        theirs == 3
                    } else {
                        theirs == 2
                    };
                    if parity_match {
                        score += RATING_BLOCK_ONE_MILL * their_mills;
                    }
                }
            }
            if self.state.phase == MillPhase::Placing
                && self.side == 1
                && self.algorithm_is_mcts
                && self.black_piece_count < 2
                && is_star_square(self.options, to)
            {
                score += RATING_STAR_SQUARE;
            }
            return score;
        }

        let our_mills = if can_form_mill {
            potential_mills_count_at(self.state, self.options, to, self.side, from) as i32
        } else {
            0
        };
        let mut score = 0_i32;
        if our_mills > 0 {
            score += RATING_ONE_MILL * our_mills;
        } else if self.state.phase == MillPhase::Placing && !self.options.may_move_in_placing_phase
        {
            if can_block_mill {
                let their_mills =
                    potential_mills_count_at(self.state, self.options, to, self.opponent, None)
                        as i32;
                score += RATING_BLOCK_ONE_MILL * their_mills;
            }
        } else if can_block_mill
            && (self.state.phase == MillPhase::Moving
                || (self.state.phase == MillPhase::Placing
                    && self.options.may_move_in_placing_phase))
        {
            let their_mills =
                potential_mills_count_at(self.state, self.options, to, self.opponent, None) as i32;
            if their_mills > 0 {
                let (_, theirs, _) = surrounded_pieces_count(self.state, self.options, to);
                // Master keys this branch off legacy `Square` parity.  The
                // master-normalized node is `Square - 8`, so parity is
                // preserved.
                let parity_match = if to.is_multiple_of(2) {
                    theirs == 3
                } else {
                    theirs == 2
                };
                if parity_match {
                    score += RATING_BLOCK_ONE_MILL * their_mills;
                }
            }
        }

        if self.state.phase == MillPhase::Placing
            && self.side == 1
            && (self.options.has_diagonal_lines || self.algorithm_is_mcts)
            && self.black_piece_count < 2
            && is_star_square(self.options, to)
        {
            score += RATING_STAR_SQUARE;
        }

        score
    }

    #[inline]
    fn score_actions(
        &self,
        actions: &[Action],
        scores: &mut [MaybeUninit<MoveOrderScore>],
    ) -> bool {
        assert!(
            actions.len() <= scores.len(),
            "Mill move-order score buffer is smaller than action list"
        );
        if self.standard_place_no_move {
            return self.score_standard_place_no_move_actions(actions, scores);
        }
        if self.standard_no_diagonal_no_one_time
            && self.valid_side
            && self.state.phase == MillPhase::Moving
            && actions
                .first()
                .is_some_and(|action| action.kind_tag == MillActionKind::Move as i16)
        {
            debug_assert!(
                actions
                    .iter()
                    .all(|action| action.kind_tag == MillActionKind::Move as i16),
                "Mill moving-phase action lists must contain only move actions"
            );
            return self.score_standard_moving_actions(actions, scores);
        }
        let mut previous_score = 0_i32;
        let mut has_previous = false;
        let mut needs_sort = false;
        for (i, action) in actions.iter().copied().enumerate() {
            let score = self.score(action);
            scores[i].write(pack_move_order_score(score));
            if has_previous && previous_score < score {
                needs_sort = true;
            }
            previous_score = score;
            has_previous = true;
        }
        needs_sort
    }

    #[inline]
    fn score_standard_moving_actions(
        &self,
        actions: &[Action],
        scores: &mut [MaybeUninit<MoveOrderScore>],
    ) -> bool {
        let can_form_mill = self.side_piece_count >= 3;
        let can_block_mill = self.opponent_piece_count >= 2;
        // No generated standard moving action can receive a static score.
        if !can_form_mill && !can_block_mill {
            return false;
        }
        let mut block_scores = [STANDARD_BLOCK_SCORE_UNKNOWN; 24];

        let mut previous_score = 0_i32;
        let mut has_previous = false;
        let mut needs_sort = false;
        for (i, action) in actions.iter().copied().enumerate() {
            let to = action.to_node as usize;
            let from = action.from_node as usize;
            let score = if to < 24 && from < 24 {
                let our_mills = if can_form_mill {
                    potential_mills_count_standard_unrestricted(self.side_bb, to, Some(from))
                } else {
                    0
                };
                if our_mills > 0 {
                    RATING_ONE_MILL * our_mills as i32
                } else if can_block_mill {
                    standard_moving_block_score(&mut block_scores, self.opponent_bb, to)
                } else {
                    0
                }
            } else {
                self.score(action)
            };
            scores[i].write(pack_move_order_score(score));
            if has_previous && previous_score < score {
                needs_sort = true;
            }
            previous_score = score;
            has_previous = true;
        }
        needs_sort
    }

    #[inline]
    fn score_standard_place_no_move_actions(
        &self,
        actions: &[Action],
        scores: &mut [MaybeUninit<MoveOrderScore>],
    ) -> bool {
        let can_form_mill = self.side_piece_count >= 2;
        let can_block_mill = self.opponent_piece_count >= 2;
        // Early placing plies have only zero-valued static ordering scores.
        if !can_form_mill && !can_block_mill {
            return false;
        }
        let mut node_scores = [0_i32; 24];

        for (to, score) in node_scores.iter_mut().enumerate() {
            let (our_mills, their_mills) = if can_form_mill && can_block_mill {
                potential_mills_count_standard_unrestricted_pair(
                    self.side_bb,
                    self.opponent_bb,
                    to,
                    None,
                )
            } else if can_form_mill {
                (
                    potential_mills_count_standard_unrestricted(self.side_bb, to, None),
                    0,
                )
            } else {
                (
                    0,
                    potential_mills_count_standard_unrestricted(self.opponent_bb, to, None),
                )
            };
            *score = if our_mills > 0 {
                RATING_ONE_MILL * our_mills as i32
            } else {
                RATING_BLOCK_ONE_MILL * their_mills as i32
            };
        }

        let mut previous_score = 0_i32;
        let mut has_previous = false;
        let mut needs_sort = false;
        for (i, action) in actions.iter().copied().enumerate() {
            let to = action.to_node as usize;
            let score = if action.kind_tag == MillActionKind::Place as i16 && to < 24 {
                // Standard placing nodes ask the same two-line mill questions
                // for many siblings.  Cache the layer-local answers once and
                // keep the exact score() semantics for out-of-shape actions.
                node_scores[to]
            } else {
                self.score(action)
            };
            scores[i].write(pack_move_order_score(score));
            if has_previous && previous_score < score {
                needs_sort = true;
            }
            previous_score = score;
            has_previous = true;
        }
        needs_sort
    }
}

const STANDARD_BLOCK_SCORE_UNKNOWN: i32 = i32::MIN;

#[inline(always)]
fn standard_moving_block_score(cache: &mut [i32; 24], opponent_bb: u32, to: usize) -> i32 {
    let cached = cache[to];
    if cached != STANDARD_BLOCK_SCORE_UNKNOWN {
        return cached;
    }

    let their_mills = potential_mills_count_standard_unrestricted(opponent_bb, to, None);
    let score = if their_mills == 0 {
        0
    } else {
        // In moving-phase standard rules the block bonus depends only on the
        // destination square: opponent potential mills at `to` and the count
        // of opponent pieces adjacent to `to`.  Lazily cache it per batch so
        // sparse action lists do not pay for all 24 board nodes.
        let their_neighbors =
            (crate::topology::standard_neighbor_mask_for(to) & opponent_bb).count_ones() as i32;
        let parity_match = if to.is_multiple_of(2) {
            their_neighbors == 3
        } else {
            their_neighbors == 2
        };
        if parity_match {
            RATING_BLOCK_ONE_MILL * their_mills as i32
        } else {
            0
        }
    };
    cache[to] = score;
    score
}

#[inline]
fn score_remove_actions(
    state: &MillState,
    options: &MillVariantOptions,
    actions: &[Action],
    scores: &mut [MaybeUninit<MoveOrderScore>],
) -> bool {
    assert!(
        actions.len() <= scores.len(),
        "Mill move-order score buffer is smaller than action list"
    );
    let scorer = MillRemoveOrderScorer::new(state, options);
    let mut previous_score = 0_i32;
    let mut has_previous = false;
    let mut needs_sort = false;
    for (i, action) in actions.iter().copied().enumerate() {
        let to = action.to_node as usize;
        let score = if to < 24 { scorer.score(to) } else { 0 };
        scores[i].write(pack_move_order_score(score));
        if has_previous && previous_score < score {
            needs_sort = true;
        }
        previous_score = score;
        has_previous = true;
    }
    needs_sort
}

struct MillRemoveOrderScorer<'a> {
    state: &'a MillState,
    options: &'a MillVariantOptions,
    valid_side: bool,
    side: i8,
    opponent: i8,
    side_bb: u32,
    opponent_bb: u32,
    occupied: u32,
    standard_unrestricted: bool,
}

impl<'a> MillRemoveOrderScorer<'a> {
    #[inline]
    fn new(state: &'a MillState, options: &'a MillVariantOptions) -> Self {
        let side = state.side_to_move;
        let valid_side = (0..2).contains(&side);
        let side_idx = if valid_side { side as usize } else { 0 };
        let opponent = side ^ 1;
        let opponent_idx = side_idx ^ 1;
        Self {
            state,
            options,
            valid_side,
            side,
            opponent,
            side_bb: state.by_color_bb[side_idx],
            opponent_bb: state.by_color_bb[opponent_idx],
            occupied: board_occupied_bitboard(state),
            standard_unrestricted: state.delayed_marked_pieces == 0
                && !options.has_diagonal_lines
                && !options.one_time_use_mill,
        }
    }

    #[inline]
    fn score(&self, to: usize) -> i32 {
        if !self.valid_side {
            return 0;
        }

        let (our_mills, their_mills) = if self.standard_unrestricted {
            let (our_mills, their_mills) = potential_mills_count_standard_unrestricted_pair(
                self.side_bb,
                self.opponent_bb,
                to,
                None,
            );
            (our_mills as i32, their_mills as i32)
        } else {
            (
                potential_mills_count_at(self.state, self.options, to, self.side, None) as i32,
                potential_mills_count_at(self.state, self.options, to, self.opponent, None) as i32,
            )
        };

        // Remove scoring is called for every legal removal target in the same
        // node. Cache the side bitboards and occupied mask once, then keep the
        // exact bucket arithmetic from `remove_move_score`.
        let neighbor_mask = if self.options.has_diagonal_lines {
            crate::topology::diagonal_neighbor_mask_for(to)
        } else {
            crate::topology::standard_neighbor_mask_for(to)
        };
        let our_count = (neighbor_mask & self.side_bb).count_ones() as i32;
        let their_count = (neighbor_mask & self.opponent_bb).count_ones() as i32;
        let empty_count = (neighbor_mask & !self.occupied).count_ones() as i32;

        let mut score = 0_i32;
        if our_mills > 0 && their_count == 0 {
            score += 1;
            if our_count > 0 {
                score += our_count;
            }
        }
        if their_mills > 0 && their_count >= 2 {
            score -= their_count;
            if our_count == 0 {
                score -= 1;
            }
        }
        score + empty_count
    }
}

#[inline]
fn pack_mill_tt_node(node: i16) -> Option<u16> {
    if node == -1 {
        return Some(31);
    }
    (0..24).contains(&node).then_some(node as u16)
}

#[inline]
fn unpack_mill_tt_node(code: u16) -> Option<i16> {
    if code == 31 {
        return Some(-1);
    }
    (code < 24).then_some(code as i16)
}

#[inline]
fn pack_mill_tt_action(action: Action) -> Option<u16> {
    if action.is_none() || action.aux != -1 || action.payload_bits != 0 {
        return None;
    }
    let kind = action.kind_tag;
    if !(MillActionKind::Place as i16..=MillActionKind::Remove as i16).contains(&kind) {
        return None;
    }
    let from = pack_mill_tt_node(action.from_node)?;
    let to = pack_mill_tt_node(action.to_node)?;
    // Layout before the +1 sentinel offset:
    //   [0:1]  kind  (Place/Move/Remove)
    //   [2:6]  from  (0..23 or 31 for none)
    //   [7:11] to    (0..23 or 31 for none)
    // Code 0 is reserved for "no TT move" in the side storage.
    let raw = (kind as u16) | (from << 2) | (to << 7);
    Some(raw + 1)
}

#[inline]
fn unpack_mill_tt_action(packed: u16) -> Option<Action> {
    if packed == 0 {
        return None;
    }
    let raw = packed - 1;
    let kind = (raw & 0x03) as i16;
    if !(MillActionKind::Place as i16..=MillActionKind::Remove as i16).contains(&kind) {
        return None;
    }
    let from = unpack_mill_tt_node((raw >> 2) & 0x1f)?;
    let to = unpack_mill_tt_node((raw >> 7) & 0x1f)?;
    Some(Action {
        kind_tag: kind,
        from_node: from,
        to_node: to,
        aux: -1,
        payload_bits: 0,
    })
}

impl Game for MillGame {
    type Workbench = MillWorkbench;
    type Evaluator = MillEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        let mut rules = MillRules::new(self.options.clone());
        rules.set_eval_weights(self.eval_weights);
        let mut state = rules.decode_with_options(snap);
        if self.root_repetition_history.len() > state.key_history.len() {
            state.key_history = self.root_repetition_history.clone();
            state.key_history_len = state.key_history.len();
        }
        MillWorkbench {
            rules,
            state,
            undo_stack: Vec::with_capacity(MILL_SEARCH_STACK_CAPACITY),
            root_position_resets_repetition: self.root_position_resets_repetition,
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut SearchActionList) {
        wb.rules
            .legal_actions_ctx(&wb.state, out, &tgf_core::MoveOrderContext::default());
    }

    fn generate_legal_ctx(
        wb: &Self::Workbench,
        out: &mut SearchActionList,
        ctx: &MoveOrderContext,
    ) {
        wb.rules.legal_actions_ctx(&wb.state, out, ctx);
    }

    fn generate_quiescence_ctx(
        wb: &Self::Workbench,
        out: &mut SearchActionList,
        ctx: &MoveOrderContext,
        kind_tag: i16,
    ) {
        if kind_tag != MillActionKind::Remove as i16
            || wb.state.action_for_legal_generation() != MillActionState::Remove
            || wb.state.side_to_move < 0
        {
            Self::generate_legal_ctx(wb, out, ctx);
            out.retain(|action| action.kind_tag == kind_tag);
            return;
        }

        let side = wb.state.side_to_move as usize;
        if side >= 2 || wb.state.pending_removals[side] == 0 {
            return;
        }

        let priority_storage;
        let priority = if ctx.shuffling {
            priority_storage = move_priority_list_for_search(&wb.rules.options, ctx);
            &priority_storage
        } else {
            static_move_priority_for_search(&wb.rules.options, ctx)
        };
        wb.rules.generate_remove_actions(&wb.state, out, priority);
    }

    /// MovePicker-style move ordering bonus translated from
    /// `src/movepick.cpp::score()`.  Combines mill formation, mill blocking,
    /// star-square opening preference, and capture-target preference.  The
    /// numeric weights match `RATING_*` constants in `src/types.h`.  Rust now
    /// promotes legal TT moves before static scoring by default; killer /
    /// history bonuses stay disabled unless a future parity-and-performance
    /// audit proves they help.
    ///
    /// # Note on master's "score-negation" bug (Diff 17)
    ///
    /// Master `src/movepick.cpp:152-154` runs after the per-move scoring
    /// loop:
    /// ```cpp
    ///     if (!pos.shouldFocusOnBlockingPaths()) {
    ///         cur->value = -cur->value;
    ///     }
    /// ```
    /// At that point `cur` already equals `endMoves` (the for-loop
    /// post-incremented past the last entry), so the negation lands on
    /// the one-past-end placeholder slot rather than reversing every
    /// move's value.  This is a master bug noted in
    /// SEARCH_DIFF_REPORT.md (Diff 4.2) -- effectively master never
    /// reverses the score, identical to the Rust port (which simply
    /// returns the positive score here).  No code change needed; this
    /// comment documents the alignment so future readers do not
    /// reintroduce a literal port of the buggy negation.
    #[inline]
    fn move_order_bias_ctx(
        wb: &Self::Workbench,
        action: Action,
        ctx: &tgf_core::MoveOrderContext,
    ) -> i32 {
        MillMoveOrderScorer::new(wb, ctx).score(action)
    }

    #[inline]
    fn move_order_scores_ctx(
        wb: &Self::Workbench,
        actions: &[Action],
        ctx: &MoveOrderContext,
        scores: &mut [MaybeUninit<MoveOrderScore>],
    ) -> bool {
        if actions
            .first()
            .is_some_and(|action| action.kind_tag == MillActionKind::Remove as i16)
        {
            debug_assert!(
                actions
                    .iter()
                    .all(|action| action.kind_tag == MillActionKind::Remove as i16),
                "Mill remove-action lists must not mix place/move actions"
            );
            return score_remove_actions(&wb.state, &wb.rules.options, actions, scores);
        }
        MillMoveOrderScorer::new(wb, ctx).score_actions(actions, scores)
    }

    /// Mill terminal-score for the searcher.  Mirrors master
    /// `Search::search` (src/search.cpp:142-151) and
    /// `Search::qsearch` (src/search.cpp:60-64), both of which take
    /// `Eval::evaluate(*pos)` and add `+depth` for positive scores
    /// (winning side, prefer faster wins) or subtract `depth` for
    /// negative scores (losing side, prefer slower losses).
    ///
    /// Diff 8 alignment: the Rust mate-distance direction matches
    /// master's `eval += depth` / `eval -= depth` exactly because
    /// both branches accumulate `+distance` toward the absolute value
    /// (Rust's winner-perspective branch returns +MATE+distance and
    /// master's positive eval becomes positive_eval+depth; the loser-
    /// perspective branch returns -MATE-distance which equals
    /// negative_eval-depth in master).  Verified against
    /// SEARCH_DIFF_REPORT.md.
    #[inline]
    fn terminal_score(wb: &Self::Workbench, perspective: i8, depth: i32) -> Option<i32> {
        if wb.state.phase == MillPhase::GameOver && wb.state.winner == 2 {
            // Master scores every in-search repetition as `VALUE_DRAW + 1`
            // (src/search.cpp `has_repeated` cut).  Because that cut fires on
            // the SECOND occurrence, the search never actually reaches a 3-fold
            // terminal node, so this branch is effectively root-only (a game
            // that is already a draw before the engine is asked to move).  We
            // keep it consistent with the in-search bias so the rare root case
            // scores the same small positive draw value.  Other draws (50-move
            // / stalemate / full-board) stay neutral at VALUE_DRAW (0).
            if wb.state.outcome_reason == MillOutcomeReason::DrawThreefold {
                return Some(Self::repetition_draw_bias());
            }
            return Some(0);
        }
        if wb.state.phase != MillPhase::GameOver {
            return None;
        }
        let distance = depth.max(0);
        if wb.state.winner == perspective {
            Some(MILL_TERMINAL_WIN_SCORE + distance)
        } else {
            Some(-MILL_TERMINAL_WIN_SCORE - distance)
        }
    }

    #[inline]
    fn search_alpha_override(wb: &Self::Workbench) -> Option<i32> {
        search_n_move_draw_alpha_override(wb)
    }

    #[inline]
    fn action_resets_repetition(action: Action) -> bool {
        // Master `Position::has_repeated` walks the search stack back only as
        // far as the last REMOVE (capture); a placement does NOT reset that
        // window.  We therefore mark only Remove as a barrier.  (Placing
        // positions can never collide with moving positions because the piece
        // counts differ, so omitting Place as a barrier is faithful AND
        // harmless for detection.)
        action.kind_tag == MillActionKind::Remove as i16
    }

    #[inline]
    fn pack_tt_action(action: Action) -> Option<u16> {
        pack_mill_tt_action(action)
    }

    #[inline]
    fn unpack_tt_action(packed: u16) -> Option<Action> {
        unpack_mill_tt_action(packed)
    }

    /// Mill MCTS post-search material score, mirroring master
    /// `monte_carlo_tree_search` (src/mcts.cpp:391-395):
    ///   `(piece_on_board(stm) + piece_in_hand(stm)
    ///     - piece_on_board(opp) - piece_in_hand(opp)) * VALUE_EACH_PIECE`
    /// where VALUE_EACH_PIECE = 5 in master `src/types.h`.
    #[inline]
    fn mcts_terminal_score(wb: &Self::Workbench) -> i32 {
        const VALUE_EACH_PIECE: i32 = 5;
        let state = &wb.state;
        let stm = state.side_to_move;
        if !(0..2).contains(&stm) {
            return 0;
        }
        let stm = stm as usize;
        let opp = stm ^ 1;
        (i32::from(state.pieces_on_board[stm]) + i32::from(state.pieces_in_hand[stm])
            - i32::from(state.pieces_on_board[opp])
            - i32::from(state.pieces_in_hand[opp]))
            * VALUE_EACH_PIECE
    }

    // Mill intentionally does NOT override `root_short_circuit_draw` and does
    // not bias root tie-breaks toward draws. The engine keeps the FIRST move
    // on ties: the standard threefold is already handled by `terminal_score`.
    // Master's `g7-d7`-style "finish the game" choices therefore emerge
    // naturally from the in-search `has_repeated` cut alone:
    //
    //   * `terminal_score` keeps a real DrawThreefold at the small positive
    //     `VALUE_DRAW + 1` master uses for repetitions;
    //   * `Searcher::alpha_beta` reproduces master `has_repeated` exactly --
    //     after the TT probe, second-occurrence detection across both the
    //     pre-root reversible history (`Workbench::current_repetition_count`)
    //     and the in-search path with a REMOVE-only barrier
    //     (`action_resets_repetition`) -- returning `VALUE_DRAW + 1` to prune
    //     the cycle without ever adjudicating a draw before `apply` reaches
    //     the standard third occurrence (handled by `GameRules::apply`).
}

#[inline]
fn search_n_move_draw_alpha_override(wb: &MillWorkbench) -> Option<i32> {
    let state = &wb.state;
    let options = &wb.rules.options;
    let is_move_counting_phase = state.phase == MillPhase::Moving
        || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase);
    if !is_move_counting_phase {
        return None;
    }

    // Master separates real-play adjudication from search-tree scoring:
    // Position::check_if_game_is_over uses `>= nMoveRule`, but
    // Search::search uses `rule50_count() > nMoveRule` for the regular
    // rule and `>= endgameNMoveRule` for the three-piece endgame rule, then
    // applies it as `alpha = VALUE_DRAW` instead of returning immediately.
    // Keeping both asymmetries avoids ending reversible search lines before
    // master's later TT and repetition checks can participate.
    let ply_since_capture = u32::from(state.ply_since_capture);
    let is_endgame = options.endgame_n_move_rule > 0
        && options.endgame_n_move_rule < options.n_move_rule
        && state.pieces_on_board.contains(&3);
    let draws = if is_endgame {
        ply_since_capture >= options.endgame_n_move_rule
    } else {
        options.n_move_rule > 0 && ply_since_capture > options.n_move_rule
    };
    draws.then_some(0)
}
