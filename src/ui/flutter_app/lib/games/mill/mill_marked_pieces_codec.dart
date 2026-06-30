// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Decode Rust `MillState.delayed_marked_pieces` from `GameStateSnapshot` /
// `TgfSnapshot.opaque_payload`.  Layout matches
// `crates/tgf-mill/src/rules/state_impl.rs::MillState::encode`
// (LE u32 at bytes 39..43).

import 'dart:typed_data';

import '../../game_platform/engine/tgf_kernel_extras.dart';
import '../../game_platform/game_id.dart';

/// Stable map key under which [MillKernelExtraDecoder] publishes the set
/// of currently-marked node ids.
const String millMarkedNodesPayloadKey = 'millMarkedNodes';

/// Stable map key under which the session snapshot carries the
/// outcome-reason token (see `NativeMillRulesPort` and
/// `GameController.forceGameOver`).  The value is the canonical token
/// emitted by the Rust engine or by `GameOverReasonExtension.tgfReason`.
const String millOutcomeReasonPayloadKey = 'tgfOutcomeReason';

/// Extracts marked-piece node ids for
/// `MillFormationActionInPlacingPhase.markAndDelayRemovingPieces`.
abstract final class MillMarkedPiecesCodec {
  MillMarkedPiecesCodec._();

  /// Byte offset of `delayed_marked_pieces` in the Mill opaque payload blob.
  static const int markedPiecesBitfieldByteOffset = 39;

  /// Node indices `0..23` whose bits are set in the delayed-marked bitmask.
  static Set<int> markedNodesFromOpaquePayload(Uint8List payload) {
    if (payload.length < markedPiecesBitfieldByteOffset + 4) {
      return <int>{};
    }
    const int o = markedPiecesBitfieldByteOffset;
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

/// [TgfKernelExtraDecoder] implementation injected by [MillGameModule] so
/// the framework-level [TgfKernel] never has to know about Mill's
/// payload layout.
class MillKernelExtraDecoder implements TgfKernelExtraDecoder {
  const MillKernelExtraDecoder();

  @override
  Map<String, Object?> decode(Uint8List opaquePayload) => <String, Object?>{
    millMarkedNodesPayloadKey:
        MillMarkedPiecesCodec.markedNodesFromOpaquePayload(opaquePayload),
  };
}

/// Convenience hook used by [MillGameModule] to register the decoder at
/// app startup; idempotent (calling twice replaces the previous entry).
void registerMillKernelExtras() {
  TgfKernelExtraRegistry.instance.register(
    GameId.mill,
    const MillKernelExtraDecoder(),
  );
}
