// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Shared codec for the external NMM_LLM `human_db.sqlite` conventions:
//! `state_key` encode/decode, the D4 board canonicalization it uses, its
//! move-notation coordinate transforms, and the full-turn notation parser.
//!
//! Both consumers -- the FRB Human Database lookup
//! (`crates/tgf-frb/src/games/mill/human_db.rs`) and the patch packer's
//! behavior-weighted trap scoring (`crates/tgf-cli/src/mill_pack/`) -- must
//! route through this one module so the two ends can never drift apart on
//! coordinates.
//!
//! This module is deliberately pure logic: it depends on nothing beyond
//! `tgf-mill` itself (no sqlite, no perfect-db). Database scanning stays in
//! the callers, and canonical-key derivation / sign calibration stay in the
//! perfect-db domain: everything here returns concrete states and actions.
//!
//! Coordinate-frame contract (see `docs/HUMAN_DATABASE.md`): a `state_key`
//! stores the board in **its own D4-canonical orientation**, and the
//! `moves.notation` strings for that key live in the **same orientation**.
//! Decoding therefore always reconstructs the state in the key's frame
//! first, applies moves there, and only then may a caller canonicalize the
//! results; canonicalizing the parent before parsing the notation would
//! land moves on the wrong points.

use tgf_core::{Action, GameRules, GameStateSnapshot};

use crate::notation::MillUciCodec;
use crate::rules::{MillPhase, MillRules};

/// NMM_LLM's canonical 24-character board string order (outer ring, middle
/// ring, inner ring) mapped to this engine's node ids.
pub const NMM_POSITION_ORDER_NODES: [usize; 24] = [
    23, 16, 17, 18, 19, 20, 21, 22, // outer ring
    15, 8, 9, 10, 11, 12, 13, 14, // middle ring
    7, 0, 1, 2, 3, 4, 5, 6, // inner ring
];

/// Point labels in the same order as [`NMM_POSITION_ORDER_NODES`].
pub const NMM_POSITIONS: [&str; 24] = [
    "a7", "d7", "g7", "g4", "g1", "d1", "a1", "a4", "b6", "d6", "f6", "f4", "f2", "d2", "b2", "b4",
    "c5", "d5", "e5", "e4", "e3", "d3", "c3", "c4",
];

/// Board coordinates for each entry of [`NMM_POSITIONS`].
pub const POSITION_COORDS: [(i8, i8); 24] = [
    (-3, 3),
    (0, 3),
    (3, 3),
    (3, 0),
    (3, -3),
    (0, -3),
    (-3, -3),
    (-3, 0),
    (-2, 2),
    (0, 2),
    (2, 2),
    (2, 0),
    (2, -2),
    (0, -2),
    (-2, -2),
    (-2, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, -1),
    (-1, 0),
];

/// The 8 D4 symmetries the human database canonicalizes with, as 2x2
/// integer matrices `(a, b, c, d)` acting on [`POSITION_COORDS`].
pub const SYMMETRIES: [(i8, i8, i8, i8); 8] = [
    (1, 0, 0, 1),
    (0, -1, 1, 0),
    (-1, 0, 0, -1),
    (0, 1, -1, 0),
    (-1, 0, 0, 1),
    (1, 0, 0, -1),
    (0, 1, 1, 0),
    (0, -1, -1, 0),
];

/// Index of each symmetry's inverse in [`SYMMETRIES`].
pub const SYM_INVERSE: [usize; 8] = [0, 3, 2, 1, 4, 5, 6, 7];

/// Build a Mill FEN from a `human_db.sqlite` `positions.state_key` /
/// `moves.state_key` value
/// (`{canon}|{turn}|{phase}|{placed_w}|{placed_b}|{on_w}|{on_b}`). Returns
/// `None` for malformed keys; the human database is external, user-supplied
/// data, so callers should skip rather than panic on a bad row.
pub fn fen_from_state_key(state_key: &str) -> Option<String> {
    let fields = state_key.split('|').collect::<Vec<_>>();
    if fields.len() < 7 {
        return None;
    }
    let canonical = fields[0];
    if canonical.len() != 24 {
        return None;
    }
    let side = match fields[1] {
        "W" => "w",
        "B" => "b",
        _ => return None,
    };
    let phase = match fields[2] {
        "place" => "p",
        "move" | "fly" => "m",
        _ => return None,
    };
    let action = if phase == "p" { "p" } else { "s" };
    let placed_w = fields[3].parse::<u8>().ok()?;
    let placed_b = fields[4].parse::<u8>().ok()?;
    let on_w = fields[5].parse::<u8>().ok()?;
    let on_b = fields[6].parse::<u8>().ok()?;
    let hand_w = 9_u8.checked_sub(placed_w)?;
    let hand_b = 9_u8.checked_sub(placed_b)?;

    let mut board = ['*'; 24];
    for (nmm_idx, ch) in canonical.chars().enumerate() {
        let node = NMM_POSITION_ORDER_NODES[nmm_idx];
        board[node] = match ch {
            'W' => 'O',
            'B' => '@',
            '.' => '*',
            _ => return None,
        };
    }
    let inner: String = board[0..8].iter().collect();
    let middle: String = board[8..16].iter().collect();
    let outer: String = board[16..24].iter().collect();
    Some(format!(
        "{inner}/{middle}/{outer} {side} {phase} {action} \
         {on_w} {hand_w} {on_b} {hand_b} 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
    ))
}

