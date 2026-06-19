// SPDX-License-Identifier: GPL-3.0-or-later
// Custodian / intervention / leap capture detection and bookkeeping.
//
// These helpers mirror master `Position::checkCustodianCapture`,
// `checkInterventionCapture`, and `checkLeapCapture` plus the per-side
// `custodian_targets / intervention_targets / leap_targets` state
// management that follows once a capture is activated.

use tgf_core::BoardTopology;

use super::lines::{CAPTURE_CROSS_LINES, CAPTURE_DIAGONAL_LINES, CAPTURE_SQUARE_EDGE_LINES};
use super::{
    CaptureRuleConfig, MillPhase, MillState, MillTopology, MillVariantOptions, is_piece_in_mill,
    node_bit, piece_bitboard,
};

pub(super) fn active_capture_lines(
    config: &CaptureRuleConfig,
    options: &MillVariantOptions,
) -> Vec<[usize; 3]> {
    let mut lines = Vec::new();
    if config.on_cross_lines {
        lines.extend_from_slice(CAPTURE_CROSS_LINES);
    }
    if config.on_square_edges {
        lines.extend_from_slice(CAPTURE_SQUARE_EDGE_LINES);
    }
    if config.on_diagonal_lines && options.has_diagonal_lines {
        lines.extend_from_slice(CAPTURE_DIAGONAL_LINES);
    }
    lines
}

pub(super) fn capture_phase_allowed(config: &CaptureRuleConfig, phase: MillPhase) -> bool {
    config.enabled
        && match phase {
            MillPhase::Placing => config.in_placing_phase,
            MillPhase::Moving => config.in_moving_phase,
            MillPhase::Ready | MillPhase::GameOver => false,
        }
}

pub(super) fn capture_piece_count_allowed(config: &CaptureRuleConfig, state: &MillState) -> bool {
    // For custodian and intervention captures, onlyAvailableWhenOwnPiecesLeq3
    // only applies in moving phase, matching master's checkCustodianCapture
    // and checkInterventionCapture where the condition is guarded by
    // `if (phase == Phase::moving)`.
    if !config.only_available_when_own_pieces_leq3 || state.phase != MillPhase::Moving {
        return true;
    }
    let side = state.side_to_move as usize;
    let us = state.pieces_on_board[side];
    us <= 3
}

pub(super) fn capture_piece_count_allowed_leap(
    config: &CaptureRuleConfig,
    state: &MillState,
) -> bool {
    // For leap captures, onlyAvailableWhenOwnPiecesLeq3 applies in BOTH
    // placing and moving phases.  This mirrors master's checkLeapCapture
    // where the condition is checked OUTSIDE any phase guard (unlike
    // custodian/intervention which wrap it in `if (phase == Phase::moving)`).
    if !config.only_available_when_own_pieces_leq3 {
        return true;
    }
    let side = state.side_to_move as usize;
    let us = state.pieces_on_board[side];
    us <= 3
}

pub(super) fn is_all_in_mills(state: &MillState, options: &MillVariantOptions, piece: i8) -> bool {
    let target_bb = piece_bitboard(state, piece);
    (0_usize..24).all(|idx| {
        let mask = node_bit(idx);
        (target_bb & mask) == 0 || is_piece_in_mill(state, options, idx)
    })
}

/// Validates that the piece at `mid` (the captured middle square) is actually
/// removable under mill-protection rules.  Called during leap move generation
/// to mirror master's checkLeapCapture mill-protection validation (P0-A.2).
pub(super) fn leap_capture_target_is_removable(
    state: &MillState,
    options: &MillVariantOptions,
    mid: usize,
) -> bool {
    let opponent_piece = (state.side_to_move ^ 1) + 1;
    if (piece_bitboard(state, opponent_piece) & node_bit(mid)) == 0 {
        return false;
    }
    // Mill protection: if may_remove_from_mills_always is false, a piece in a
    // mill cannot be captured unless ALL opponent pieces are in mills.
    if !options.may_remove_from_mills_always
        && is_piece_in_mill(state, options, mid)
        && !is_all_in_mills(state, options, opponent_piece)
    {
        return false;
    }
    true
}

pub(super) fn is_adjacent_to_side_piece(
    state: &MillState,
    topology: &MillTopology,
    node: usize,
) -> bool {
    if state.side_to_move < 0 {
        return false;
    }
    let own_bb = piece_bitboard(state, state.side_to_move + 1);
    topology
        .neighbors(node as u16)
        .iter()
        .any(|neighbor| (own_bb & node_bit(*neighbor as usize)) != 0)
}

pub(super) fn filter_capture_targets(
    state: &MillState,
    options: &MillVariantOptions,
    targets: u32,
) -> u32 {
    let opponent_piece = (state.side_to_move ^ 1) + 1;
    let opponent_bb = piece_bitboard(state, opponent_piece);
    let mut filtered = 0_u32;
    let all_in_mills = is_all_in_mills(state, options, opponent_piece);
    for node in 0..24_usize {
        let mask = node_bit(node);
        if (targets & mask) == 0 || (opponent_bb & mask) == 0 {
            continue;
        }
        if !options.may_remove_from_mills_always
            && is_piece_in_mill(state, options, node)
            && !all_in_mills
        {
            continue;
        }
        filtered |= mask;
    }
    filtered
}

