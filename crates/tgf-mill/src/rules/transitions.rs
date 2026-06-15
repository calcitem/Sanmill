// SPDX-License-Identifier: GPL-3.0-or-later
// Phase transitions, repetition / fifty-move bookkeeping, and the
// supporting "is the action in board bounds" guard that protect the
// FRB `apply_unchecked` path.

use tgf_core::Action;

use super::{
    MillBoardFullAction, MillFormationActionInPlacingPhase, MillOutcomeReason, MillPhase,
    MillState, MillVariantOptions, mill_lines, node_bit,
};

/// and this helper is not called, so the placing-phase indicator stays
/// correct until the obligated remove resolves.
pub(super) fn maybe_transition_to_moving(state: &mut MillState, options: &MillVariantOptions) {
    if state.phase == MillPhase::Placing
        && state.pieces_in_hand[0] == 0
        && state.pieces_in_hand[1] == 0
    {
        enter_moving_phase(state, options);
    }
    if options.piece_count == 12
        && options.stop_placing_when_two_empty_squares
        && state.phase == MillPhase::Placing
        && empty_square_count(state) <= 2
    {
        state.pieces_in_hand = [0, 0];
        enter_moving_phase(state, options);
    }
}

/// The C++ engine determines the effective phase from the **active
/// player's** hand count on every side switch, for every variant (see
/// `Position::set_side_to_move` in legacy position.cpp):
///
/// ```cpp
/// if (pieceInHandCount[sideToMove] == 0) { phase = moving;  ... }
/// else                                   { phase = placing; ... }
/// ```
///
/// For most variants both hands deplete in lockstep, so this is a no-op
/// until the regular placing-end transition fires.  It becomes
/// observable whenever hand counts diverge:
///   * `may_move_in_placing_phase` (Lasker Morris): a player who has
///     placed all pieces starts moving while the opponent still places.
///   * `RemoveOpponentsPieceFromHandThenOpponentsTurn` (Dooz): a mill
///     removes a piece from the opponent's hand, so the opponent can run
///     out of hand pieces early and must answer with board moves.
///
/// Call this after every side change in `apply()`.  Only the
/// Placing/Moving pair is touched — terminal phases stay intact, and the
/// placing-end bookkeeping (marked-piece sweep, defender-first seat
/// assignment) still happens exclusively in `enter_moving_phase` once
/// both hands are empty.
pub(super) fn sync_phase_with_active_hand(state: &mut MillState) {
    // Only adjust when the game is still in progress (placing or moving).
    if state.phase != MillPhase::Placing && state.phase != MillPhase::Moving {
        return;
    }
    let active = state.side_to_move as usize;
    if active <= 1 {
        state.phase = if state.pieces_in_hand[active] == 0 {
            MillPhase::Moving
        } else {
            MillPhase::Placing
        };
    }
}

pub(super) fn enter_moving_phase(state: &mut MillState, options: &MillVariantOptions) {
    state.phase = MillPhase::Moving;
    // Mirrors Position::remove_marked_pieces in legacy position.cpp: at
    // the placing-to-moving boundary every "X"-marked square sweeps to
    // empty.  Only meaningful for MarkAndDelayRemovingPieces but cheap
    // enough to run unconditionally — the bitset is already 0 elsewhere.
    if state.delayed_marked_pieces != 0 {
        for node in 0_usize..24 {
            if (state.delayed_marked_pieces & node_bit(node)) != 0 {
                state.board[node] = 0;
            }
        }
        state.delayed_marked_pieces = 0;
    }
    // Mirror handle_placing_phase_end side-to-move logic from master
    // position.cpp.  The "invariant" branch (lasker / your-turn-with-
    // multiple / opponents-turn) keeps the active side intact unless
    // isDefenderMoveFirst forces it to BLACK; every other path
    // unconditionally hands control to the rule-defined first mover.
    let invariant = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn
    ) || (matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenYourTurn
    ) && options.may_remove_multiple)
        || options.may_move_in_placing_phase;
    let mark_and_delay = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces
    );
    let removal_mill_counts = matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
    );
    if invariant && !mark_and_delay && !removal_mill_counts {
        // Master returns early after `if (isDefenderMoveFirst) set_side_to_move(BLACK)`,
        // leaving the caller to skip the default change_side_to_move when
        // !isDefenderMoveFirst.  We have already toggled side_to_move in
        // the apply() prelude, so leaving it untouched preserves the
        // caller's "no further change" intent.
        if options.is_defender_move_first {
            state.side_to_move = 1;
        }
    } else {
        // Default branch + markAndDelay + removalBasedOnMillCounts all
        // funnel through master `set_side_to_move(defender ? BLACK : WHITE)`.
        state.side_to_move = if options.is_defender_move_first { 1 } else { 0 };
    }
    if matches!(
        options.mill_formation_action_in_placing_phase,
        MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
    ) {
        apply_removal_based_on_mill_counts(state, options);
    }
}

