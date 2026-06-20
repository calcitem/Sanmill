// SPDX-License-Identifier: GPL-3.0-or-later
// Static evaluator helpers consumed by `MillEvaluator::score` and the
// game-over branch.  These are pure functions of `MillState` plus a
// `MillVariantOptions` snapshot; keeping them next to the evaluator
// keeps `mod.rs` focused on the rules / move dispatch surface.

use super::{
    MillBoardFullAction, MillPhase, MillState, MillVariantOptions, StalemateAction,
    board_occupied_bitboard, live_occupied_bitboard, live_piece, node_bit,
};

// Limit inverted bitboards to the 24 real board nodes.  Rust's `!u32`
// otherwise leaves high bits set, which would make popcount-based empty
// square counts include non-board bits when the expression is not already
// intersected by a topology mask.
const MILL_BOARD_MASK: u32 = (1_u32 << 24) - 1;

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
    // Mobility follows master's live-piece semantics: delayed-marked
    // pieces are not live blockers, so they count as empty for mobility.
    // This differs from `board_occupied_bitboard`, which keeps marked
    // squares occupied for movement and surrounded-piece scoring.
    let live_empty = !live_occupied_bitboard(state) & MILL_BOARD_MASK;
    let mut white = 0_i32;
    let mut white_bb = state.by_color_bb[0];
    while white_bb != 0 {
        let node = white_bb.trailing_zeros() as usize;
        let neighbor_mask = crate::topology::neighbor_mask_for(node, options.has_diagonal_lines);
        white += (neighbor_mask & live_empty).count_ones() as i32;
        // Clear the least significant set bit and continue with the next
        // live piece, avoiding a 24-square scan in this evaluator hot path.
        white_bb &= white_bb - 1;
    }

    let mut black = 0_i32;
    let mut black_bb = state.by_color_bb[1];
    while black_bb != 0 {
        let node = black_bb.trailing_zeros() as usize;
        let neighbor_mask = crate::topology::neighbor_mask_for(node, options.has_diagonal_lines);
        black += (neighbor_mask & live_empty).count_ones() as i32;
        // Same bit-pop loop as White: one iteration per live Black piece.
        black_bb &= black_bb - 1;
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
    let neighbor_mask = crate::topology::neighbor_mask_for(node, options.has_diagonal_lines);
    // Incremental mobility updates must use the same live-empty definition
    // as `calculate_mobility_diff`; otherwise delayed removal would drift
    // between full recomputation and make/unmake updates.
    let live_occupied = live_occupied_bitboard(state);
    let white = (neighbor_mask & state.by_color_bb[0]).count_ones() as i32;
    let black = (neighbor_mask & state.by_color_bb[1]).count_ones() as i32;
    let empty = (neighbor_mask & !live_occupied).count_ones() as i32;
    (white, black, empty)
}

/// Detect whether the side has any legal move (placing or fly excluded:
/// matches `Position::is_all_surrounded`).  Used by stalemate handling and
/// by the static evaluator's gameover branch where C++ checks
/// `phase == moving && action == select && is_all_surrounded(side)`.
///
/// Mirrors `Position::is_all_surrounded` from master `src/position.cpp`.
/// When `restrict_repeated_mills_formation` is enabled the function also
/// treats a piece as "surrounded" if its only free neighbour is the
/// shuttle-back square that the restriction rule blocks — matching the
/// inline `isMoveRestricted` + `wouldFormMill` logic in the C++ version
/// (lines 3239-3297).
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
        // Mirror master: `restrictRepeatedMillsFormation` can only restrict
        // the single piece at lastMillToSquare from returning to
        // lastMillFromSquare; the remaining (flyPieceCount - 1) pieces are
        // unrestricted and can fly to any empty square, so the player always
        // has at least one legal move when flying is available.
        return state.pieces_on_board[0] + state.pieces_on_board[1] >= 24;
    }
    let own_bb = state.by_color_bb[s];
    let occupied = board_occupied_bitboard(state);
    let mut pieces = own_bb;
    while pieces != 0 {
        let from = pieces.trailing_zeros() as usize;
        let neighbor_mask = crate::topology::neighbor_mask_for(from, options.has_diagonal_lines);
        // Surrounded checks are about legal movement, so delayed-marked
        // squares remain occupied here.  The mask already limits `!occupied`
        // to adjacent board nodes, making an extra board mask unnecessary.
        let empty_adjacent = neighbor_mask & !occupied;
        if empty_adjacent == 0 {
            // All adjacent squares are occupied — physically surrounded.
            pieces &= pieces - 1;
            continue;
        }
        // At least one empty adjacent square exists.  When
        // `restrict_repeated_mills_formation` is active this piece may still
        // be effectively stuck if its only free neighbour is the single
        // square that the shuttle restriction forbids.  Mirror master
        // `Position::is_all_surrounded` lines 3239-3297.
        if options.restrict_repeated_mills_formation {
            let last_to = state.last_mill_to[s];
            let last_from = state.last_mill_from[s];
            if last_to >= 0
                && last_from >= 0
                && from == last_to as usize
                && empty_adjacent == node_bit(last_from as usize)
            {
                // The sole free neighbour is the restricted destination.
                // Check whether the restriction conditions actually hold:
                //   1. `from` must currently be part of a usable mill.
                //   2. Moving to `last_from` would form a new usable mill.
                if is_shuttle_move_restricted(state, options, from, last_from as usize, s) {
                    // Treat this piece as surrounded and continue to the next.
                    pieces &= pieces - 1;
                    continue;
                }
            }
        }
        return false;
    }
    true
}

