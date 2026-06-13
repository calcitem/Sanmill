// SPDX-License-Identifier: GPL-3.0-or-later
// Perfect-database lookup for Mill positions (Nine Men's Morris std only).

use std::sync::OnceLock;

use tgf_core::Action;
use tgf_mill::{MillRules, MillVariantOptions, default_mill_topology, rules::MillState};

use crate::games::mill::action_codec::action_to_uci_str;

/// C++ `Square` ids returned by `from_perfect_square` for perfect indices 0..24.
const PERFECT_TO_SQUARE: [u16; 24] = [
    30, 31, 24, 25, 26, 27, 28, 29, 22, 23, 16, 17, 18, 19, 20, 21, 14, 15, 8, 9, 10, 11, 12, 13,
];

static NODE_TO_PERFECT: OnceLock<[u8; 24]> = OnceLock::new();

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

/// Query the vendored perfect database for a legal action matching the
/// current position.  Returns `None` when the DB is unavailable, the
/// variant is not std 9-piece, or no legal action matches the DB token.
pub(crate) fn try_perfect_best_action(
    snapshot: &tgf_core::GameStateSnapshot,
    options: &MillVariantOptions,
    legal: &[Action],
) -> Option<Action> {
    if options.piece_count != 9 || !perfect_db::is_initialized() {
        return None;
    }

    let state = MillRules::decode_snapshot(*snapshot);
    let side = snapshot.side_to_move;
    if side != 0 && side != 1 {
        return None;
    }

    let (white_bits, black_bits) = bitboards_from_state(&state);
    let in_hand = state.pieces_in_hand();
    let pending = state.pending_removals();
    let only_stone_taking = pending[side as usize] > 0;

    let token = perfect_db::best_move_token(
        white_bits,
        black_bits,
        in_hand[0],
        in_hand[1],
        side as u8,
        only_stone_taking,
    )?;

    legal
        .iter()
        .copied()
        .find(|action| action_to_uci_str(*action) == token)
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