pub(super) fn maybe_stop_placing_when_two_empty(
    state: &mut MillState,
    options: &MillVariantOptions,
) {
    if options.piece_count == 12
        && options.stop_placing_when_two_empty_squares
        && empty_square_count(state) <= 2
    {
        state.pieces_in_hand = [0, 0];
    }
}

pub(super) fn empty_square_count(state: &MillState) -> usize {
    state.board.iter().filter(|piece| **piece == 0).count()
}

/// Memory-safety check for FRB callers (in particular
/// `tgf_kernel_apply_unchecked`) that bypass `is_legal` but must not be
/// allowed to crash the engine with an out-of-range board index.
///
/// The 24-node Mill board uses `0..24` for real squares and `-1` as the
/// sentinel "no node" value (placing from hand, removal-only, etc.).
/// Accept Place / Move / Remove kinds whose source / destination fields
/// fall in those ranges; reject everything else so callers can recover
/// instead of triggering a panic deep inside `apply`.
#[inline]
pub(super) fn is_action_within_board_bounds(action: &Action) -> bool {
    fn is_node_or_none(value: i16) -> bool {
        value == -1 || (0..24).contains(&value)
    }
    is_node_or_none(action.from_node) && is_node_or_none(action.to_node)
}

pub(super) fn maybe_finish_full_board(state: &mut MillState, options: &MillVariantOptions) {
    // Mirror Position::handle_placing_phase_end / is_board_full_removal_at_placing_phase_end:
    // the boardFullAction switch only fires for the 12-piece variant.  In
    // 9-piece games 9+9=18<24 means the board cannot fill, and the 24-cell
    // 12-piece variant is the only one master Position checks.
    if options.piece_count != 12 {
        return;
    }
    if state.phase != MillPhase::Moving || empty_square_count(state) != 0 {
        return;
    }
    if state.pending_removals.iter().any(|count| *count > 0) {
        return;
    }
    match options.board_full_action {
        MillBoardFullAction::FirstPlayerLose => {
            state.phase = MillPhase::GameOver;
            state.winner = 1;
            state.outcome_reason = MillOutcomeReason::LoseFullBoard;
            state.side_to_move = -1;
        }
        MillBoardFullAction::AgreeToDraw => {
            state.phase = MillPhase::GameOver;
            state.winner = 2;
            state.outcome_reason = MillOutcomeReason::DrawFullBoard;
            state.side_to_move = -1;
        }
        MillBoardFullAction::FirstAndSecondPlayerRemovePiece => {
            state.pending_removals = [1, 1];
            state.side_to_move = 0;
            state.board_full_removing = true;
        }
        MillBoardFullAction::SecondAndFirstPlayerRemovePiece => {
            state.pending_removals = [1, 1];
            state.side_to_move = 1;
            state.board_full_removing = true;
        }
        MillBoardFullAction::SideToMoveRemovePiece => {
            state.pending_removals = [0, 0];
            let remover = if options.is_defender_move_first { 1 } else { 0 };
            state.side_to_move = remover;
            state.pending_removals[remover as usize] = 1;
            state.board_full_removing = true;
        }
    }
}

/// True when `node` currently holds a piece that has been visually
/// preserved as a "marked" piece by `MarkAndDelayRemovingPieces`: the
/// piece colour is intact in `state.board` (so the UI can render an X),
/// but rule logic must treat the square as empty / inert until the
/// placing-to-moving transition sweeps it via `remove_marked_pieces`.
#[inline]
pub(super) fn is_marked(state: &MillState, node: usize) -> bool {
    (state.delayed_marked_pieces & node_bit(node)) != 0
}

/// Live (non-marked) piece colour at `node`: 0 = empty, 1 = white, 2 = black.
#[inline]
pub(super) fn live_piece(state: &MillState, node: usize) -> i8 {
    if is_marked(state, node) {
        0
    } else {
        state.board[node]
    }
}

pub(super) fn total_mills_count(state: &MillState, options: &MillVariantOptions, side: i8) -> u8 {
    mill_lines(options)
        .iter()
        .filter(|line| line.iter().all(|idx| live_piece(state, *idx) == side + 1))
        .count() as u8
}

