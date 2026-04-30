// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import '../../game_platform/game_session.dart';
import '../../game_platform/mill_marked_pieces_codec.dart';

/// Read-only board view over the Rust-native Mill opaque payload.
///
/// Layout matches `crates/tgf-mill/src/rules.rs::MillState::encode`:
/// bytes 0..23 store node occupancy (`0` empty, `1` first player, `2`
/// second player).  Marked delayed-removal pieces are read through
/// [MillMarkedPiecesCodec].
class NativeMillSnapshotBoardView {
  NativeMillSnapshotBoardView._(this._payload, this.markedNodes);

  static NativeMillSnapshotBoardView? fromSnapshot(GameStateSnapshot snapshot) {
    final Object? raw = snapshot.payload['tgfPayload'];
    if (raw is! Uint8List || raw.length < nodeCount) {
      return null;
    }
    return NativeMillSnapshotBoardView._(
      raw,
      MillMarkedPiecesCodec.markedNodesFromOpaquePayload(raw),
    );
  }

  static const int nodeCount = 24;

  final Uint8List _payload;
  final Set<int> markedNodes;

  PlayerSeat? pieceAtLegacySquare(int square) {
    final int? node = _legacySquareToNode[square];
    return node == null ? null : pieceAtNode(node);
  }

  PlayerSeat? pieceAtNode(int node) {
    if (node < 0 || node >= nodeCount) {
      return null;
    }
    return switch (_payload[node]) {
      1 => PlayerSeat.first,
      2 => PlayerSeat.second,
      _ => null,
    };
  }

  bool isMarkedLegacySquare(int square) {
    final int? node = _legacySquareToNode[square];
    return node != null && markedNodes.contains(node);
  }

  Map<int, PlayerSeat> occupiedNodes() {
    final Map<int, PlayerSeat> out = <int, PlayerSeat>{};
    for (int node = 0; node < nodeCount; node++) {
      final PlayerSeat? seat = pieceAtNode(node);
      if (seat != null) {
        out[node] = seat;
      }
    }
    return out;
  }

  static const Map<int, int> _legacySquareToNode = <int, int>{
    31: 0,
    24: 1,
    25: 2,
    26: 3,
    27: 4,
    28: 5,
    29: 6,
    30: 7,
    23: 8,
    16: 9,
    17: 10,
    18: 11,
    19: 12,
    20: 13,
    21: 14,
    22: 15,
    15: 16,
    8: 17,
    9: 18,
    10: 19,
    11: 20,
    12: 21,
    13: 22,
    14: 23,
  };
}
