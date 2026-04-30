// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Decode Rust `MillState.delayed_marked_pieces` from `GameStateSnapshot` /
// `TgfSnapshot.opaque_payload`.  Layout matches
// `crates/tgf-mill/src/rules.rs::MillState::encode` (LE u32 at bytes 39..43).

import 'dart:typed_data';

/// Extracts marked-piece node ids for
/// [MillFormationActionInPlacingPhase.markAndDelayRemovingPieces].
abstract final class MillMarkedPiecesCodec {
  MillMarkedPiecesCodec._();

  /// Byte offset of `delayed_marked_pieces` in the Mill opaque payload blob.
  static const int markedPiecesBitfieldByteOffset = 39;

  /// Node indices `0..23` whose bits are set in the delayed-marked bitmask.
  static Set<int> markedNodesFromOpaquePayload(Uint8List payload) {
    if (payload.length < markedPiecesBitfieldByteOffset + 4) {
      return <int>{};
    }
    final int o = markedPiecesBitfieldByteOffset;
    final int bits =
        payload[o] |
        (payload[o + 1] << 8) |
        (payload[o + 2] << 16) |
        (payload[o + 3] << 24);
    final Set<int> out = <int>{};
    for (int i = 0; i < 24; i++) {
      if ((bits & (1 << i)) != 0) {
        out.add(i);
      }
    }
    return out;
  }
}
