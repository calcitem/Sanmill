// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! The 16-way symmetry used by Sanmill opening-book assets.
//!
//! Operation order exactly matches Flutter's `TransformationType.values`:
//! identity, three rotations, four reflections, then the same eight spatial
//! operations combined with an inner/outer ring swap.

use tgf_core::GameStateSnapshot;

use crate::MillUciCodec;

pub const OPENING_BOOK_SYMMETRY_COUNT: usize = 16;

const INVERSE_TRANSFORMS: [usize; OPENING_BOOK_SYMMETRY_COUNT] =
    [0, 3, 2, 1, 4, 5, 6, 7, 8, 11, 10, 9, 12, 13, 14, 15];

/// Normalize volatile FEN fields used by opening-book keys.
pub fn normalize_opening_book_fen(fen: &str) -> Result<String, String> {
    let mut fields = fen.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 17 {
        return Err(format!(
            "opening-book FEN must contain at least 17 fields, got {}",
            fields.len()
        ));
    }
    validate_board_field(fields[0])?;
    fields[14] = "0";
    fields[15] = "0";
    Ok(fields.join(" "))
}

/// Return the canonical FEN and the first transform that reaches it.
pub fn canonical_opening_book_fen(fen: &str) -> Result<(String, usize), String> {
    let normalized = normalize_opening_book_fen(fen)?;
    let mut canonical = normalized.clone();
    let mut canonical_transform = 0;
    for transform in 0..OPENING_BOOK_SYMMETRY_COUNT {
        let candidate = transform_opening_book_fen(&normalized, transform)?;
        if candidate < canonical {
            canonical = candidate;
            canonical_transform = transform;
        }
    }
    Ok((canonical, canonical_transform))
}

/// Apply one opening-book transform to a full Mill FEN.
pub fn transform_opening_book_fen(fen: &str, transform: usize) -> Result<String, String> {
    validate_transform(transform)?;
    let mut fields = fen
        .split_whitespace()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    if fields.len() < 17 {
        return Err(format!(
            "opening-book FEN must contain at least 17 fields, got {}",
            fields.len()
        ));
    }
    let board = board_chars(&fields[0])?;
    let mut transformed = ['?'; 24];
    for (old_node, piece) in board.into_iter().enumerate() {
        transformed[transform_opening_book_node(old_node, transform)?] = piece;
    }
    fields[0] = format!(
        "{}/{}/{}",
        transformed[0..8].iter().collect::<String>(),
        transformed[8..16].iter().collect::<String>(),
        transformed[16..24].iter().collect::<String>(),
    );
    let joined = fields.join(" ");
    normalize_opening_book_fen(&joined)
}

/// Transform an atomic or capture-combined Mill notation string.
pub fn transform_opening_book_notation(notation: &str, transform: usize) -> Result<String, String> {
    validate_transform(transform)?;
    let trimmed = notation.trim();
    if trimmed.is_empty() {
        return Err("opening-book notation must not be empty".to_owned());
    }

    if let Some((base, capture)) = trimmed.split_once('x') {
        if capture.contains('x') || capture.is_empty() {
            return Err(format!("invalid combined Mill notation {trimmed:?}"));
        }
        let capture = transform_atomic_notation(&format!("x{capture}"), transform)?;
        if base.is_empty() {
            return Ok(capture);
        }
        let base = transform_atomic_notation(base, transform)?;
        return Ok(format!("{base}{capture}"));
    }

    transform_atomic_notation(trimmed, transform)
}

pub fn inverse_opening_book_transform(transform: usize) -> Result<usize, String> {
    validate_transform(transform)?;
    Ok(INVERSE_TRANSFORMS[transform])
}

pub fn transform_opening_book_node(node: usize, transform: usize) -> Result<usize, String> {
    validate_transform(transform)?;
    if node >= 24 {
        return Err(format!("opening-book node must be in 0..24, got {node}"));
    }
    let spatial = transform % 8;
    let ring_swap = transform >= 8;
    let ring = node / 8;
    let local = node % 8;
    let target_ring = if ring_swap {
        match ring {
            0 => 2,
            1 => 1,
            2 => 0,
            _ => unreachable!(),
        }
    } else {
        ring
    };
    Ok(target_ring * 8 + transform_ring_index(local, spatial))
}

fn transform_atomic_notation(notation: &str, transform: usize) -> Result<String, String> {
    let dummy = GameStateSnapshot::default();
    let mut action = MillUciCodec::decode_action(&dummy, notation)
        .ok_or_else(|| format!("invalid Mill notation {notation:?}"))?;
    if action.from_node >= 0 {
        action.from_node =
            transform_opening_book_node(action.from_node as usize, transform)? as i16;
    }
    if action.to_node >= 0 {
        action.to_node = transform_opening_book_node(action.to_node as usize, transform)? as i16;
    }
    let transformed = MillUciCodec::encode_action(action);
    if transformed.is_empty() {
        Err(format!("unsupported Mill notation {notation:?}"))
    } else {
        Ok(transformed)
    }
}

fn transform_ring_index(index: usize, spatial: usize) -> usize {
    match spatial {
        0 => index,
        1 => (index + 2) % 8,
        2 => (index + 4) % 8,
        3 => (index + 6) % 8,
        4 => [4, 3, 2, 1, 0, 7, 6, 5][index],
        5 => [0, 7, 6, 5, 4, 3, 2, 1][index],
        6 => [2, 1, 0, 7, 6, 5, 4, 3][index],
        7 => [6, 5, 4, 3, 2, 1, 0, 7][index],
        _ => unreachable!(),
    }
}

fn validate_transform(transform: usize) -> Result<(), String> {
    if transform < OPENING_BOOK_SYMMETRY_COUNT {
        Ok(())
    } else {
        Err(format!(
            "opening-book transform must be in 0..{OPENING_BOOK_SYMMETRY_COUNT}, got {transform}"
        ))
    }
}

fn validate_board_field(board: &str) -> Result<(), String> {
    board_chars(board).map(|_| ())
}

fn board_chars(board: &str) -> Result<[char; 24], String> {
    let rings = board.split('/').collect::<Vec<_>>();
    if rings.len() != 3 || rings.iter().any(|ring| ring.chars().count() != 8) {
        return Err(format!(
            "opening-book board must contain three eight-point rings: {board:?}"
        ));
    }
    let chars = rings.concat().chars().collect::<Vec<_>>();
    chars
        .try_into()
        .map_err(|_| "opening-book board must contain exactly 24 points".to_owned())
}

#[cfg(test)]
#[path = "opening_book_symmetry_tests.rs"]
mod tests;
