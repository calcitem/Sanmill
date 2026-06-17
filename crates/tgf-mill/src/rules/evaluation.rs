// SPDX-License-Identifier: GPL-3.0-or-later
// Static evaluator helpers consumed by `MillEvaluator::score` and the
// game-over branch.  These are pure functions of `MillState` plus a
// `MillVariantOptions` snapshot; keeping them next to the evaluator
// keeps `mod.rs` focused on the rules / move dispatch surface.

use super::{
    MillBoardFullAction, MillPhase, MillState, MillVariantOptions, StalemateAction, live_piece,
};

/// Mirror of `Position::shouldConsiderMobility()` in option.h: enabled
/// when the user requested mobility scoring or when blocking-path focus
/// requires the mobility delta to drive the search.
pub(super) fn should_consider_mobility(options: &MillVariantOptions) -> bool {
    options.consider_mobility || options.focus_on_blocking_paths
}

/// Mirror of `Position::shouldFocusOnBlockingPaths()`: in placing it is
/// just the user toggle; in moving it additionally requires that flying
/// is enabled, the opponent is one move away from the fly threshold, and
/// the active side has at most two captured pieces left.
pub(super) fn should_focus_on_blocking_paths(
    state: &MillState,
    options: &MillVariantOptions,
) -> bool {
    if !options.focus_on_blocking_paths {
        return false;
    }
    match state.phase {
        MillPhase::Placing => true,
        MillPhase::Moving => {
            if !options.may_fly {
                return false;
            }
            let side = state.side_to_move as usize;
            if side >= 2 {
                return false;
            }
            let opp = side ^ 1;
            let opp_threshold = options.pieces_at_least_count.saturating_add(1);
            let our_min_pieces = options.piece_count.saturating_sub(2);
            state.pieces_on_board[opp] == opp_threshold
                && state.pieces_on_board[side] >= our_min_pieces
        }
        _ => false,
    }
}

/// Translation of `Position::mills_pieces_count_difference()`:
/// `popcount(formedMillsBB[WHITE]) - popcount(formedMillsBB[BLACK])`.
/// Counts every square recorded in any historically-formed mill, so a
/// single piece sitting on a 2-mill intersection contributes twice.
/// Driven by `note_mill_formation` (oneTimeUseMill semantics in master).
pub(super) fn mills_pieces_count_difference(
    state: &MillState,
    _options: &MillVariantOptions,
) -> i32 {
    state.formed_mills_bb[0].count_ones() as i32 - state.formed_mills_bb[1].count_ones() as i32
}

/// Translation of `Position::calculate_mobility_diff`: every empty (or
/// `MARKED_PIECE`) square contributes the count of its White / Black
/// neighbours.
pub(super) fn calculate_mobility_diff(state: &MillState, options: &MillVariantOptions) -> i32 {
    if state.delayed_marked_pieces == 0 {
        let mut white = 0_i32;
        let mut black = 0_i32;
        for s in 0_usize..24 {
            let piece = state.board[s];
            if piece != 1 && piece != 2 {
                continue;
            }
            let mut mobility = 0_i32;
            for &to in crate::topology::neighbors_for(s, options.has_diagonal_lines) {
                if state.board[to as usize] == 0 {
                    mobility += 1;
                }
            }
            if piece == 1 {
                white += mobility;
            } else {
                black += mobility;
            }
        }
        return white - black;
    }

    let mut white = 0_i32;
    let mut black = 0_i32;
    for s in 0_usize..24 {
        if live_piece(state, s) != 0 {
            // Occupied by a real (non-marked) piece — skip.
            continue;
        }
        for &neigh in crate::topology::neighbors_for(s, options.has_diagonal_lines) {
            match live_piece(state, neigh as usize) {
                1 => white += 1,
                2 => black += 1,
                _ => {}
            }
        }
    }
    white - black
}

#[inline]
pub(super) fn mobility_diff(state: &MillState, _options: &MillVariantOptions) -> i32 {
    state.mobility_diff
}

pub(super) fn recompute_mobility_diff(state: &mut MillState, options: &MillVariantOptions) {
    state.mobility_diff = if should_consider_mobility(options) {
        calculate_mobility_diff(state, options)
    } else {
        0
    };
}

#[inline]
pub(super) fn update_mobility_place(
    state: &mut MillState,
    options: &MillVariantOptions,
    node: usize,
    side: usize,
) {
    if !should_consider_mobility(options) {
        return;
    }
    let (adjacent_white, adjacent_black, adjacent_empty) =
        adjacent_mobility_counts(state, options, node);
    state.mobility_diff -= adjacent_white;
    state.mobility_diff += adjacent_black;
    if side == 0 {
        state.mobility_diff += adjacent_empty;
    } else {
        state.mobility_diff -= adjacent_empty;
    }
}

