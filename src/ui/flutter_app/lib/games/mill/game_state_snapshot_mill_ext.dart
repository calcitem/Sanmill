// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Mill-specific accessors for [GameStateSnapshot.payload] populated by
// [NativeMillRulesPort] / [TgfKernel] via [MillKernelExtraDecoder].

import '../../game_platform/game_session.dart';
import 'mill_marked_pieces_codec.dart';

/// Reads Rust-backed Mill extras from a generic [GameStateSnapshot].
extension GameStateSnapshotMillExt on GameStateSnapshot {
  /// Node indices `0..23` marked for
  /// `MillFormationActionInPlacingPhase.markAndDelayRemovingPieces`
  /// (from `MillState.delayed_marked_pieces` via [MillMarkedPiecesCodec]).
  Set<int> get millMarkedNodes {
    final Object? raw = payload[millMarkedNodesPayloadKey];
    if (raw is Set<int>) {
      return raw;
    }
    if (raw is Set) {
      return raw.cast<int>().toSet();
    }
    return <int>{};
  }
}
