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
        let mut state = Self::decode(snap);
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
                                sync_phase_for_may_move_in_placing(&mut state, &self.options);
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
                            sync_phase_for_may_move_in_placing(&mut state, &self.options);
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
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
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
                    push_key_and_check_threefold(&mut state, &self.options);
                    maybe_draw_by_n_move_rule(&mut state, &self.options);
                    // Mirror C++ set_side_to_move phase sync for
                    // may_move_in_placing_phase variant.
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
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
                // WITHOUT a phase guard. The original Rust code only checked
                // in Moving phase and omitted in-hand count; both are fixed here.
                let pieces_total = u32::from(state.pieces_on_board[target_color_index])
                    + u32::from(state.pieces_in_hand[target_color_index]);
                if state.pieces_in_hand == [0, 0]
                    && pieces_total < u32::from(self.options.pieces_at_least_count)
                {
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
                    sync_phase_for_may_move_in_placing(&mut state, &self.options);
                    maybe_finish_full_board(&mut state, &self.options);
                    sync_action_state(&mut state);
                }
            }
            _ => {}
        }
        self.maybe_handle_stalemate(&mut state);
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
    pub(super) fn legal_actions_ctx(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        ctx: &tgf_core::MoveOrderContext,
    ) {
        let priority = move_priority_list_for_search(&self.options, ctx);
        match state.action_for_legal_generation() {
            MillActionState::Remove => {
                if state.pending_removals[state.side_to_move as usize] > 0 {
                    self.generate_remove_actions(state, out, &priority);
                }
            }
            MillActionState::Place => {
                if state.pieces_in_hand[state.side_to_move as usize] > 0 {
                    for &node in &priority {
                        if state.board[node] == 0 {
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
                    self.generate_move_actions_with_priority(state, out, false, &priority);
                }
            }
            MillActionState::Select => {
                if state.phase == MillPhase::Moving {
                    self.generate_move_actions_with_priority(state, out, true, &priority);
                }
            }
            MillActionState::GameOver => {}
        }
    }

    fn has_legal_move(&self, state: &MillState) -> bool {
        if state.phase != MillPhase::Moving {
            return true;
        }
        let mut actions = ActionList::<256>::new();
        self.generate_move_actions(state, &mut actions, true);
        !actions.is_empty()
    }

    pub(super) fn maybe_handle_stalemate(&self, state: &mut MillState) {
        if state.phase != MillPhase::Moving
            || state.side_to_move < 0
            || state.pending_removals[state.side_to_move as usize] != 0
            || self.has_legal_move(state)
        {
            return;
        }

        match self.options.stalemate_action {
            StalemateAction::EndWithStalemateLoss => {
                state.phase = MillPhase::GameOver;
                state.winner = state.side_to_move ^ 1;
                state.outcome_reason = MillOutcomeReason::LoseNoLegalMoves;
                state.side_to_move = -1;
            }
            StalemateAction::ChangeSideToMove => {
                state.side_to_move ^= 1;
            }
            StalemateAction::RemoveOpponentsPieceAndMakeNextMove => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.stalemate_removing = true;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
            StalemateAction::RemoveOpponentsPieceAndChangeSideToMove => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
            StalemateAction::EndWithStalemateDraw => {
                state.phase = MillPhase::GameOver;
                state.winner = 2;
                state.outcome_reason = MillOutcomeReason::DrawStalemate;
                state.side_to_move = -1;
            }
            StalemateAction::BothPlayersRemoveOpponentsPiece => {
                let side = state.side_to_move as usize;
                state.pending_removals[side] = 1;
                state.pending_removals[side ^ 1] = 1;
                state.both_stalemate_removing = true;
                state.mill_available_at_removal = false;
                clear_capture_state(state);
            }
        }
    }

    pub(super) fn check_if_game_is_over(&self, state: &mut MillState) {
        if state.phase == MillPhase::GameOver || state.side_to_move < 0 {
            return;
        }
        // Mirror master src/position.cpp:2069 Position::check_if_game_is_over:
        // terminal conditions are evaluated after FEN import just as they are
        // after normal moves.
        maybe_finish_full_board(state, &self.options);
        if state.phase == MillPhase::GameOver {
            return;
        }
        maybe_draw_by_n_move_rule(state, &self.options);
        if state.phase == MillPhase::GameOver {
            return;
        }
        if state.phase == MillPhase::Moving {
            for side in 0..2 {
                let pieces_total =
                    u32::from(state.pieces_on_board[side]) + u32::from(state.pieces_in_hand[side]);
                if pieces_total < u32::from(self.options.pieces_at_least_count) {
                    state.phase = MillPhase::GameOver;
                    state.winner = (side ^ 1) as i8;
                    state.outcome_reason = MillOutcomeReason::LoseFewerThanThree;
                    state.side_to_move = -1;
                    return;
                }
            }
        }
        self.maybe_handle_stalemate(state);
    }

    fn generate_move_actions(&self, state: &MillState, out: &mut ActionList<256>, allow_fly: bool) {
        let priority = default_dense_priority();
        self.generate_move_actions_with_priority(state, out, allow_fly, &priority);
    }

    fn generate_move_actions_with_priority(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        allow_fly: bool,
        priority: &[usize; 24],
    ) {
        let side = state.side_to_move as usize;
        // Mirror master src/movegen.cpp:87 generate<MOVE> and
        // src/movegen.cpp:157 generate<LEGAL>: movement, including
        // Lasker-style leap and fly moves, is only generated when the active
        // side has no pieces left in hand.
        let no_pieces_in_hand = state.pieces_in_hand[side] == 0;
        let can_fly = allow_fly
            && self.options.may_fly
            && no_pieces_in_hand
            && state.pieces_on_board[side] <= self.options.fly_piece_count;
        let opponent_color = (state.side_to_move ^ 1) + 1;
        // Leap moves are emitted *in addition to* regular adjacency moves
        // (mirrors master generate<MOVE>'s `tryAddLeap` superset).  They
        // require leap_capture.enabled, the active phase to be allowed,
        // and — when in placing — that may_move_in_placing_phase opens
        // movement.  In fly state, every empty square is already
        // reachable so the leap superset is redundant.
        // Use capture_piece_count_allowed_leap (not the generic variant) so that
        // onlyAvailableWhenOwnPiecesLeq3 is enforced in placing phase too,
        // matching master's checkLeapCapture which checks the condition outside
        // any phase guard.
        let leap_enabled = !can_fly
            && no_pieces_in_hand
            && self.options.leap_capture.enabled
            && capture_phase_allowed(&self.options.leap_capture, state.phase)
            && capture_piece_count_allowed_leap(&self.options.leap_capture, state)
            && (state.phase == MillPhase::Moving
                || (state.phase == MillPhase::Placing
                    && self.options.may_move_in_placing_phase
                    && self.options.leap_capture.in_placing_phase));
        for &from in priority.iter().rev() {
            // Use live_piece() rather than the raw board value so that
            // mark-and-delay MARKED_PIECE squares are treated as empty
            // (not movable) — mirrors C++ generate<MOVE>'s byColorBB filter.
            if live_piece(state, from) != state.side_to_move + 1 {
                continue;
            }
            if can_fly {
                for to in 0_usize..24 {
                    if state.board[to] == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                        out.push(move_action(from, to));
                    }
                }
                continue;
            }
            for &to in self.topology.neighbors(from as u16) {
                let to = to as usize;
                if state.board[to] == 0 && !self.is_restricted_repeated_mill(state, from, to) {
                    out.push(move_action(from, to));
                }
            }
            if leap_enabled {
                // For every three-point line with `from` at one end, jumping
                // over an opponent in the middle to the empty far end is a
                // legal leap move.  master generate<MOVE> calls checkLeapCapture
                // which also validates that the captured middle piece is actually
                // removable under mill-protection rules (P0-A.2). We replicate
                // that check here via leap_capture_target_is_removable.
                for line in active_capture_lines(&self.options.leap_capture, &self.options) {
                    let (a, mid, b) = (line[0], line[1], line[2]);
                    let jumps_from_a =
                        from == a && state.board[b] == 0 && state.board[mid] == opponent_color;
                    let jumps_from_b =
                        from == b && state.board[a] == 0 && state.board[mid] == opponent_color;
                    if jumps_from_a {
                        if !self.is_restricted_repeated_mill(state, from, b)
                            && leap_capture_target_is_removable(state, &self.options, mid)
                        {
                            out.push(move_action(from, b));
                        }
                    } else if jumps_from_b
                        && !self.is_restricted_repeated_mill(state, from, a)
                        && leap_capture_target_is_removable(state, &self.options, mid)
                    {
                        out.push(move_action(from, a));
                    }
                }
            }
        }
    }

    fn is_restricted_repeated_mill(&self, state: &MillState, from: usize, to: usize) -> bool {
        if !self.options.restrict_repeated_mills_formation {
            return false;
        }
        // Per-side last-mill tracking, matching C++ position.cpp
        // `lastMillFromSquare[c]` / `lastMillToSquare[c]`.
        let side = state.side_to_move as usize;
        if side >= 2 {
            return false;
        }
        let last_from = state.last_mill_from[side];
        let last_to = state.last_mill_to[side];
        if last_from < 0 || last_to < 0 {
            return false;
        }
        if from != last_to as usize || to != last_from as usize {
            return false;
        }
        // Mirror master src/position.cpp:1068 / potential_mills_count:
        // restrict only when `from` currently counts as a usable mill and
        // moving back to `to` would form another usable mill.  Under
        // oneTimeUseMill, potential_mills_count filters out lines already
        // recorded in formedMillsBB, so an already consumed mill must not
        // keep the reverse move restricted.
        if potential_mills_count_at(state, &self.options, from, state.side_to_move, None) == 0 {
            return false;
        }
        potential_mills_count_at(state, &self.options, to, state.side_to_move, Some(from)) > 0
    }

    fn generate_remove_actions(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        priority: &[usize; 24],
    ) {
        let us = state.side_to_move as usize;
        let capture_targets = if us < 2 {
            state.custodian_targets[us] | state.intervention_targets[us] | state.leap_targets[us]
        } else {
            0
        };
        if capture_targets != 0 {
            self.generate_capture_remove_actions(state, out, capture_targets);
            // Mirror master generate<REMOVE>'s `totalRemovals <= captureCount`
            // cutoff (P0-A.1): when pending removals are fully covered by
            // capture obligations, only capture targets are legal this turn.
            if us >= 2 || state.pending_removals[us] <= capture_total(state) {
                return;
            }
            // pending_removals[us] > capture_total: the current player formed
            // a mill simultaneously with a capture, so also generate the
            // regular mill-remove targets below (excluding capture targets
            // already emitted above).
        }

        if us < 2 && state.remove_own_piece[us] {
            // Mirror master src/position.cpp:1773 remove_piece:
            // negative pieceToRemoveCount switches the target colour to the
            // mover's own pieces, then the common stalemate and mill
            // protection filters at lines 1793-1801 still run.
            self.generate_regular_remove_actions_for_piece(
                state,
                out,
                state.side_to_move + 1,
                0,
                priority,
            );
            return;
        }

        let opponent_piece = (state.side_to_move ^ 1) + 1;
        self.generate_regular_remove_actions_for_piece(
            state,
            out,
            opponent_piece,
            capture_targets,
            priority,
        );
    }

    fn generate_regular_remove_actions_for_piece(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        target_piece: i8,
        excluded_targets: u32,
        priority: &[usize; 24],
    ) {
        // When `may_remove_from_mills_always` is set the rule simplifies:
        // every target-colour piece is legal, regardless of whether
        // it sits in a mill.  Otherwise we mirror the C++ default (and
        // the FIDE Mill rule): mill pieces can only be removed when no
        // non-mill alternative exists.  Capture targets already emitted
        // above are skipped to avoid duplicate Remove actions, mirroring
        // master generate<REMOVE>'s `if (combinedTargets & square_bb(s)) continue;`.
        // Marked pieces are filtered out via `live_piece` to mirror
        // legacy `removeColorPiece` matching against `byColorBB[c]`,
        // which excludes MARKED_PIECE squares.
        let has_non_mill_target = (0_usize..24).any(|idx| {
            live_piece(state, idx) == target_piece && !is_piece_in_mill(state, &self.options, idx)
        });

        for &node in priority.iter().rev() {
            if live_piece(state, node) != target_piece {
                continue;
            }
            if (excluded_targets & node_bit(node)) != 0 {
                continue;
            }
            if self.is_stalemate_removal_context(state)
                && !is_adjacent_to_side_piece(state, &self.topology, node)
            {
                continue;
            }
            if !self.options.may_remove_from_mills_always
                && has_non_mill_target
                && is_piece_in_mill(state, &self.options, node)
            {
                continue;
            }
            out.push(Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: node as i16,
                aux: -1,
                payload_bits: 0,
            });
        }
    }

    fn generate_capture_remove_actions(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        targets: u32,
    ) {
        let opponent_piece = (state.side_to_move ^ 1) + 1;
        for node in 0..24_usize {
            if (targets & node_bit(node)) == 0 || state.board[node] != opponent_piece {
                continue;
            }
            out.push(Action {
                kind_tag: MillActionKind::Remove as i16,
                from_node: -1,
                to_node: node as i16,
                aux: -1,
                payload_bits: 0,
            });
        }
    }

    fn is_stalemate_removal_context(&self, state: &MillState) -> bool {
        if state.stalemate_removing || state.both_stalemate_removing {
            return true;
        }
        // Mirror master src/position.cpp:3475 is_board_full_removal_at_placing_phase_end:
        // the board-full branch is only a placing-phase predicate. Rust arms
        // the removals after transitioning to Moving, so board_full_removing
        // is persisted only as UI/FEN metadata and never enables stalemate
        // adjacency filtering.
        matches!(
            self.options.stalemate_action,
            StalemateAction::RemoveOpponentsPieceAndMakeNextMove
                | StalemateAction::RemoveOpponentsPieceAndChangeSideToMove
                | StalemateAction::BothPlayersRemoveOpponentsPiece
        ) && state.phase == MillPhase::Moving
            && state.side_to_move >= 0
            && state.pending_removals[state.side_to_move as usize] > 0
            && !self.has_legal_move(state)
    }
}