pub(super) fn detect_custodian_targets(
    state: &MillState,
    options: &MillVariantOptions,
    to: usize,
) -> u32 {
    let config = &options.custodian_capture;
    if !capture_phase_allowed(config, state.phase) || !capture_piece_count_allowed(config, state) {
        return 0;
    }
    let us = state.side_to_move + 1;
    let them = state.side_to_move ^ 1;
    let opponent = them + 1;
    let us_bb = piece_bitboard(state, us);
    let opponent_bb = piece_bitboard(state, opponent);
    let mut targets = 0_u32;
    for line in active_capture_lines(config, options) {
        let brackets_middle = (to == line[0] && (us_bb & node_bit(line[2])) != 0)
            || (to == line[2] && (us_bb & node_bit(line[0])) != 0);
        if brackets_middle && (opponent_bb & node_bit(line[1])) != 0 {
            targets |= node_bit(line[1]);
        }
    }
    filter_capture_targets(state, options, targets)
}

pub(super) fn detect_intervention_targets(
    state: &MillState,
    options: &MillVariantOptions,
    to: usize,
) -> u32 {
    let config = &options.intervention_capture;
    if !capture_phase_allowed(config, state.phase) || !capture_piece_count_allowed(config, state) {
        return 0;
    }
    let opponent = (state.side_to_move ^ 1) + 1;
    let opponent_bb = piece_bitboard(state, opponent);

    // Mirror master src/position.cpp:2670 checkInterventionCapture: collect
    // raw capture lines first, select the preferred/first line, then apply
    // mill-protection filtering only to that selected line.  If filtering
    // removes every target, the intervention capture is abandoned instead
    // of falling back to another line.
    let preferred = state.preferred_remove_target;

    let mut capture_lines: Vec<u32> = Vec::new();
    for line in active_capture_lines(config, options) {
        if to == line[1]
            && (opponent_bb & node_bit(line[0])) != 0
            && (opponent_bb & node_bit(line[2])) != 0
        {
            let targets = node_bit(line[0]) | node_bit(line[2]);
            capture_lines.push(targets);
        }
    }
    if capture_lines.is_empty() {
        return 0;
    }

    // Select the line containing preferredRemoveTarget if specified.
    if preferred >= 0 {
        let pref_mask = node_bit(preferred as usize);
        if let Some(&line) = capture_lines.iter().find(|&&l| (l & pref_mask) != 0) {
            return filter_capture_targets(state, options, line);
        }
    }
    // Fall back to the first valid line (mirrors master's captureLines[0]).
    filter_capture_targets(state, options, capture_lines[0])
}

pub(super) fn detect_leap_targets(
    state: &MillState,
    options: &MillVariantOptions,
    from: usize,
    to: usize,
) -> u32 {
    let config = &options.leap_capture;
    // Use the leap-specific piece-count check that applies in both placing
    // and moving phases (master checkLeapCapture has the count guard outside
    // any phase conditional, unlike custodian/intervention).
    if !capture_phase_allowed(config, state.phase)
        || !capture_piece_count_allowed_leap(config, state)
    {
        return 0;
    }
    let opponent = (state.side_to_move ^ 1) + 1;
    let opponent_bb = piece_bitboard(state, opponent);
    let mut targets = 0_u32;
    for line in active_capture_lines(config, options) {
        let jumps_over_middle =
            (to == line[2] && from == line[0]) || (to == line[0] && from == line[2]);
        if jumps_over_middle && (opponent_bb & node_bit(line[1])) != 0 {
            targets |= node_bit(line[1]);
        }
    }
    filter_capture_targets(state, options, targets)
}

fn bit_count(mask: u32) -> u8 {
    mask.count_ones().min(u8::MAX as u32) as u8
}

pub(super) fn clear_capture_state(state: &mut MillState) {
    state.custodian_targets = [0, 0];
    state.intervention_targets = [0, 0];
    state.leap_targets = [0, 0];
    state.custodian_count = [0, 0];
    state.intervention_count = [0, 0];
    state.leap_count = [0, 0];
    state.mill_available_at_removal = false;
}

pub(super) fn clear_capture_state_for_side(state: &mut MillState, side: usize) {
    debug_assert!(side < 2);
    state.custodian_targets[side] = 0;
    state.intervention_targets[side] = 0;
    state.leap_targets[side] = 0;
    state.custodian_count[side] = 0;
    state.intervention_count[side] = 0;
    state.leap_count[side] = 0;
    state.mill_available_at_removal = false;
}

pub(super) fn activate_capture_state(
    state: &mut MillState,
    custodian: u32,
    intervention: u32,
    leap: u32,
) {
    let side = state.side_to_move as usize;
    if side >= 2 {
        return;
    }
    state.custodian_targets[side] = custodian;
    state.intervention_targets[side] = intervention;
    state.leap_targets[side] = leap;
    state.custodian_count[side] = bit_count(custodian);
    state.intervention_count[side] = bit_count(intervention);
    state.leap_count[side] = bit_count(leap);
}

pub(super) fn capture_total(state: &MillState) -> u8 {
    let side = state.side_to_move as usize;
    if side >= 2 {
        return 0;
    }
    state.custodian_count[side]
        .saturating_add(state.intervention_count[side])
        .saturating_add(state.leap_count[side])
}

pub(super) fn find_paired_intervention_target(
    removed: usize,
    targets: u32,
    options: &MillVariantOptions,
) -> u32 {
    for line in active_capture_lines(&options.intervention_capture, options) {
        let a = line[0];
        let b = line[2];
        if removed == a && (targets & node_bit(b)) != 0 {
            return node_bit(b);
        }
        if removed == b && (targets & node_bit(a)) != 0 {
            return node_bit(a);
        }
    }
    targets & !node_bit(removed)
}
