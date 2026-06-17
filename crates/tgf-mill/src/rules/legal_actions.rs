// SPDX-License-Identifier: GPL-3.0-or-later
// Mill move generation and the supporting helpers consumed by
// `crate::rules::legal_apply::apply`:
//
//   * `legal_actions_ctx`        — context-aware move ordering driven
//                                  by the search's MoveOrderContext.
//   * `has_legal_move` / `maybe_handle_stalemate` /
//     `check_if_game_is_over` — phase-transition helpers that decide
//                                  whether a position is terminal.
//   * `generate_*_actions`       — kind-specific generators (move, remove,
//                                  capture-only-remove, regular remove).
//   * `is_restricted_repeated_mill` — `restrict_repeated_mills_formation`
//                                  filter applied during move generation.
//
// The companion `mod.rs` exposes every collaborator (state field,
// transition helper, capture detector, …) as `pub(super)` so this file
// can `use super::*` and stay close to the original layout.

use super::*;

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

    pub(super) fn has_legal_move(&self, state: &MillState) -> bool {
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
                // C++ runs change_side_to_move() -> set_side_to_move(),
                // which re-derives the phase from the new active side's
                // hand count.
                state.side_to_move ^= 1;
                sync_phase_with_active_hand(state);
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
        // Mirror the tail of master Position::check_if_game_is_over
        // (position.cpp): `if (pieceToRemoveCount[sideToMove] != 0)
        // action = Action::remove;`.  Without this resync the action
        // stays at Select after a stalemate arms pending removals, and
        // move generation would return an empty list instead of the
        // removal targets.
        sync_action_state(state);
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
        maybe_draw_by_n_move_rule(state, &self.options, true);
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

    pub(super) fn generate_move_actions(
        &self,
        state: &MillState,
        out: &mut ActionList<256>,
        allow_fly: bool,
    ) {
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

    pub(super) fn generate_remove_actions(
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
        // Mirror master generate<REMOVE>'s branch structure: the
        // stalemate-removal path applies ONLY the "adjacent to the
        // remover's pieces" filter (own-colour targets are unrestricted)
        // and returns before any mill-protection check, so a piece
        // sitting in a mill is still removable during a stalemate
        // removal.  Mill protection applies exclusively to the regular
        // (non-stalemate) path.
        let stalemate_removal = self.is_stalemate_removal_context(state);
        let removing_own = state.side_to_move >= 0 && target_piece == state.side_to_move + 1;

        for &node in priority.iter().rev() {
            if live_piece(state, node) != target_piece {
                continue;
            }
            if (excluded_targets & node_bit(node)) != 0 {
                continue;
            }
            if stalemate_removal {
                if !removing_own && !is_adjacent_to_side_piece(state, &self.topology, node) {
                    continue;
                }
            } else if !self.options.may_remove_from_mills_always
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
