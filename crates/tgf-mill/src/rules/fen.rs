// SPDX-License-Identifier: AGPL-3.0-or-later
// FEN-import helpers shared by `MillRules::set_from_fen` and
// `MillRules::export_fen`.  These are stateless conversion routines
// that turn raw FEN tokens into the equivalent `MillState` field
// updates and back.

use super::MillState;

pub(super) const NODE_ID_FEN_MARKER: &str = "ids:nodes";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum FenIdMode {
    LegacySquares,
    Nodes,
}

#[inline]
pub(super) fn id_mode_from_extensions(extension_tokens: &[&str]) -> FenIdMode {
    if extension_tokens
        .iter()
        .any(|token| token.eq_ignore_ascii_case(NODE_ID_FEN_MARKER))
    {
        FenIdMode::Nodes
    } else {
        FenIdMode::LegacySquares
    }
}

pub(super) fn parse_node_id(value: &str, mode: FenIdMode) -> Result<i8, String> {
    match mode {
        FenIdMode::LegacySquares => {
            let legacy = value
                .parse::<i16>()
                .map_err(|_| format!("cannot parse '{value}' as legacy square id"))?;
            if legacy == 0 {
                Ok(-1)
            } else if (8..32).contains(&legacy) {
                Ok((legacy - 8) as i8)
            } else {
                Err(format!("legacy square id must be 0 or 8..31, got {legacy}"))
            }
        }
        FenIdMode::Nodes => {
            let node = value
                .parse::<i8>()
                .map_err(|_| format!("cannot parse '{value}' as node id"))?;
            if node == -1 || (0..24).contains(&node) {
                Ok(node)
            } else {
                Err(format!("node id must be -1 or 0..23, got {node}"))
            }
        }
    }
}

pub(super) fn parse_node_bitboard(value: u32, mode: FenIdMode) -> Result<u32, String> {
    match mode {
        FenIdMode::LegacySquares => Ok(super::legacy_squares::legacy_square_bb_to_node_bb(value)),
        FenIdMode::Nodes => {
            if value & !0x00ff_ffff == 0 {
                Ok(value)
            } else {
                Err(format!(
                    "node bitboard must use bits 0..23 only, got {value}"
                ))
            }
        }
    }
}

/// Parse a capture field shaped like `w-N-sq.sq|b-N-sq.sq` into per-side
/// target bitmaps and counts, mirroring master Position::set_fen.
pub(super) fn parse_capture_field(
    value: &str,
    targets_out: &mut [u32; 2],
    count_out: &mut [u8; 2],
    mode: FenIdMode,
) -> Result<(), String> {
    for segment in value.split('|') {
        let segment = segment.trim();
        if segment.is_empty() || segment.len() < 3 || segment.as_bytes()[1] != b'-' {
            return Err(format!("invalid capture segment '{segment}'"));
        }
        let side = match segment.as_bytes()[0] {
            b'w' => 0_usize,
            b'b' => 1_usize,
            _ => return Err(format!("invalid capture side in segment '{segment}'")),
        };
        let after_color = &segment[2..];
        let dash = after_color
            .find('-')
            .ok_or_else(|| format!("invalid capture segment '{segment}'"))?;
        let count_str = after_color[..dash].trim();
        let parsed_count = count_str
            .parse::<i32>()
            .map_err(|_| format!("cannot parse '{count_str}' as capture count"))?;
        let list_str = &after_color[dash + 1..];
        for square_token in list_str.split('.') {
            let token = square_token.trim();
            if token.is_empty() {
                continue;
            }
            let node = parse_node_id(token, mode)?;
            if !(0..24).contains(&node) {
                return Err(format!("capture target must be 0..23, got {node}"));
            }
            targets_out[side] |= 1_u32 << (node as u8);
        }
        let next = u32::from(count_out[side]).saturating_add(parsed_count.unsigned_abs());
        count_out[side] = next.min(u8::MAX as u32) as u8;
    }
    Ok(())
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
            out.push_str(&node.to_string());
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
