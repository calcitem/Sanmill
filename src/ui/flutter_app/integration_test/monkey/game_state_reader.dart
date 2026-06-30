// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_state_reader.dart
//
// Read-only facade over [GameController.activeBoardView] for integration
// tests.  Migrated from master `integration_test/monkey/game_state_reader.dart`
// (legacy `Position`).

// ignore_for_file: avoid_print

import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/shared/database/database.dart';

/// Read-only facade over the native session board view for test code.
class GameStateReader {
  const GameStateReader._();

  static GameController get _controller => GameController();

  static MillBoardView get _board => _controller.activeBoardView;

  static Phase get phase => _board.phase;

  static Act get action {
    final PieceColor side = _board.sideToMove;
    if (_board.pieceToRemoveCountFor(side) > 0) {
      return Act.remove;
    }
    if (phase == Phase.moving) {
      final NativeMillGameSession? session =
          _controller.activeNativeMillSession;
      if (session != null &&
          session.legalActions.any(
            (GameAction action) => action.type == MillActionTypes.move,
          )) {
        return Act.select;
      }
    }
    return Act.place;
  }

  static PieceColor get sideToMove => _board.sideToMove;

  static PieceColor get winner => _board.winner;

  static GameMode get gameMode => _controller.gameInstance.gameMode;

  static bool get isGameOver => _board.isGameOver;

  static bool get isPlacing => phase == Phase.placing;

  static bool get isMoving => phase == Phase.moving;

  static bool get isRemoving => action == Act.remove;

  static int pieceOnBoardCount(PieceColor color) =>
      _board.pieceOnBoardCountFor(color);

  static int pieceInHandCount(PieceColor color) =>
      _board.pieceInHandCountFor(color);

  static int get piecesCount => DB().ruleSettings.piecesCount;

  static int get flyPieceCount => DB().ruleSettings.flyPieceCount;

  static bool get canCurrentSideFly {
    if (!DB().ruleSettings.mayFly) {
      return false;
    }
    final int count = pieceOnBoardCount(sideToMove);
    return count <= flyPieceCount && count >= 3;
  }

  static PieceColor pieceAt(int square) {
    final int? gridIndex = squareToIndex[square];
    if (gridIndex == null) {
      return PieceColor.none;
    }
    return _board.pieceOnGrid(gridIndex);
  }

  static List<int> get emptySquares {
    final List<int> result = <int>[];
    for (final int sq in squareToIndex.keys) {
      if (pieceAt(sq) == PieceColor.none) {
        result.add(sq);
      }
    }
    return result;
  }

  static List<int> occupiedSquares(PieceColor color) {
    final List<int> result = <int>[];
    for (final int sq in squareToIndex.keys) {
      if (pieceAt(sq) == color) {
        result.add(sq);
      }
    }
    return result;
  }

  static List<int> get currentSideSquares => occupiedSquares(sideToMove);

  static List<int> get opponentSquares => occupiedSquares(sideToMove.opponent);

  static const List<List<int>> _adjacentSquares = <List<int>>[
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[16, 9, 15, 0],
    <int>[10, 8, 0, 0],
    <int>[18, 11, 9, 0],
    <int>[12, 10, 0, 0],
    <int>[20, 13, 11, 0],
    <int>[14, 12, 0, 0],
    <int>[22, 15, 13, 0],
    <int>[8, 14, 0, 0],
    <int>[8, 24, 17, 23],
    <int>[18, 16, 0, 0],
    <int>[10, 26, 19, 17],
    <int>[20, 18, 0, 0],
    <int>[12, 28, 21, 19],
    <int>[22, 20, 0, 0],
    <int>[14, 30, 23, 21],
    <int>[16, 22, 0, 0],
    <int>[16, 25, 31, 0],
    <int>[26, 24, 0, 0],
    <int>[18, 27, 25, 0],
    <int>[28, 26, 0, 0],
    <int>[20, 29, 27, 0],
    <int>[30, 28, 0, 0],
    <int>[22, 31, 29, 0],
    <int>[24, 30, 0, 0],
  ];

  static const List<List<int>> _adjacentSquaresDiagonal = <List<int>>[
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[0, 0, 0, 0],
    <int>[9, 15, 16, 0],
    <int>[17, 8, 10, 0],
    <int>[9, 11, 18, 0],
    <int>[19, 10, 12, 0],
    <int>[11, 13, 20, 0],
    <int>[21, 12, 14, 0],
    <int>[13, 15, 22, 0],
    <int>[23, 8, 14, 0],
    <int>[17, 23, 8, 24],
    <int>[9, 25, 16, 18],
    <int>[17, 19, 10, 26],
    <int>[19, 21, 12, 28],
    <int>[12, 28, 21, 19],
    <int>[13, 29, 20, 22],
    <int>[14, 30, 23, 21],
    <int>[15, 31, 16, 22],
    <int>[25, 31, 16, 0],
    <int>[17, 24, 26, 0],
    <int>[25, 27, 18, 0],
    <int>[19, 26, 28, 0],
    <int>[27, 29, 20, 0],
    <int>[21, 28, 30, 0],
    <int>[22, 31, 29, 0],
    <int>[24, 30, 0, 0],
  ];

  static List<int> adjacentSquaresOf(int square) {
    final List<List<int>> table = DB().ruleSettings.hasDiagonalLines
        ? _adjacentSquaresDiagonal
        : _adjacentSquares;
    if (square < 0 || square >= table.length) {
      return <int>[];
    }
    return table[square].where((int s) => s != 0).toList();
  }

  static List<int> adjacentEmptySquaresOf(int square) {
    return adjacentSquaresOf(
      square,
    ).where((int s) => pieceAt(s) == PieceColor.none).toList();
  }

  static List<int> movablePieces(PieceColor color) {
    return occupiedSquares(
      color,
    ).where((int sq) => adjacentEmptySquaresOf(sq).isNotEmpty).toList();
  }

  static String get moveHistoryText => _controller.gameRecorder.moveHistoryText;

  static int get moveCount => _controller.gameRecorder.mainlineMoves.length;

  static void printState() {
    print(
      '[GameState] phase=$phase action=$action '
      'sideToMove=$sideToMove winner=$winner mode=$gameMode',
    );
    print(
      '[GameState] White: board=${pieceOnBoardCount(PieceColor.white)} '
      'hand=${pieceInHandCount(PieceColor.white)}',
    );
    print(
      '[GameState] Black: board=${pieceOnBoardCount(PieceColor.black)} '
      'hand=${pieceInHandCount(PieceColor.black)}',
    );
    print('[GameState] moves=$moveCount empty=${emptySquares.length}');
  }
}
