// SPDX-License-Identifier: GPL-3.0-or-later
// Implementation of `GameRules for MillRules` (`legal_actions`,
// `is_legal`, `apply`, `outcome`) plus the supporting `MillRules`
// helper methods consumed by the apply / legal-actions paths.
//
// The companion `mod.rs` exposes every collaborator (state field,
// transition helper, capture detector, …) as `pub(super)` so this file
// can `use super::*` and stay close to the original layout — the goal
// here is purely to shrink `mod.rs`, not to rewrite the rule engine.

use super::*;

impl MillRules {
    fn hydrate_repetition_history_from_snapshots(
        &self,
        state: &mut MillState,
        snap: &GameStateSnapshot,
        history: &[GameStateSnapshot],
    ) {
        if !self.options.threefold_repetition_rule {
            return;
        }
        let rebuilt = Self::repetition_history_from_snapshots(snap, history);
        if rebuilt.len() > state.key_history.len() {
            state.key_history = rebuilt;
            state.key_history_len = state.key_history.len();
        }
    }

    /// Rebuild the runtime repetition history from a kernel-style snapshot
    /// stack without expanding the compact snapshot payload.
    ///
    /// The history slice must be chronological and must not include `snap`.
    /// Each snapshot after a reversible Move carries `key_history_len > 0`;
    /// Place and Remove transitions clear it, which gives us an exact reset
    /// marker.  Scanning backwards is bounded to master's 256-key cap and is
    /// only used at runtime boundaries, never inside the search tree.
    pub fn repetition_history_from_snapshots(
        snap: &GameStateSnapshot,
        history: &[GameStateSnapshot],
    ) -> Vec<u64> {
        let decoded_current = Self::decode(snap);
        if history.is_empty() {
            return decoded_current.key_history;
        }

        let mut reversed = Vec::new();
        for candidate in history.iter().chain(std::iter::once(snap)).rev() {
            let decoded = Self::decode(candidate);
            if decoded.key_history_len == 0 {
                break;
            }
            let key = candidate.zobrist_key;
            debug_assert_ne!(key, 0, "Mill snapshots must carry a non-zero key");
            reversed.push(key);
            if reversed.len() == MILL_REPETITION_HISTORY_CAP {
                break;
            }
        }

        if reversed.is_empty() {
            decoded_current.key_history
        } else {
            reversed.reverse();
            reversed
        }
    }
}

impl GameRules for MillRules {
    fn game_id(&self) -> &str {
        "mill"
    }

    fn topology(&self) -> &dyn BoardTopology {
        &self.topology
    }

    fn initial_state(&self, _variant_options: &[u8]) -> GameStateSnapshot {
        let state = MillState {
            board: [0; 24],
            side_to_move: 0,
            phase: MillPhase::Placing,
            move_number: 0,
            pieces_in_hand: [self.options.piece_count, self.options.piece_count],
            pieces_on_board: [0, 0],
            pending_removals: [0, 0],
            winner: -1,
            ..MillState::default()
        };
        self.encode(state)
    }