/// Canonical `state_key` (plus the symmetry index that produced it) for a
/// standard Nine Men's Morris FEN, mirroring the human database builder's
/// convention.
pub fn state_key_from_fen(fen: &str) -> Result<(String, usize), String> {
    let fields = fen.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 8 {
        return Err("Mill FEN must contain at least 8 fields".to_owned());
    }
    if fields[1] != "w" && fields[1] != "b" {
        return Err(format!("invalid side-to-move in Mill FEN: {}", fields[1]));
    }

    let rules = MillRules::new(crate::rules::MillVariantOptions::default());
    let state = rules.set_from_fen(fen)?;
    let pieces_in_hand = state.pieces_in_hand();
    let pieces_on_board = state.pieces_on_board();

    for (side, in_hand) in pieces_in_hand.iter().enumerate() {
        assert!(
            *in_hand <= 9,
            "Human Database supports standard Nine Men's Morris hand counts only"
        );
        assert!(
            pieces_on_board[side] + *in_hand <= 9,
            "Human Database supports standard Nine Men's Morris piece totals only"
        );
    }

    let board24 = nmm_board24(state.board());
    let (canonical, sym_idx) = canonical_board_str(&board24);
    let turn = if fields[1] == "w" { "W" } else { "B" };
    let side = if fields[1] == "w" { 0 } else { 1 };
    let phase = phase_for_side(state.phase(), pieces_in_hand[side], pieces_on_board[side]);
    let placed_w = 9_u8 - pieces_in_hand[0];
    let placed_b = 9_u8 - pieces_in_hand[1];

    Ok((
        format!(
            "{canonical}|{turn}|{phase}|{placed_w}|{placed_b}|{}|{}",
            pieces_on_board[0], pieces_on_board[1],
        ),
        sym_idx,
    ))
}

/// Phase field of a `state_key` for the given side, mirroring the human
/// database builder's convention.
pub fn phase_for_side(phase: MillPhase, pieces_in_hand: u8, pieces_on_board: u8) -> &'static str {
    if phase == MillPhase::Placing || pieces_in_hand > 0 {
        "place"
    } else if pieces_on_board <= 3 {
        "fly"
    } else {
        "move"
    }
}

/// Export a [`MillState`] board as the human database's 24-character
/// outer/middle/inner string.
pub fn nmm_board24(board: &[i8; 24]) -> String {
    NMM_POSITION_ORDER_NODES
        .iter()
        .map(|&node| match board[node] {
            1 => 'W',
            2 => 'B',
            _ => '.',
        })
        .collect()
}

/// Lexicographically smallest D4 image of `board24` plus the symmetry
/// index that produced it.
pub fn canonical_board_str(board24: &str) -> (String, usize) {
    assert!(
        board24.len() == 24,
        "Human Database canonicalization requires a 24-character board"
    );
    let mut best = board24.to_owned();
    let mut best_idx = 0;
    for sym_idx in 1..SYMMETRIES.len() {
        let transformed =
            apply_board_sym(board24, sym_idx).expect("Mill D4 transform must stay on board");
        if transformed < best {
            best = transformed;
            best_idx = sym_idx;
        }
    }
    (best, best_idx)
}

/// Apply symmetry `sym_idx` to a 24-character board string.
pub fn apply_board_sym(board24: &str, sym_idx: usize) -> Option<String> {
    let chars = board24.chars().collect::<Vec<_>>();
    let mut result = ['?'; 24];
    for (old_idx, ch) in chars.into_iter().enumerate() {
        let new_idx = transform_index(old_idx, sym_idx)?;
        result[new_idx] = ch;
    }
    Some(result.iter().collect())
}

/// Map a stored notation (place / move / capture-combined) through
/// symmetry `sym_idx`.
pub fn transform_notation(notation: &str, sym_idx: usize) -> Option<String> {
    if sym_idx == 0 {
        return Some(notation.to_owned());
    }

    let (base, capture) = match notation.split_once('x') {
        Some((base, capture)) => (base, Some(capture)),
        None => (notation, None),
    };
    let capture_suffix = match capture {
        Some(pos) => format!("x{}", transform_pos(pos, sym_idx)?),
        None => String::new(),
    };

    if base.is_empty() {
        return Some(capture_suffix);
    }
    if let Some((from, to)) = base.split_once('-') {
        return Some(format!(
            "{}-{}{}",
            transform_pos(from, sym_idx)?,
            transform_pos(to, sym_idx)?,
            capture_suffix,
        ));
    }
    Some(format!(
        "{}{}",
        transform_pos(base, sym_idx)?,
        capture_suffix
    ))
}