pub(super) fn apply_removal_based_on_mill_counts(
    state: &mut MillState,
    options: &MillVariantOptions,
) {
    let white_mills = total_mills_count(state, options, 0);
    let black_mills = total_mills_count(state, options, 1);
    // Mirror Position::calculate_removal_based_on_mill_counts.  In C++ the
    // double-zero branch sets pieceToRemoveCount[c] = -1 for both sides:
    // the negative sign tells movegen to enumerate the *own* colour for
    // removal.  We model the sign with `remove_own_piece[c]` while
    // `pending_removals[c]` keeps the absolute count.
    state.remove_own_piece = [false, false];
    let (white_remove, black_remove) = if white_mills == 0 && black_mills == 0 {
        state.remove_own_piece = [true, true];
        (1_u8, 1_u8)
    } else if white_mills > 0 && black_mills == 0 {
        (2, 1)
    } else if black_mills > 0 && white_mills == 0 {
        (1, 2)
    } else if white_mills == black_mills {
        (white_mills, black_mills)
    } else if white_mills > black_mills {
        let black = black_mills;
        (black + 1, black)
    } else {
        let white = white_mills;
        (white, white + 1)
    };
    state.pending_removals = [white_remove, black_remove];
    if state.pending_removals[state.side_to_move as usize] == 0 {
        state.side_to_move ^= 1;
    }
    state.mill_available_at_removal = state.pending_removals.iter().any(|count| *count > 0);
}

pub(super) fn bump_ply_since_capture(state: &mut MillState, options: &MillVariantOptions) {
    // P0-F.2: mirror master's `isMovingOrMayMoveInPlacing` check in
    // search_engine.cpp L432-L458 which accumulates posKeyHistory (and thus
    // rule50) for BOTH the standard moving phase AND the placing-phase when
    // may_move_in_placing_phase is enabled.
    let is_move_counting_phase = state.phase == MillPhase::Moving
        || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase);
    if is_move_counting_phase {
        state.ply_since_capture = state.ply_since_capture.saturating_add(1);
    }
}

pub(super) fn maybe_draw_by_n_move_rule(state: &mut MillState, options: &MillVariantOptions) {
    // Mirror master src/position.cpp:2077 is_three_endgame:
    // C++ hard-codes the endgame N-move threshold to exactly three pieces,
    // independent of flyPieceCount. Keep the literal because UI/i18n wording
    // describes a "three-piece endgame" rather than a fly-threshold endgame.
    // P0-F.2: apply the N-move rule in placing phase as well when
    // may_move_in_placing_phase is enabled, matching master's behaviour where
    // the posKeyHistory size tracks move-type moves in both phases.
    let is_move_counting_phase = state.phase == MillPhase::Moving
        || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase);
    if !is_move_counting_phase {
        return;
    }
    let is_endgame = options.endgame_n_move_rule > 0
        && options.endgame_n_move_rule < options.n_move_rule
        && state.pieces_on_board.contains(&3);
    let threshold = if is_endgame {
        options.endgame_n_move_rule
    } else {
        options.n_move_rule
    };
    if threshold > 0 && u32::from(state.ply_since_capture) >= threshold {
        state.phase = MillPhase::GameOver;
        state.winner = 2;
        state.outcome_reason = if is_endgame {
            MillOutcomeReason::DrawEndgameFiftyMove
        } else {
            MillOutcomeReason::DrawFiftyMove
        };
        state.side_to_move = -1;
    }
}

pub(super) fn removal_count_for_bits(bits: u32, options: &MillVariantOptions) -> u8 {
    if options.may_remove_multiple {
        bits.count_ones().max(1) as u8
    } else {
        1
    }
}

pub(super) fn usable_mill_bits(state: &MillState, options: &MillVariantOptions, bits: u32) -> u32 {
    if !options.one_time_use_mill {
        return bits;
    }
    // Mirror master Position::potential_mills_count's oneTimeUseMill
    // branch: a line is "already used" *for this side* only when all
    // three of its squares are recorded in formed_mills_bb[side].
    // `used_mill_lines` is a global union and would over-restrict —
    // a line first formed by Black should still trigger a removal
    // when White reaches the same configuration.
    let side = state.side_to_move as usize;
    if side >= 2 {
        return bits;
    }
    let formed = state.formed_mills_bb[side];
    let mut usable = bits;
    let lines = mill_lines(options);
    for (line_idx, line) in lines.iter().enumerate() {
        if (bits & (1u32 << line_idx)) == 0 {
            continue;
        }
        let line_bb = node_bit(line[0]) | node_bit(line[1]) | node_bit(line[2]);
        if (line_bb & formed) == line_bb {
            usable &= !(1u32 << line_idx);
        }
    }
    usable
}

