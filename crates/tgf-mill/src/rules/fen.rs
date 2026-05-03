// SPDX-License-Identifier: GPL-3.0-or-later
// FEN-import helpers shared by `MillRules::set_from_fen` and
// `MillRules::export_fen`.  These are stateless conversion routines
// that turn raw FEN tokens into the equivalent `MillState` field
// updates and back.

use super::legacy_squares::{legacy_square_to_node_signed, node_to_legacy_square};
use super::MillState;

/// Parse a capture field shaped like `w-N-sq.sq|b-N-sq.sq` into per-side
/// target bitmaps and counts, mirroring master Position::set_fen.
pub(super) fn parse_capture_field(
    value: &str,
    targets_out: &mut [u32; 2],
    count_out: &mut [u8; 2],
) {
    for segment in value.split('|') {
        let segment = segment.trim();
        if segment.is_empty() || segment.len() < 3 || segment.as_bytes()[1] != b'-' {
            continue;
        }
        let side = match segment.as_bytes()[0] {
            b'w' => 0_usize,
            b'b' => 1_usize,
            _ => continue,
        };
        let after_color = &segment[2..];
        let dash = match after_color.find('-') {
            Some(d) => d,
            None => continue,
        };
        let count_str = after_color[..dash].trim();
        let parsed_count = match count_str.parse::<i32>() {
            Ok(v) => v,
            Err(_) => continue,
        };
        let list_str = &after_color[dash + 1..];
        for square_token in list_str.split('.') {
            let token = square_token.trim();
            if token.is_empty() {
                continue;
            }
            if let Ok(square_value) = token.parse::<i32>() {
                if (8..32).contains(&square_value) {
                    let node = legacy_square_to_node_signed(square_value as u8);
                    if (0..24).contains(&node) {
                        targets_out[side] |= 1_u32 << (node as u8);
                    }
                }
            }
        }
        let next = u32::from(count_out[side]).saturating_add(parsed_count.unsigned_abs());
        count_out[side] = next.min(u8::MAX as u32) as u8;
    }
}

/// Append a `c:`/`i:`/`l:` capture field with both side slots.
pub(super) fn append_capture_field(
    out: &mut String,
    label: char,
    targets: [u32; 2],
    count: [u8; 2],
) {
    if targets == [0, 0] && count == [0, 0] {
        return;
    }
    out.push(' ');
    out.push(label);
    out.push(':');
    for side in 0..2 {
        if side == 1 {
            out.push('|');
        }
        out.push(if side == 0 { 'w' } else { 'b' });
        out.push('-');
        out.push_str(&count[side].to_string());
        out.push('-');
        let mut first = true;
        for node in 0_usize..24 {
            if (targets[side] & (1u32 << node)) == 0 {
                continue;
            }
            if !first {
                out.push('.');
            }
            first = false;
            out.push_str(&node_to_legacy_square(node as i8).to_string());
        }
    }
}

/// Position-fingerprint hash used by repetition detection and the FEN
/// round-trip helpers.  Mirrors `Position::key` in master `position.cpp`:
/// deterministic XOR-style mixing over every field that participates in
/// move legality / repetition.
pub(super) fn position_key(state: &MillState) -> u64 {
    let mut key = 0xcbf2_9ce4_8422_2325_u64;
    let mut mix = |byte: u8| {
        key ^= u64::from(byte);
        key = key.wrapping_mul(0x1000_0000_01b3);
    };
    // Board pieces (piece-square, 24 squares × 2 bits owner).
    for piece in state.board {
        mix(piece as u8);
    }
    // Side to move.
    mix(state.side_to_move as u8);
    // pieceToRemoveCount for the active side only (mirrors update_key_misc).
    let us = (state.side_to_move as usize) & 1;
    mix(state.pending_removals[us]);
    mix(state.phase as u8);
    mix(state.action as u8);
    for side in 0..2 {
        mix(state.pieces_in_hand[side]);
        mix(state.pieces_on_board[side]);
        let signed_remove = if state.remove_own_piece[side] {
            -(i16::from(state.pending_removals[side]))
        } else {
            i16::from(state.pending_removals[side])
        };
        for byte in signed_remove.to_le_bytes() {
            mix(byte);
        }
        for byte in state.custodian_targets[side].to_le_bytes() {
            mix(byte);
        }
        for byte in state.intervention_targets[side].to_le_bytes() {
            mix(byte);
        }
        for byte in state.leap_targets[side].to_le_bytes() {
            mix(byte);
        }
        mix(state.custodian_count[side]);
        mix(state.intervention_count[side]);
        mix(state.leap_count[side]);
    }
    if key == 0 {
        1
    } else {
        key
    }
}