/// Map a single point label through symmetry `sym_idx`.
pub fn transform_pos(pos: &str, sym_idx: usize) -> Option<&'static str> {
    let idx = position_index(pos)?;
    let next = transform_index(idx, sym_idx)?;
    Some(NMM_POSITIONS[next])
}

/// Map a [`NMM_POSITIONS`] index through symmetry `sym_idx`.
pub fn transform_index(idx: usize, sym_idx: usize) -> Option<usize> {
    let (x, y) = POSITION_COORDS[idx];
    let (a, b, c, d) = SYMMETRIES[sym_idx];
    position_index_from_coords((a * x + b * y, c * x + d * y))
}

fn position_index(pos: &str) -> Option<usize> {
    NMM_POSITIONS.iter().position(|candidate| *candidate == pos)
}

fn position_index_from_coords(coords: (i8, i8)) -> Option<usize> {
    POSITION_COORDS
        .iter()
        .position(|candidate| *candidate == coords)
}

/// Deterministic FNV-1a-style hash, used to deduplicate `state_key`
/// strings without keeping the (potentially large) strings themselves
/// around.
pub fn stable_hash(value: &str) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// One parsed human-database turn. The database stores a mill-forming move
/// and its capture as a single combined notation (`d6-d7xa4`, `d2xa4`), so
/// a turn is more than one engine action; a bare `xa4` row can also occur
/// and must stay distinguishable for the caller's routing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HumanTurn {
    /// A plain placement or move that does not capture.
    BaseOnly(Action),
    /// A mill-forming placement or move plus the follow-up removal.
    BaseThenCapture { base: Action, capture: Action },
    /// A bare removal (only legal when the position already has a pending
    /// removal).
    CaptureOnly(Action),
}

/// Why [`parse_human_turn_notation`] rejected a notation. The buckets
/// mirror the packer's diagnostic counters.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HumanTurnError {
    /// The base segment failed to parse or is not legal in the given
    /// position.
    BaseInvalid,
    /// The capture segment failed to parse or is not legal in its
    /// reference frame.
    CaptureInvalid,
    /// A capture segment is present but the base move leaves no pending
    /// removal to serve it.
    UnexpectedCapture,
}

/// Parse a human-database notation against `snap`, validating every
/// segment in its own reference frame:
///
/// * the base segment is validated against `snap`'s legal actions;
/// * a capture segment of a combined notation is validated against the
///   legal actions of the position reached **after applying the base**
///   (the pending-removal snapshot) -- never against `snap` itself;
/// * a bare capture (`xa4`) is validated against `snap`'s legal actions,
///   which only contain removals when `snap` itself has a pending removal.
pub fn parse_human_turn_notation(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    notation: &str,
) -> Result<HumanTurn, HumanTurnError> {
    let trimmed = notation.trim();
    if let Some(rest) = trimmed.strip_prefix('x') {
        let action =
            decode_legal(rules, snap, &format!("x{rest}")).ok_or(HumanTurnError::CaptureInvalid)?;
        return Ok(HumanTurn::CaptureOnly(action));
    }
    match trimmed.split_once('x') {
        None => {
            let action = decode_legal(rules, snap, trimmed).ok_or(HumanTurnError::BaseInvalid)?;
            Ok(HumanTurn::BaseOnly(action))
        }
        Some((base_text, capture_text)) => {
            let base = decode_legal(rules, snap, base_text).ok_or(HumanTurnError::BaseInvalid)?;
            let after_base = rules.apply(snap, base);
            let after_state = MillRules::decode_snapshot(after_base);
            let side = after_state.side_to_move();
            let base_state = MillRules::decode_snapshot(*snap);
            let pending = side >= 0
                && side == base_state.side_to_move()
                && after_state.pending_removals()[side as usize] > 0;
            if !pending {
                return Err(HumanTurnError::UnexpectedCapture);
            }
            let capture = decode_legal(rules, &after_base, &format!("x{capture_text}"))
                .ok_or(HumanTurnError::CaptureInvalid)?;
            Ok(HumanTurn::BaseThenCapture { base, capture })
        }
    }
}

fn decode_legal(rules: &MillRules, snap: &GameStateSnapshot, text: &str) -> Option<Action> {
    let action = MillUciCodec::decode_action(snap, text)?;
    let mut legal = tgf_core::ActionList::<256>::new();
    rules.legal_actions(snap, &mut legal);
    legal.as_slice().iter().copied().find(|&a| a == action)
}

#[cfg(test)]
#[path = "human_db_codec_tests.rs"]
mod tests;
