// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Mill-specific accessors for [GameStateSnapshot.payload] populated by
// [NativeMillRulesPort] / [TgfKernel].

import 'game_session.dart';

/// Reads Rust-backed Mill extras from a generic [GameStateSnapshot].
extension GameStateSnapshotMillExt on GameStateSnapshot {
  /// Node indices `0..23` marked for
  /// `MillFormationActionInPlacingPhase.markAndDelayRemovingPieces`
  /// (from `MillState.delayed_marked_pieces` via codec).
  Set<int> get millMarkedNodes {
    final Object? raw = payload['millMarkedNodes'];
    if (raw is Set<int>) {
      return raw;
    }
    if (raw is Set) {
      return raw.cast<int>().toSet();
    }
    return <int>{};
  }
}
