// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Mill-specific adapter that maps a `tgf-mill` board state onto the perfect
//! database's bitboard encoding and returns the best-move notation token.
//!
//! Both the Flutter bridge (`tgf-frb`) and the headless CLI (`tgf-cli`)
//! consume this helper so the node-to-perfect-index mapping lives in exactly
//! one place.  Each caller matches the returned token against its own legal
//! action list (using the shared `tgf_mill::MillUciCodec`).

use std::sync::OnceLock;

use tgf_mill::rules::MillState;
use tgf_mill::{MillVariantOptions, default_mill_topology};

/// C++ `Square` ids returned by Malom's `from_perfect_square` for perfect
/// indices 0..24.  The mapping itself is recovered from the Mill topology at
/// runtime (see [`node_to_perfect_index`]); this table only encodes the
/// fixed perfect-index → C++ Square relationship from the original engine.
const PERFECT_TO_SQUARE: [u16; 24] = [
    30, 31, 24, 25, 26, 27, 28, 29, 22, 23, 16, 17, 18, 19, 20, 21, 14, 15, 8, 9, 10, 11, 12, 13,
];

static NODE_TO_PERFECT: OnceLock<[u8; 24]> = OnceLock::new();

/// Build (and cache) the `node_id -> perfect_index` lookup by reverse-mapping
/// the canonical Mill topology's `square` field through [`PERFECT_TO_SQUARE`].
fn node_to_perfect_index() -> &'static [u8; 24] {
    NODE_TO_PERFECT.get_or_init(|| {
        let topo = default_mill_topology();
        let mut map = [0u8; 24];
        for (perfect_idx, &square) in PERFECT_TO_SQUARE.iter().enumerate() {
            let node = topo
                .nodes()
                .iter()
                .find(|n| n.square == square)
                .map(|n| n.id as u8)
                .unwrap_or_else(|| {
                    panic!("topology missing square {square} for perfect index {perfect_idx}")
                });
            map[node as usize] = perfect_idx as u8;
        }
        map
    })
}

fn bitboards_from_state(state: &MillState) -> (u32, u32) {
    let node_map = node_to_perfect_index();
    let mut white_bits = 0u32;
    let mut black_bits = 0u32;
    for (node, &occupant) in state.board().iter().enumerate() {
        let perfect_idx = node_map[node];
        let mask = 1u32 << perfect_idx;
        match occupant {
            1 => white_bits |= mask,
            2 => black_bits |= mask,
            _ => {}
        }
    }
    (white_bits, black_bits)
}

/// Query the perfect database for the best move in `state`, returned as a Mill
/// UCI notation token (`"a4"`, `"a1-a4"`, `"xg7"`).
///
/// Returns `None` when the database is not initialized, the variant is not the
/// standard 9-piece game (the only bundled dataset), the side to move is
/// invalid, or the database has no entry for the position.  Callers match the
/// token against their own legal action list.
pub fn best_move_token_for_state(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<String> {
    if options.piece_count != 9 || !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }

    let (white_bits, black_bits) = bitboards_from_state(state);
    let in_hand = state.pieces_in_hand();
    let pending = state.pending_removals();
    let only_stone_taking = pending[side_to_move as usize] > 0;

    crate::best_move_token(
        white_bits,
        black_bits,
        in_hand[0],
        in_hand[1],
        side_to_move as u8,
        only_stone_taking,
    )
}

/// Evaluate `state` through the perfect database, returning `(wdl, steps)`
/// from the perspective of `side_to_move` (`wdl`: 1 = win, 0 = draw,
/// -1 = loss; `steps`: distance-to-conversion, or a negative value when the
/// database does not expose a step count).
///
/// Returns `None` under the same conditions as [`best_move_token_for_state`]:
/// the database is not initialized, the variant is not the standard 9-piece
/// game, the side to move is invalid, or the position has no entry.  This is
/// the per-move primitive consumed by the analysis overlay, which evaluates
/// the position that results from each candidate move.
pub fn evaluate_state_for(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Option<(i32, i32)> {
    if options.piece_count != 9 || !crate::is_initialized() {
        return None;
    }
    if side_to_move != 0 && side_to_move != 1 {
        return None;
    }

    let (white_bits, black_bits) = bitboards_from_state(state);
    let in_hand = state.pieces_in_hand();
    let pending = state.pending_removals();
    let only_stone_taking = pending[side_to_move as usize] > 0;

    crate::evaluate(
        white_bits,
        black_bits,
        in_hand[0],
        in_hand[1],
        side_to_move as u8,
        only_stone_taking,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn perfect_index_labels_match_topology() {
        let expected = [
            "a4", "a7", "d7", "g7", "g4", "g1", "d1", "a1", "b4", "b6", "d6", "f6", "f4", "f2",
            "d2", "b2", "c4", "c5", "d5", "e5", "e4", "e3", "d3", "c3",
        ];
        let topo = default_mill_topology();
        for (perfect_idx, &square) in PERFECT_TO_SQUARE.iter().enumerate() {
            let node = topo
                .nodes()
                .iter()
                .find(|n| n.square == square)
                .unwrap_or_else(|| panic!("missing square {square}"));
            assert_eq!(
                node.label, expected[perfect_idx],
                "perfect index {perfect_idx}"
            );
        }
    }
}