    fn legal_actions(&self, snap: &GameStateSnapshot, out: &mut ActionList<256>) {
        let state = Self::decode(snap);
        match state.action_for_legal_generation() {
            MillActionState::Remove => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(&state, out, &default_dense_priority());
                }
            }
            MillActionState::Place => {
                if state.pieces_in_hand[state.side_to_move as usize] > 0 {
                    for (node, piece) in state.board.iter().enumerate() {
                        if *piece == 0 {
                            out.push(Action {
                                kind_tag: MillActionKind::Place as i16,
                                from_node: -1,
                                to_node: node as i16,
                                aux: -1,
                                payload_bits: 0,
                            });
                        }
                    }
                }
                if self.options.may_move_in_placing_phase {
                    self.generate_move_actions(&state, out, false);
                }
            }
            MillActionState::Select => {
                if state.phase == MillPhase::Moving {
                    self.generate_move_actions(&state, out, true);
                }
            }
            MillActionState::GameOver => {}
        }
    }

    fn apply(&self, snap: &GameStateSnapshot, action: Action) -> GameStateSnapshot {
        self.apply_with_history(snap, action, &[])
    }

    fn apply_with_history(
        &self,
        snap: &GameStateSnapshot,
        action: Action,
        history: &[GameStateSnapshot],
    ) -> GameStateSnapshot {
        // Memory-safety guard: even on the "unchecked" apply path the
        // caller may have supplied an out-of-range `from_node` or
        // `to_node` (see FRB `tgf_kernel_apply_unchecked`).  Reject such
        // actions up-front by returning the input snapshot unchanged so
        // we never index `state.board[..]` out of bounds.  Game-level
        // legality (mill formation, side-to-move, phase, capture
        // policies, …) is still the caller's responsibility — the
        // `*_unchecked` contract is "skip the slow legal-action lookup",
        // not "open up a memory-safety hole".
        if !is_action_within_board_bounds(&action) {
            return *snap;
        }
        // FRB / kernel single-move boundary: decode the POD snapshot, run
        // the in-place rule mutation, then re-encode.  The search hot path
        // bypasses this round-trip via `MillWorkbench::do_move`, which calls
        // `apply_to_state` directly on its owned `MillState`.
        let mut state = Self::decode(snap);
        self.hydrate_repetition_history_from_snapshots(&mut state, snap, history);
        // Real-play boundary: adjudicate threefold so the game actually ends in
        // a draw at the third occurrence (master's external `has_game_cycle`).
        self.apply_to_state(&mut state, action, true);
        self.encode(state)
    }

    fn outcome(&self, snap: &GameStateSnapshot) -> Outcome {
        let state = Self::decode(snap);
        if state.phase == MillPhase::GameOver {
            if state.winner == 2 {
                return Outcome {
                    kind: OutcomeKind::Draw,
                    reason: match state.outcome_reason {
                        MillOutcomeReason::DrawFullBoard => "drawFullBoard",
                        // Legacy value kept for deserialized snapshots.
                        MillOutcomeReason::DrawNMoveRule => "drawFiftyMove",
                        MillOutcomeReason::DrawFiftyMove => "drawFiftyMove",
                        MillOutcomeReason::DrawEndgameFiftyMove => "drawEndgameFiftyMove",
                        MillOutcomeReason::DrawThreefold => "drawThreefoldRepetition",
                        MillOutcomeReason::DrawStalemate => "drawStalemateCondition",
                        _ => "draw",
                    }
                    .to_owned(),
                };
            }
            Outcome {
                kind: OutcomeKind::Win(state.winner),
                reason: match state.outcome_reason {
                    MillOutcomeReason::LoseFullBoard => "loseFullBoard",
                    MillOutcomeReason::LoseFewerThanThree => "loseFewerThanThree",
                    MillOutcomeReason::LoseNoLegalMoves => "loseNoLegalMoves",
                    _ => "loseFewerThanThree",
                }
                .to_owned(),
            }
        } else {
            Outcome {
                kind: OutcomeKind::Ongoing,
                reason: "ongoing".to_owned(),
            }
        }
    }
}

