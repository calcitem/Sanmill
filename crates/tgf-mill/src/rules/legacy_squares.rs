// SPDX-License-Identifier: AGPL-3.0-or-later
// Import-side mapping from the legacy C++ engine's `Square` enum
// (`SQ_8`..`SQ_31`) to Rust dense node ids (0..24).
//
// Engine nodes use the master-normalized layout: `node = legacy_square - 8`.
// This keeps Rust arrays compact while preserving master's file/rank bitboard
// geometry and making boundary conversion a shift or add/subtract.
//
// Used by legacy FEN import and by helpers that still need to read a square id
// in the old bit-layout (e.g. the FEN field-14 formed-mills bitmask).

/// Dense node order reached by iterating legacy C++ `Square` ids
/// `SQ_BEGIN..SQ_END`.  In the master-normalized layout this is the identity
/// order and can be used directly for flying destinations.
pub(super) const LEGACY_SQUARE_ORDER_NODES: [usize; 24] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
];

/// Translate a square bitmap expressed in legacy C++ Square ids (bits
/// 8..32 set, bits 0..8 unused) into the equivalent Rust dense node id
/// bitmap.  Used by legacy FEN import for the field-14 mills bitmask.
pub(super) fn legacy_square_bb_to_node_bb(legacy_bb: u32) -> u32 {
    (legacy_bb >> 8) & 0x00ff_ffff
}
