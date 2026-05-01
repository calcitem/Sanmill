// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import '../../game_platform/game_session.dart';
import '../../game_platform/mill_marked_pieces_codec.dart';
import 'mill_board_coordinate_maps.dart';

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
  static const int usedMillLinesByteOffset = 35;

  final Uint8List _payload;
  final Set<int> markedNodes;

  PlayerSeat? pieceAtLegacySquare(int square) {
    final int? node = MillBoardCoordinateMaps.legacySquareToNode[square];
    return node == null ? null : pieceAtNode(node);
  }

  PlayerSeat? pieceAtLegacyGridIndex(int gridIndex) {
    final int? square = MillBoardCoordinateMaps.gridIndexToSquare[gridIndex];
    return square == null ? null : pieceAtLegacySquare(square);
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
    final int? node = MillBoardCoordinateMaps.legacySquareToNode[square];
    return node != null && markedNodes.contains(node);
  }

  bool isMarkedLegacyGridIndex(int gridIndex) {
    final int? square = MillBoardCoordinateMaps.gridIndexToSquare[gridIndex];
    return square != null && isMarkedLegacySquare(square);
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

  int pieceCount(PlayerSeat seat) {
    if (seat == PlayerSeat.none) {
      return 0;
    }
    int count = 0;
    for (int node = 0; node < nodeCount; node++) {
      if (pieceAtNode(node) == seat) {
        count++;
      }
    }
    return count;
  }

  Map<PlayerSeat, List<List<int>>> usedMillLinesAsLegacySquares({
    required bool hasDiagonalLines,
  }) {
    final Map<PlayerSeat, List<List<int>>> out = <PlayerSeat, List<List<int>>>{
      PlayerSeat.first: <List<int>>[],
      PlayerSeat.second: <List<int>>[],
    };
    if (_payload.length < usedMillLinesByteOffset + 4) {
      return out;
    }
    const int o = usedMillLinesByteOffset;
    final int bits =
        _payload[o] |
        (_payload[o + 1] << 8) |
        (_payload[o + 2] << 16) |
        (_payload[o + 3] << 24);
    final List<List<int>> lines = hasDiagonalLines
        ? _diagonalMillLines
        : _standardMillLines;
    for (int i = 0; i < lines.length; i++) {
      if ((bits & (1 << i)) == 0) {
        continue;
      }
      final List<int> line = lines[i];
      final PlayerSeat? owner = pieceAtNode(line[0]);
      if (owner == null ||
          owner == PlayerSeat.none ||
          line.any((int node) => pieceAtNode(node) != owner)) {
        continue;
      }
      out[owner]!.add(<int>[
        for (final int node in line)
          MillBoardCoordinateMaps.nodeToLegacySquare[node]!,
      ]);
    }
    return out;
  }

  static const List<List<int>> _standardMillLines = <List<int>>[
    <int>[0, 1, 2],
    <int>[2, 3, 4],
    <int>[4, 5, 6],
    <int>[6, 7, 0],
    <int>[8, 9, 10],
    <int>[10, 11, 12],
    <int>[12, 13, 14],
    <int>[14, 15, 8],
    <int>[16, 17, 18],
    <int>[18, 19, 20],
    <int>[20, 21, 22],
    <int>[22, 23, 16],
    <int>[1, 9, 17],
    <int>[3, 11, 19],
    <int>[5, 13, 21],
    <int>[7, 15, 23],
  ];

  static const List<List<int>> _diagonalMillLines = <List<int>>[
    ..._standardMillLines,
    <int>[0, 8, 16],
    <int>[18, 10, 2],
    <int>[6, 14, 22],
    <int>[20, 12, 4],
  ];
}