#[inline]
pub(super) fn update_mobility_remove(
    state: &mut MillState,
    options: &MillVariantOptions,
    node: usize,
) {
    if !should_consider_mobility(options) {
        return;
    }
    let piece = live_piece(state, node);
    debug_assert!(
        piece == 1 || piece == 2,
        "remove target must hold a live piece"
    );
    let (adjacent_white, adjacent_black, adjacent_empty) =
        adjacent_mobility_counts(state, options, node);
    state.mobility_diff += adjacent_white;
    state.mobility_diff -= adjacent_black;
    if piece == 1 {
        state.mobility_diff -= adjacent_empty;
    } else {
        state.mobility_diff += adjacent_empty;
    }
}

#[inline]
fn adjacent_mobility_counts(
    state: &MillState,
    options: &MillVariantOptions,
    node: usize,
) -> (i32, i32, i32) {
    let mut white = 0_i32;
    let mut black = 0_i32;
    let mut empty = 0_i32;
    for &neighbor in crate::topology::neighbors_for(node, options.has_diagonal_lines) {
        match live_piece(state, neighbor as usize) {
            0 => empty += 1,
            1 => white += 1,
            2 => black += 1,
            _ => {}
        }
    }
    (white, black, empty)
}

/// Detect whether the side has any legal move (placing or fly excluded:
/// matches `Position::is_all_surrounded`).  Only used for the static
/// evaluator's gameover branch where C++ checks
/// `phase == moving && action == select && is_all_surrounded(side)`.
pub(super) fn is_all_surrounded(state: &MillState, options: &MillVariantOptions, side: i8) -> bool {
    if (side & 1) != side {
        return false;
    }
    let s = side as usize;
    if state.pieces_on_board[0] + state.pieces_on_board[1] >= 24 {
        return true;
    }
    if options.may_fly && state.pieces_on_board[s] <= options.fly_piece_count {
        // Fly endgame: never surrounded as long as an empty square exists.
        return state.pieces_on_board[0] + state.pieces_on_board[1] >= 24;
    }
    for from in 0_usize..24 {
        if state.board[from] != side + 1 {
            continue;
        }
        for &to in crate::topology::neighbors_for(from, options.has_diagonal_lines) {
            if state.board[to as usize] == 0 {
                return false;
            }
        }
    }
    true
}

/// Translation of `Phase::gameOver` branch of `Evaluation::value`.
pub(super) fn gameover_value(
    state: &MillState,
    options: &MillVariantOptions,
    mate: i32,
    draw: i32,
) -> i32 {
    let on_board_total = i32::from(state.pieces_on_board[0]) + i32::from(state.pieces_on_board[1]);
    if options.piece_count == 12 && on_board_total >= 24 {
        return match options.board_full_action {
            MillBoardFullAction::FirstPlayerLose => -mate,
            MillBoardFullAction::AgreeToDraw => draw,
            // Other board-full variants resolve via remove-action elsewhere
            // and should never reach the static evaluator with phase=GameOver.
            _ => 0,
        };
    }
    let stalemate_loss = matches!(
        options.stalemate_action,
        StalemateAction::EndWithStalemateLoss
    );
    if stalemate_loss
        && state.phase == MillPhase::GameOver
        && state.pending_removals[0] == 0
        && state.pending_removals[1] == 0
        && (state.side_to_move == 0 || state.side_to_move == 1)
        && is_all_surrounded(state, options, state.side_to_move)
    {
        return if state.side_to_move == 0 { -mate } else { mate };
    }
    if i32::from(state.pieces_on_board[0]) < i32::from(options.pieces_at_least_count) {
        return -mate;
    }
    if i32::from(state.pieces_on_board[1]) < i32::from(options.pieces_at_least_count) {
        return mate;
    }
    0
}

/// Surrounded-pieces neighbour count: returns `(our, theirs, empty)`.
/// Used by [`super::remove_move_score`] / `MovePicker` style scoring.
/// The "marked piece" fourth bucket is intentionally omitted because the
/// C++ MovePicker discards it as well.
pub(super) fn surrounded_pieces_count(
    state: &MillState,
    options: &MillVariantOptions,
    s: usize,
) -> (i32, i32, i32) {
    let neighbors = crate::topology::neighbors_for(s, options.has_diagonal_lines);
    let our_piece = state.side_to_move + 1;
    let their_piece = (state.side_to_move ^ 1) + 1;
    let mut our = 0_i32;
    let mut theirs = 0_i32;
    let mut empty = 0_i32;
    for &n in neighbors {
        match state.board[n as usize] {
            0 => empty += 1,
            p if p == our_piece => our += 1,
            p if p == their_piece => theirs += 1,
            _ => {}
        }
    }
    (our, theirs, empty)
}

/// Mirrors the Remove branch in `src/movepick.cpp::score()`.  Combines the
/// "remove inside our mill" preference with mobility (empty neighbour count)
/// and the discouragement against capturing inside an opponent mill that is
/// already heavily defended.
pub(super) fn remove_move_score(state: &MillState, options: &MillVariantOptions, to: usize) -> i32 {
    let side = state.side_to_move;
    let opponent = side ^ 1;
    let our_mills = super::potential_mills_count_at(state, options, to, side, None) as i32;
    let their_mills = super::potential_mills_count_at(state, options, to, opponent, None) as i32;
    let (our_count, their_count, empty_count) = surrounded_pieces_count(state, options, to);

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
