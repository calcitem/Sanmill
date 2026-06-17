// SPDX-License-Identifier: GPL-3.0-or-later
// FEN-import helpers shared by `MillRules::set_from_fen` and
// `MillRules::export_fen`.  These are stateless conversion routines
// that turn raw FEN tokens into the equivalent `MillState` field
// updates and back.

use super::MillState;
use super::legacy_squares::{legacy_square_to_node_signed, node_to_legacy_square};

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
            if let Ok(square_value) = token.parse::<i32>()
                && (8..32).contains(&square_value)
            {
                let node = legacy_square_to_node_signed(square_value as u8);
                if (0..24).contains(&node) {
                    targets_out[side] |= 1_u32 << (node as u8);
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
/// round-trip helpers.  Returns the cached `MillState::zobrist_key`
/// when it is non-zero (i.e. when the state went through
/// `MillRules::apply` or `recompute_zobrist`); falls back to a full
/// Zobrist recomputation otherwise to keep consumers that synthesise
/// `MillState` directly (tests, FEN setup) working without first
/// calling apply.
///
/// Mirrors `Position::key` in master `src/position.cpp`: piece-square
/// xor + side-to-move + capture-state target/count xors + 2-bit
/// piece-to-remove counter in the high bits (`update_key_misc`).
pub(super) fn position_key(state: &MillState) -> u64 {
    let cached = state.zobrist_key;
    if cached != 0 {
        return cached;
    }
    super::zobrist::full_state_key(state)
}