impl MillRules {
    /// In-place core of [`GameRules::apply`].
    ///
    /// Applies `action` by mutating `state_out` directly, skipping the
    /// `encode`/`decode` snapshot round-trip that the trait boundary needs
    /// for the FRB / kernel single-move path.  The search hot path
    /// ([`MillWorkbench::do_move`]) calls this once per tree edge.  The
    /// caller is responsible for refreshing the cached `zobrist_key`
    /// afterwards (the trait `apply` does so via `encode`; `do_move` calls
    /// `recompute_zobrist`).  Out-of-range actions are a no-op.
    pub(super) fn apply_to_state(
        &self,
        state_out: &mut MillState,
        action: Action,
        adjudicate_repetition: bool,
    ) {
        if !is_action_within_board_bounds(&action) {
            return;
        }
        // Move the owned state out (leaving a non-allocating `Default`) so
        // the rule logic below operates on a local `state` value verbatim,
        // then move it back.  No clone, no heap traffic.
        let mut state = std::mem::take(state_out);
        // Capture the pre-apply Zobrist inputs so the post-apply key can be
        // refreshed incrementally (avoids the full 24-square scan per node).
        let old_key = state.zobrist_key;
        let old_zobrist = super::zobrist::ZobristInputs::capture(&state);
        match action.kind_tag {
            x if x == MillActionKind::Place as i16 => {
                let to = action.to_node as usize;
                debug_assert!(state.board[to] == 0);
                let side = state.side_to_move as usize;
                state.board[to] = state.side_to_move + 1;
                state.pieces_in_hand[side] = state.pieces_in_hand[side].saturating_sub(1);
                state.pieces_on_board[side] += 1;
                state.move_number += 1;
                state.ply_since_capture = 0;
                // Placing a new piece is irreversible: any rolling
                // repetition history accumulated in the moving phase
                // becomes irrelevant.
                clear_key_history(&mut state);
                let custodian = detect_custodian_targets(&state, &self.options, to);
                let intervention = detect_intervention_targets(&state, &self.options, to);
                let mill_bits = formed_mill_bits_at(&state, &self.options, to, state.side_to_move);
                let usable_bits = usable_mill_bits(&state, &self.options, mill_bits);
                if usable_bits != 0 {
                    let removals = removal_count_for_bits(usable_bits, &self.options);
                    match self.options.mill_formation_action_in_placing_phase {
                        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
                        | MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn => {
                            let opponent = side ^ 1;
                            let hand_removed = removals.min(state.pieces_in_hand[opponent]);
                            state.pieces_in_hand[opponent] -= hand_removed;
                            let remaining = removals - hand_removed;
                            if remaining > 0 {
                                state.pending_removals[side] = remaining;
                                state.mill_available_at_removal = true;
                                sync_action_state(&mut state);
                            } else {
                                state.side_to_move = if matches!(
                                    self.options.mill_formation_action_in_placing_phase,
                                    MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
                                ) {
                                    (side ^ 1) as i8
                                } else {
                                    side as i8
                                };
                                maybe_transition_to_moving(&mut state, &self.options);
                                sync_phase_with_active_hand(&mut state);
                                maybe_finish_full_board(&mut state, &self.options);
                                sync_action_state(&mut state);
                            }
                            clear_capture_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::OpponentRemovesOwnPiece => {
                            let opponent = side ^ 1;
                            state.side_to_move = opponent as i8;
                            state.pending_removals[opponent] = removals;
                            state.mill_available_at_removal = false;
                            clear_capture_state(&mut state);
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces => {
                            // Same shape as the standard "remove opponent's
                            // piece from board" branch: pending_removals is
                            // armed and the opponent waits until the active
                            // side picks a target.  The Remove handler then
                            // diverts to marking instead of physical removal,
                            // and `maybe_transition_to_moving` sweeps every
                            // marked square at the placing-to-moving boundary
                            // (mirrors Position::remove_marked_pieces).
                            state.pending_removals[side] = removals;
                            state.mill_available_at_removal = true;
                            activate_capture_state(&mut state, custodian, intervention, 0);
                            if self.options.may_remove_multiple {
                                state.pending_removals[side] = state.pending_removals[side]
                                    .saturating_add(capture_total(&state));
                            }
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts => {
                            clear_capture_state(&mut state);
                            if state.pieces_in_hand[0] == 0 && state.pieces_in_hand[1] == 0 {
                                apply_removal_based_on_mill_counts(&mut state, &self.options);
                            } else {
                                state.side_to_move ^= 1;
                            }
                            maybe_transition_to_moving(&mut state, &self.options);
                            sync_phase_with_active_hand(&mut state);
                            maybe_finish_full_board(&mut state, &self.options);
                            sync_action_state(&mut state);
                        }
                        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromBoard => {
                            state.pending_removals[side] = removals;
                            state.mill_available_at_removal = true;
                            activate_capture_state(&mut state, custodian, intervention, 0);
                            if self.options.may_remove_multiple {
                                state.pending_removals[side] =
                                    state.pending_removals[side].saturating_add(capture_total(&state));
                            }
                            sync_action_state(&mut state);
                        }
                    }
                    note_mill_formation(&mut state, side, -1, to as i8, usable_bits, &self.options);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else {
                    clear_capture_state(&mut state);
                    // Mirror master src/position.cpp:1217 put_piece:
                    // StopPlacingWhenTwoEmptySquares is checked only after
                    // the no-mill/no-capture placing path has been selected.
                    // Mill formation and capture obligations must keep the
                    // remaining hand counts intact until their removal flow
                    // completes.
                    maybe_stop_placing_when_two_empty(&mut state, &self.options);
                    state.side_to_move ^= 1;
                    maybe_transition_to_moving(&mut state, &self.options);
                    sync_phase_with_active_hand(&mut state);
                    maybe_finish_full_board(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            x if x == MillActionKind::Move as i16 => {
                let from = action.from_node as usize;
                let to = action.to_node as usize;
                debug_assert_eq!(state.board[from], state.side_to_move + 1);
                debug_assert_eq!(state.board[to], 0);
                state.board[from] = 0;
                state.board[to] = state.side_to_move + 1;
                state.move_number += 1;
                let side = state.side_to_move as usize;
                bump_ply_since_capture(&mut state, &self.options);
                let custodian = detect_custodian_targets(&state, &self.options, to);
                let intervention = detect_intervention_targets(&state, &self.options, to);
                let leap = detect_leap_targets(&state, &self.options, from, to);
                let mill_bits = formed_mill_bits_at(&state, &self.options, to, state.side_to_move);
                let usable_bits = usable_mill_bits(&state, &self.options, mill_bits);
                if leap != 0 {
                    activate_capture_state(&mut state, 0, 0, leap);
                    state.pending_removals[side] = 1;
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else if usable_bits != 0 {
                    state.pending_removals[side] =
                        removal_count_for_bits(usable_bits, &self.options);
                    state.mill_available_at_removal = true;
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    if self.options.may_remove_multiple {
                        state.pending_removals[side] =
                            state.pending_removals[side].saturating_add(capture_total(&state));
                    }
                    note_mill_formation(
                        &mut state,
                        side,
                        from as i8,
                        to as i8,
                        usable_bits,
                        &self.options,
                    );
                    sync_action_state(&mut state);
                } else if custodian != 0 || intervention != 0 {
                    activate_capture_state(&mut state, custodian, intervention, 0);
                    state.pending_removals[side] = capture_total(&state);
                    state.mill_available_at_removal = false;
                    sync_action_state(&mut state);
                } else {
                    clear_capture_state(&mut state);
                    // Clear the per-side last-mill record when no mill was
                    // formed.  Mirrors C++ position.cpp's
                    // `lastMillFromSquare[c] = SQ_NONE` / `lastMillToSquare[c] = SQ_NONE`
                    // in the non-mill branch of do_move().  Without this clear,
                    // `restrict_repeated_mills_formation` incorrectly blocks a
                    // later re-formation of the same mill even after the mover
                    // has made an intermediate non-mill move.
                    state.last_mill_from[side] = -1;
                    state.last_mill_to[side] = -1;
                    state.side_to_move ^= 1;
                    // Record this side-changing reversible move into the
                    // repetition history *before* deciding whether the
                    // n-move rule fires; threefold takes precedence and
                    // sets GameOver itself, after which the n-move check
                    // becomes a no-op (it inspects `state.phase`).
                    push_key_and_check_threefold(&mut state, &self.options, adjudicate_repetition);
                    maybe_draw_by_n_move_rule(&mut state, &self.options, adjudicate_repetition);
                    // Mirror C++ set_side_to_move: phase follows the new
                    // active side's hand count (matters for Dooz-style
                    // asymmetric hands and may_move_in_placing_phase).
                    sync_phase_with_active_hand(&mut state);
                    sync_action_state(&mut state);
                }
            }
            x if x == MillActionKind::Remove as i16 => {
                let to = action.to_node as usize;
                let side = state.side_to_move as usize;
                let opponent = (state.side_to_move ^ 1) as usize;
                let removing_own = side < 2 && state.remove_own_piece[side];
                let target_color_index = if removing_own { side } else { opponent };
                debug_assert_eq!(state.board[to], target_color_index as i8 + 1);
                debug_assert!(state.pending_removals[side] > 0);
                let mask = node_bit(to);
                let is_custodian =
                    (state.custodian_targets[side] & mask) != 0 && state.custodian_count[side] > 0;
                let is_intervention = (state.intervention_targets[side] & mask) != 0
                    && state.intervention_count[side] > 0;
                let is_leap = (state.leap_targets[side] & mask) != 0 && state.leap_count[side] > 0;
                let cap_total = capture_total(&state);
                let remaining_before = state.pending_removals[side];

                if is_intervention {
                    state.mill_available_at_removal = false;
                    state.custodian_targets[side] = 0;
                    state.custodian_count[side] = 0;
                    state.leap_targets[side] = 0;
                    state.leap_count[side] = 0;
                    state.pending_removals[side] = state.intervention_count[side];
                } else if is_custodian {
                    state.mill_available_at_removal = false;
                    state.intervention_targets[side] = 0;
                    state.intervention_count[side] = 0;
                    state.leap_targets[side] = 0;
                    state.leap_count[side] = 0;
                    state.pending_removals[side] = 1;
                } else if is_leap {
                    state.mill_available_at_removal = false;
                    state.custodian_targets[side] = 0;
                    state.custodian_count[side] = 0;
                    state.intervention_targets[side] = 0;
                    state.intervention_count[side] = 0;
                    state.pending_removals[side] = 1;
                } else if state.mill_available_at_removal && cap_total > 0 {
                    if self.options.may_remove_multiple && remaining_before > cap_total {
                        state.pending_removals[side] = remaining_before.saturating_sub(cap_total);
                    }
                    clear_capture_state_for_side(&mut state, side);
                    state.mill_available_at_removal = true;
                } else {
                    debug_assert!(
                        cap_total == 0 || state.mill_available_at_removal,
                        "capture obligation must remove a capture target"
                    );
                }

                let mark_pending = matches!(
                    self.options.mill_formation_action_in_placing_phase,
                    MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
                ) && state.phase == MillPhase::Placing
                    && !removing_own;
                if mark_pending {
                    // Preserve the original colour in `state.board` so that
                    // the UI can render the X overlay; flag the square in
                    // `delayed_marked_pieces` so every rule predicate
                    // (`live_piece`, `is_marked`) treats the cell as empty
                    // until the placing-to-moving sweep clears it.
                    state.delayed_marked_pieces |= mask;
                } else {
                    state.board[to] = 0;
                }
                state.pieces_on_board[target_color_index] =
                    state.pieces_on_board[target_color_index].saturating_sub(1);
                state.pending_removals[side] = state.pending_removals[side].saturating_sub(1);
                if is_custodian {
                    state.custodian_targets[side] &= !mask;
                    state.custodian_count[side] = state.custodian_count[side].saturating_sub(1);
                    if state.custodian_count[side] == 0 {
                        state.custodian_targets[side] = 0;
                    }
                }
                if is_intervention {
                    state.intervention_targets[side] &= !mask;
                    state.intervention_count[side] =
                        state.intervention_count[side].saturating_sub(1);
                    if state.intervention_count[side] == 0 {
                        state.intervention_targets[side] = 0;
                    } else {
                        state.intervention_targets[side] = find_paired_intervention_target(
                            to,
                            state.intervention_targets[side] | mask,
                            &self.options,
                        );
                    }
                }
                if is_leap {
                    state.leap_targets[side] &= !mask;
                    state.leap_count[side] = state.leap_count[side].saturating_sub(1);
                    if state.leap_count[side] == 0 {
                        state.leap_targets[side] = 0;
                    }
                }
                state.ply_since_capture = 0;
                // Capturing changes material — restart the rolling
                // repetition window.
                clear_key_history(&mut state);
                // P0-B.1: Mirror master remove_piece L1834-1838 which checks
                // `pieceOnBoardCount[them] + pieceInHandCount[them] < piecesAtLeastCount`
                // WITHOUT a phase guard and WITHOUT requiring empty hands.
                // A side whose board + hand total has dropped below
                // `pieces_at_least_count` can never reach the minimum piece
                // count again, so the loss is declared immediately even in
                // the placing phase (e.g. repeated captures while the victim
                // still holds pieces in hand).  An earlier revision gated
                // this on `pieces_in_hand == [0, 0]`, which deferred the
                // loss; since this is the only fewer-than-three check on the
                // apply path, a doomed position could then drag on into the
                // moving phase and even reach an n-move-rule draw.
                let pieces_total = u32::from(state.pieces_on_board[target_color_index])
                    + u32::from(state.pieces_in_hand[target_color_index]);
                if pieces_total < u32::from(self.options.pieces_at_least_count) {
                    state.phase = MillPhase::GameOver;
                    state.winner = if removing_own {
                        opponent as i8
                    } else {
                        state.side_to_move
                    };
                    state.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
                    state.side_to_move = -1;
                } else if state.pending_removals[side] == 0 {
                    clear_capture_state_for_side(&mut state, side);
                    if removing_own {
                        // Negative pieceToRemoveCount cleared its quota; flip
                        // the flag so the next removal (if scheduled) reverts
                        // to opponent-targeting semantics.
                        state.remove_own_piece[side] = false;
                    }
                    if state.stalemate_removing {
                        state.stalemate_removing = false;
                    } else {
                        state.side_to_move ^= 1;
                    }
                    if state.both_stalemate_removing && state.pending_removals == [0, 0] {
                        state.both_stalemate_removing = false;
                    }
                    if state.board_full_removing && state.pending_removals == [0, 0] {
                        state.board_full_removing = false;
                    }
                    maybe_transition_to_moving(&mut state, &self.options);
                    sync_phase_with_active_hand(&mut state);
                    maybe_finish_full_board(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            _ => {}
        }
        self.maybe_handle_stalemate(&mut state);
        state.key_history_len = state.key_history.len();
        // Refresh the cached Zobrist key incrementally from the pre-apply
        // inputs, skipping the full board scan.  `old_key == 0` only on a
        // hand-built state that bypassed encode/decode (no known baseline);
        // fall back to a full recompute there.  The debug_assert validates
        // the incremental result against the authoritative full recompute on
        // every apply in debug / test builds.
        if old_key == 0 {
            recompute_zobrist(&mut state);
        } else {
            state.zobrist_key = super::zobrist::key_after_apply(
                old_key,
                &old_zobrist,
                &state,
                action.from_node,
                action.to_node,
            );
        }
        debug_assert_eq!(
            state.zobrist_key,
            super::zobrist::full_state_key(&state),
            "incremental Zobrist key diverged from full_state_key",
        );
        *state_out = state;
    }
}
