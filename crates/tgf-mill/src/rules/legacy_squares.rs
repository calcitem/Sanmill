// SPDX-License-Identifier: GPL-3.0-or-later
// Bidirectional mapping between Rust dense node ids (0..24) and the
// legacy C++ engine's `Square` enum (`SQ_8`..`SQ_31`).
//
// Used by FEN import / export (`super::set_from_fen` / `super::export_fen`)
// and by any helper that needs to surface a square id in the legacy
// bit-layout (e.g. the FEN field-14 formed-mills bitmask).

/// Convert a legacy C++ `Square` enum value (8..32) to a Rust dense node
/// id (0..24).  Returns `-1` when the legacy id is `0` (i.e. SQ_NONE) so
/// the result lines up with `MillState::last_mill_from/to` semantics.
pub(super) fn legacy_square_to_node_signed(legacy: u8) -> i8 {
    if legacy == 0 || !(8..32).contains(&legacy) {
        return -1;
    }
    const FEN_TO_NODE: [usize; 24] = [
        17, 18, 19, 20, 21, 22, 23, 16, 9, 10, 11, 12, 13, 14, 15, 8, 1, 2, 3, 4, 5, 6, 7, 0,
    ];
    FEN_TO_NODE[(legacy - 8) as usize] as i8
}

/// Inverse of [`legacy_square_to_node_signed`].  `-1` (no last mill) is
/// emitted as `0` to round-trip C++ FEN, which uses `0` for "none".
pub(super) fn node_to_legacy_square(node: i8) -> u8 {
    if !(0..24).contains(&node) {
        return 0;
    }
    const NODE_TO_FEN_POS: [usize; 24] = [
        23, 16, 17, 18, 19, 20, 21, 22, 15, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6,
    ];
    (NODE_TO_FEN_POS[node as usize] + 8) as u8
}

/// Translate a square bitmap expressed in legacy C++ Square ids (bits
/// 8..32 set, bits 0..8 unused) into the equivalent Rust dense node id
/// bitmap.  Used by `set_from_fen` to re-import the FEN field-14 mills
/// bitmask.
pub(super) fn legacy_square_bb_to_node_bb(legacy_bb: u32) -> u32 {
    let mut node_bb = 0_u32;
    for legacy_sq in 8_u8..32 {
        if (legacy_bb & (1u32 << legacy_sq)) != 0 {
            let node = legacy_square_to_node_signed(legacy_sq);
            if (0..24).contains(&node) {
                node_bb |= 1u32 << (node as u8);
            }
        }
    }
    node_bb
}

/// Inverse of [`legacy_square_bb_to_node_bb`].  Used by `export_fen` to
/// emit the FEN field-14 mills bitmask in the legacy bit layout.
pub(super) fn node_bb_to_legacy_square_bb(node_bb: u32) -> u32 {
    let mut legacy_bb = 0_u32;
    for node in 0_u8..24 {
        if (node_bb & (1u32 << node)) != 0 {
            let legacy_sq = node_to_legacy_square(node as i8);
            legacy_bb |= 1u32 << legacy_sq;
        }
    }
    legacy_bb
}
