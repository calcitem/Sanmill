// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_view.dart
//
// MillBoardView — a read-only snapshot of the current board state for
// display and analysis purposes.
//
// Phase 6.C.2.a: this class is the LONG-TERM replacement for the public
// read-only API currently exposed by the legacy `Position` class.  During
// the transition it is populated from the active native session snapshot
// when `useNativeMillSession` is true, and from the legacy `Position`
// otherwise.  Callers are migrated to use `MillBoardView` in Phase 6.C.2.b;
// `Position` rule methods are deleted in Phase 6.C.2.c.

part of '../mill.dart';

/// Lightweight read-only board view.
///
/// Constructed from a `GameStateSnapshot` (native path) or a `Position`
/// (legacy path).  Consumers should read through this class rather than
/// accessing `GameController().position` directly so that the underlying
/// source can be switched without changing call sites.
class MillBoardView {
  const MillBoardView._({
    required this.phase,
    required this.action,
    required this.sideToMove,
    required this.pieceOnBoardCount,
    required this.pieceInHandCount,
    required this.pieceToRemoveCount,
    required this.winner,
    required this.fen,
    required PieceColor Function(int) pieceAtFn,
    required this.markedGridIndices,
    required this.isNative,
  }) : _pieceAt = pieceAtFn;

  /// Construct from the active [NativeMillGameSession] snapshot.
  ///
  /// Returns null when the snapshot payload is missing or invalid.
  static MillBoardView? fromNativeSnapshot(
    GameStateSnapshot snapshot,
    String? exportedFen,
  ) {
    final Object? raw = snapshot.payload['tgfPayload'];
    if (raw is! Uint8List || raw.length < 24) {
      return null;
    }
    // Bytes 0..23 = node occupancy; bytes 24-25 = pieces in hand;
    // bytes 26-27 = pieces on board; bytes 28-29 = pending removals.
    final int pInHand0 = raw[24];
    final int pInHand1 = raw[25];
    final int pOnBoard0 = raw[26];
    final int pOnBoard1 = raw[27];
    final int pRemove0 = raw[28];
    final int pRemove1 = raw[29];
    final int winnerByte = raw[30];
    final PieceColor winner = switch (winnerByte) {
      1 => PieceColor.white,
      2 => PieceColor.black,
      _ => PieceColor.nobody,
    };

    final Set<int> markedNodes =
        MillMarkedPiecesCodec.markedNodesFromOpaquePayload(raw);

    // Convert marked nodes to legacy grid indices for compatibility with the
    // board rendering layer that currently indexes by grid position.
    final Set<int> markedGrids = <int>{};
    for (final int node in markedNodes) {
      final int? sq = MillBoardCoordinateMaps.nodeToLegacySquare[node];
      if (sq != null) {
        final int? gi = MillBoardCoordinateMaps.squareToGridIndex[sq];
        if (gi != null) {
          markedGrids.add(gi);
        }
      }
    }

    return MillBoardView._(
      phase: switch (snapshot.phase) {
        'placing' => Phase.placing,
        'moving' => Phase.moving,
        'gameOver' => Phase.gameOver,
        _ => Phase.ready,
      },
      action: (pRemove0 > 0 || pRemove1 > 0) ? Act.remove : Act.place,
      sideToMove: switch (snapshot.activeSeat) {
        PlayerSeat.first => PieceColor.white,
        PlayerSeat.second => PieceColor.black,
        _ => PieceColor.nobody,
      },
      pieceOnBoardCount: <PieceColor, int>{
        PieceColor.white: pOnBoard0,
        PieceColor.black: pOnBoard1,
      },
      pieceInHandCount: <PieceColor, int>{
        PieceColor.white: pInHand0,
        PieceColor.black: pInHand1,
      },
      pieceToRemoveCount: <PieceColor, int>{
        PieceColor.white: pRemove0,
        PieceColor.black: pRemove1,
      },
      winner: winner,
      fen: exportedFen,
      pieceAtFn: (int gridIndex) {
        final int? sq = MillBoardCoordinateMaps.gridIndexToSquare[gridIndex];
        if (sq == null) {
          return PieceColor.none;
        }
        final int? node = MillBoardCoordinateMaps.legacySquareToNode[sq];
        if (node == null || node >= 24) {
          return PieceColor.none;
        }
        return switch (raw[node]) {
          1 => PieceColor.white,
          2 => PieceColor.black,
          _ => PieceColor.none,
        };
      },
      markedGridIndices: markedGrids,
      isNative: true,
    );
  }

  /// Empty placeholder board view used at very-early init before the
  /// native session is bound.  Returns "ready" phase, both-sides-zero
  /// counts, and `PieceColor.none` for every grid index.
  static MillBoardView empty() {
    return MillBoardView._(
      phase: Phase.ready,
      action: Act.place,
      sideToMove: PieceColor.white,
      pieceOnBoardCount: const <PieceColor, int>{
        PieceColor.white: 0,
        PieceColor.black: 0,
      },
      pieceInHandCount: const <PieceColor, int>{
        PieceColor.white: 0,
        PieceColor.black: 0,
      },
      pieceToRemoveCount: const <PieceColor, int>{
        PieceColor.white: 0,
        PieceColor.black: 0,
      },
      winner: PieceColor.nobody,
      fen: null,
      pieceAtFn: (int _) => PieceColor.none,
      markedGridIndices: const <int>{},
      isNative: false,
    );
  }

  // ---- Fields ----------------------------------------------------------------

  final Phase phase;
  final Act action;
  final PieceColor sideToMove;
  final Map<PieceColor, int> pieceOnBoardCount;
  final Map<PieceColor, int> pieceInHandCount;
  final Map<PieceColor, int> pieceToRemoveCount;
  final PieceColor winner;

  /// FEN string for the current position, or null when unavailable.
  final String? fen;

  final PieceColor Function(int gridIndex) _pieceAt;

  /// Grid indices (legacy 7×7 coordinate system) of marked delayed-removal
  /// pieces.
  final Set<int> markedGridIndices;

  /// True when this view was built from a native session snapshot.
  final bool isNative;

  // ---- Derived helpers -------------------------------------------------------

  /// Returns the piece at the given legacy grid index.
  PieceColor pieceOnGrid(int gridIndex) => _pieceAt(gridIndex);

  bool get isGameOver => phase == Phase.gameOver;

  bool get isWhiteTurn => sideToMove == PieceColor.white;

  int pieceOnBoardCountFor(PieceColor color) => pieceOnBoardCount[color] ?? 0;

  int pieceInHandCountFor(PieceColor color) => pieceInHandCount[color] ?? 0;

  int pieceToRemoveCountFor(PieceColor color) => pieceToRemoveCount[color] ?? 0;
}