/// Returns `true` when the move `from` → `to` is blocked by the
/// `restrict_repeated_mills_formation` rule.  Mirrors the C++
/// `isMoveRestricted` lambda inside `Position::is_all_surrounded` and the
/// shared `is_restricted_repeated_mill` logic used during move generation.
///
/// Preconditions (caller must verify):
///   * `from == state.last_mill_to[side]`
///   * `to   == state.last_mill_from[side]` (both non-negative)
fn is_shuttle_move_restricted(
    state: &MillState,
    options: &MillVariantOptions,
    from: usize,
    to: usize,
    side: usize,
) -> bool {
    // Condition 1 — piece at `from` is currently in a usable mill.
    let color_bb = state.by_color_bb[side];
    let from_in_mill = super::mill_line_peer_masks_for_node(options, from)
        .iter()
        .take_while(|&&m| m != 0)
        .any(|&peer_mask| {
            if (color_bb & peer_mask) != peer_mask {
                return false;
            }
            if options.one_time_use_mill {
                let line_bb = super::node_bit(from) | peer_mask;
                (line_bb & state.formed_mills_bb[side]) != line_bb
            } else {
                true
            }
        });
    if !from_in_mill {
        return false;
    }
    // Condition 2 — moving `from` → `to` would form a new usable mill at `to`.
    // Virtually remove the piece at `from` to simulate the move.
    let color_bb_virtual = color_bb & !super::node_bit(from);
    super::mill_line_peer_masks_for_node(options, to)
        .iter()
        .take_while(|&&m| m != 0)
        .any(|&peer_mask| {
            if (color_bb_virtual & peer_mask) != peer_mask {
                return false;
            }
            if options.one_time_use_mill {
                let line_bb = super::node_bit(to) | peer_mask;
                (line_bb & state.formed_mills_bb[side]) != line_bb
            } else {
                true
            }
        })
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
    if !(0..2).contains(&state.side_to_move) {
        return (0, 0, 0);
    }
    let side = state.side_to_move as usize;
    let neighbor_mask = crate::topology::neighbor_mask_for(s, options.has_diagonal_lines);
    let our_bb = state.by_color_bb[side];
    let their_bb = state.by_color_bb[side ^ 1];
    // Remove scoring follows master's MovePicker bucket accounting:
    // live side pieces are counted through by-color bitboards, marked
    // pieces are deliberately omitted from the side buckets, and board
    // occupancy prevents marked squares from being counted as empty.
    let occupied = board_occupied_bitboard(state);
    let our = (neighbor_mask & our_bb).count_ones() as i32;
    let theirs = (neighbor_mask & their_bb).count_ones() as i32;
    let empty = (neighbor_mask & !occupied).count_ones() as i32;
    (our, theirs, empty)
}

/// Mirrors the Remove branch in `src/movepick.cpp::score()`.  Combines the
/// "remove inside our mill" preference with mobility (empty neighbour count)
/// and the discouragement against capturing inside an opponent mill that is
/// already heavily defended.
pub(super) fn remove_move_score(state: &MillState, options: &MillVariantOptions, to: usize) -> i32 {
    let side = state.side_to_move;
    if !(0..2).contains(&side) {
        return 0;
    }
    let opponent = side ^ 1;
    let (our_mills, their_mills) = if state.delayed_marked_pieces == 0
        && !options.has_diagonal_lines
        && !options.one_time_use_mill
    {
        let (our_mills, their_mills) = super::potential_mills_count_standard_unrestricted_pair(
            state.by_color_bb[side as usize],
            state.by_color_bb[opponent as usize],
            to,
            None,
        );
        (our_mills as i32, their_mills as i32)
    } else {
        (
            super::potential_mills_count_at(state, options, to, side, None) as i32,
            super::potential_mills_count_at(state, options, to, opponent, None) as i32,
        )
    };
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