pub(super) fn note_mill_formation(
    state: &mut MillState,
    side: usize,
    from: i8,
    to: i8,
    bits: u32,
    options: &MillVariantOptions,
) {
    debug_assert!(side < 2);
    state.last_mill_from[side] = from;
    state.last_mill_to[side] = to;
    state.used_mill_lines |= bits;
    // Mirror Position::potential_mills_count (`oneTimeUseMill` branch):
    // Only record into `formedMillsBB[c]` when oneTimeUseMill is enabled.
    // C++ only maintains this bitmap in the `oneTimeUseMill` code path;
    // unconditionally accumulating it (as previously) caused the evaluator's
    // mills_pieces_count_difference to diverge for non-Russian-Mill rules.
    if options.one_time_use_mill {
        let lines = mill_lines(options);
        for (line_idx, line) in lines.iter().enumerate() {
            if (bits & (1u32 << line_idx)) != 0 {
                for &sq in line.iter() {
                    state.formed_mills_bb[side] |= node_bit(sq);
                }
            }
        }
    }
}

/// Hash the parts of a `MillState` that participate in threefold repetition.
/// P0-G: aligned with master's posKeyHistory key (same fields as
/// position_key): board layout, side-to-move, pending_removals[us] only, and
/// capture-misc. Phase, move_number, ply_since_capture and other transient
/// counters are excluded so a repeated board configuration always hashes
/// identically regardless of ply distance.
pub(super) fn repetition_signature(state: &MillState) -> u64 {
    // Always recompute from scratch: this is invoked from inside
    // `MillRules::apply` *before* `recompute_zobrist` writes the cache,
    // so `state.zobrist_key` may still hold the pre-mutation value.
    // Using the cache here would compare the new state against the
    // pre-move history under the wrong key.  Mirrors master's
    // `Position::key()` which always reads st.key after every
    // st.key ^= update inside do_move.
    let key = super::zobrist::full_state_key(state);
    if key == 0 { 1 } else { key }
}

/// Empty the rolling repetition history on irreversible events (Place/Remove),
/// matching master's `posKeyHistory.clear()` for MOVETYPE_PLACE and
/// MOVETYPE_REMOVE (engine_commands.cpp L151-157). Cycles can only span
/// pure Move sequences.
pub(super) fn clear_key_history(state: &mut MillState) {
    state.key_history.clear();
    state.key_history_len = 0;
}

/// Append the current state's repetition signature to the rolling buffer and,
/// when `adjudicate` is set, end the game in a draw once the same signature has
/// appeared three times.
///
/// Mirrors master src/position.cpp:25 `posKeyHistory`: the runtime history is
/// vector-backed and may grow to 256 entries; snapshot payloads persist only
/// the most recent 24 entries for compatibility with existing FRB snapshots.
/// No-op when `threefold_repetition_rule` is disabled.
///
/// `adjudicate` separates the two ways master uses repetition information:
///
///   * **Search** (`MillWorkbench::do_move`, `adjudicate = false`): master's
///     `Position::do_move` NEVER terminalises a threefold; the position stays
///     in the moving phase and `Eval::evaluate` returns the ordinary heuristic.
///     Inside the tree, repetitions are handled by `Search::has_repeated`
///     (a `VALUE_DRAW + 1` cut on the SECOND occurrence) -- not by a GameOver
///     state.  Keeping `do_move` non-terminalising is required for move parity:
///     e.g. at a Skill-1 (depth-1) leaf a move that completes a threefold must
///     be scored by its heuristic (master picks it), not collapsed to a draw.
///   * **Real play** (`GameRules::apply`, `adjudicate = true`): the move that
///     reaches the third occurrence ends the game, matching master's external
///     `has_game_cycle()` / `check_if_game_is_over` adjudication (non-Qt
///     `count >= 3`, i.e. the standard threefold).  The history itself is
///     tracked in BOTH modes so the search still sees the same repetition
///     window through `Workbench::current_repetition_count`.
pub(super) fn push_key_and_check_threefold(
    state: &mut MillState,
    options: &MillVariantOptions,
    adjudicate: bool,
) {
    if !options.threefold_repetition_rule {
        return;
    }
    let key = repetition_signature(state);
    if state.key_history.len() >= super::MILL_REPETITION_HISTORY_CAP {
        state.key_history.remove(0);
    }
    debug_assert!(state.key_history.len() < super::MILL_REPETITION_HISTORY_CAP);
    state.key_history.push(key);
    state.key_history_len = state.key_history.len();
    if !adjudicate {
        return;
    }
    let count = state.key_history.iter().filter(|k| **k == key).count();
    if count >= 3 {
        state.phase = MillPhase::GameOver;
        state.winner = 2;
        state.outcome_reason = MillOutcomeReason::DrawThreefold;
        state.side_to_move = -1;
    }
}
