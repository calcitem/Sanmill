// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_state_reader.dart
//
// Provides a clean API for reading the current game state from
// GameController in integration tests. Encapsulates all direct access
// to the game engine internals.

// ignore_for_file: avoid_print

import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

/// Read-only facade over the game engine state for test code.
class GameStateReader {
  // -- Phase & Action -------------------------------------------------------

  /// Current game phase (ready, placing, moving, gameOver).
  static Phase get phase => GameController().position.phase;

  /// Current required action (place, select, remove).
  static Act get action => GameController().position.action;

  /// The side (color) whose turn it is.
  static PieceColor get sideToMove => GameController().position.sideToMove;

  /// Winner of the game (nobody if still in progress).
  static PieceColor get winner => GameController().position.winner;

  /// Current game mode (humanVsAi, humanVsHuman, aiVsAi, …).
  static GameMode get gameMode =>
      GameController().gameInstance.gameMode;

  /// True when the game has ended.
  static bool get isGameOver => phase == Phase.gameOver;

  /// True when it is the placing phase.
  static bool get isPlacing => phase == Phase.placing;

  /// True when it is the moving phase.
  static bool get isMoving => phase == Phase.moving;

  /// True when the current action is to remove an opponent's piece.
  static bool get isRemoving => action == Act.remove;

  // -- Piece counts ---------------------------------------------------------

  /// Number of pieces on the board for each color.
  static int pieceOnBoardCount(PieceColor color) =>
      GameController().position.pieceOnBoardCount[color] ?? 0;

  /// Number of pieces still in hand (not yet placed) for each color.
  static int pieceInHandCount(PieceColor color) =>
      GameController().position.pieceInHandCount[color] ?? 0;

  /// The configured number of pieces per player for the current rule set.
  static int get piecesCount => DB().ruleSettings.piecesCount;

  /// The fly piece count threshold from the current rule set.
  static int get flyPieceCount => DB().ruleSettings.flyPieceCount;

  /// Whether the current side can fly (has few enough pieces).
  static bool get canCurrentSideFly {
    if (!DB().ruleSettings.mayFly) return false;
    final int count = pieceOnBoardCount(sideToMove);
    return count <= flyPieceCount && count >= 3;
  }

  // -- Board state ----------------------------------------------------------

  /// Get the piece color at a given square (8-31).
  ///
  /// Returns [PieceColor.none] if the square is empty.
  /// Note: Position.pieceOnGrid() takes a grid index (0-48), not a square
  /// number, so we convert via squareToIndex first.
  static PieceColor pieceAt(int square) {
    final int? gridIndex = squareToIndex[square];
    if (gridIndex == null) return PieceColor.none;
    return GameController().position.pieceOnGrid(gridIndex);
  }

  /// List of all empty squares on the board.
  static List<int> get emptySquares {
    final List<int> result = <int>[];
    for (final int sq in squareToIndex.keys) {
      if (pieceAt(sq) == PieceColor.none) {
        result.add(sq);
      }
    }
    return result;
  }

  /// List of squares occupied by the given color.
  static List<int> occupiedSquares(PieceColor color) {
    final List<int> result = <int>[];
    for (final int sq in squareToIndex.keys) {
      if (pieceAt(sq) == color) {
        result.add(sq);
      }
    }
    return result;
  }

  /// List of squares occupied by the current side to move.
  static List<int> get currentSideSquares => occupiedSquares(sideToMove);

  /// List of squares occupied by the opponent.
  static List<int> get opponentSquares => occupiedSquares(sideToMove.opponent);

  // -- Adjacency ------------------------------------------------------------

  /// Adjacency table for the standard board (no diagonal lines).
  /// Index = square number (0-31); value = list of adjacent squares (0 = unused).
  static const List<List<int>> _adjacentSquares = <List<int>>[
    /*  0 */ <int>[0, 0, 0, 0],
    /*  1 */ <int>[0, 0, 0, 0],
    /*  2 */ <int>[0, 0, 0, 0],
    /*  3 */ <int>[0, 0, 0, 0],
    /*  4 */ <int>[0, 0, 0, 0],
    /*  5 */ <int>[0, 0, 0, 0],
    /*  6 */ <int>[0, 0, 0, 0],
    /*  7 */ <int>[0, 0, 0, 0],
    /*  8 */ <int>[16, 9, 15, 0],
    /*  9 */ <int>[10, 8, 0, 0],
    /* 10 */ <int>[18, 11, 9, 0],
    /* 11 */ <int>[12, 10, 0, 0],
    /* 12 */ <int>[20, 13, 11, 0],
    /* 13 */ <int>[14, 12, 0, 0],
    /* 14 */ <int>[22, 15, 13, 0],
    /* 15 */ <int>[8, 14, 0, 0],
    /* 16 */ <int>[8, 24, 17, 23],
    /* 17 */ <int>[18, 16, 0, 0],
    /* 18 */ <int>[10, 26, 19, 17],
    /* 19 */ <int>[20, 18, 0, 0],
    /* 20 */ <int>[12, 28, 21, 19],
    /* 21 */ <int>[22, 20, 0, 0],
    /* 22 */ <int>[14, 30, 23, 21],
    /* 23 */ <int>[16, 22, 0, 0],
    /* 24 */ <int>[16, 25, 31, 0],
    /* 25 */ <int>[26, 24, 0, 0],
    /* 26 */ <int>[18, 27, 25, 0],
    /* 27 */ <int>[28, 26, 0, 0],
    /* 28 */ <int>[20, 29, 27, 0],
    /* 29 */ <int>[30, 28, 0, 0],
    /* 30 */ <int>[22, 31, 29, 0],
    /* 31 */ <int>[24, 30, 0, 0],
  ];

  /// Adjacency table for the board with diagonal lines.
  static const List<List<int>> _adjacentSquaresDiagonal = <List<int>>[
    /*  0 */ <int>[0, 0, 0, 0],
    /*  1 */ <int>[0, 0, 0, 0],
    /*  2 */ <int>[0, 0, 0, 0],
    /*  3 */ <int>[0, 0, 0, 0],
    /*  4 */ <int>[0, 0, 0, 0],
    /*  5 */ <int>[0, 0, 0, 0],
    /*  6 */ <int>[0, 0, 0, 0],
    /*  7 */ <int>[0, 0, 0, 0],
    /*  8 */ <int>[9, 15, 16, 0],
    /*  9 */ <int>[17, 8, 10, 0],
    /* 10 */ <int>[9, 11, 18, 0],
    /* 11 */ <int>[19, 10, 12, 0],
    /* 12 */ <int>[11, 13, 20, 0],
    /* 13 */ <int>[21, 12, 14, 0],
    /* 14 */ <int>[13, 15, 22, 0],
    /* 15 */ <int>[23, 8, 14, 0],
    /* 16 */ <int>[17, 23, 8, 24],
    /* 17 */ <int>[9, 25, 16, 18],
    /* 18 */ <int>[17, 19, 10, 26],
    /* 19 */ <int>[11, 27, 18, 20],
    /* 20 */ <int>[19, 21, 12, 28],
    /* 21 */ <int>[13, 29, 20, 22],
    /* 22 */ <int>[21, 23, 14, 30],
    /* 23 */ <int>[15, 31, 16, 22],
    /* 24 */ <int>[25, 31, 16, 0],
    /* 25 */ <int>[17, 24, 26, 0],
    /* 26 */ <int>[25, 27, 18, 0],
    /* 27 */ <int>[19, 26, 28, 0],
    /* 28 */ <int>[27, 29, 20, 0],
    /* 29 */ <int>[21, 28, 30, 0],
    /* 30 */ <int>[22, 31, 29, 0],
    /* 31 */ <int>[24, 30, 0, 0],
  ];

  /// Get adjacent squares for the given square.
  ///
  /// Respects the current rule set (diagonal lines or not).
  static List<int> adjacentSquaresOf(int square) {
    final List<List<int>> table = DB().ruleSettings.hasDiagonalLines
        ? _adjacentSquaresDiagonal
        : _adjacentSquares;
    if (square < 0 || square >= table.length) {
      return <int>[];
    }
    return table[square].where((int s) => s != 0).toList();
  }

  /// Get adjacent empty squares for the given square.
  static List<int> adjacentEmptySquaresOf(int square) {
    return adjacentSquaresOf(square)
        .where((int s) => pieceAt(s) == PieceColor.none)
        .toList();
  }

  /// Find pieces of the given color that have at least one adjacent empty
  /// square (i.e., pieces that can potentially move).
  static List<int> movablePieces(PieceColor color) {
    return occupiedSquares(color)
        .where((int sq) => adjacentEmptySquaresOf(sq).isNotEmpty)
        .toList();
  }

  // -- Move history ---------------------------------------------------------

  /// The move history as a text string.
  static String get moveHistoryText =>
      GameController().gameRecorder.moveHistoryText;

  /// Number of moves played so far.
  static int get moveCount =>
      GameController().gameRecorder.mainlineMoves.length;

  // -- Debug ----------------------------------------------------------------

  /// Print a snapshot of the current game state for logging.
  static void printState() {
    print('[GameState] phase=$phase action=$action '
        'sideToMove=$sideToMove winner=$winner '
        'mode=$gameMode');
    print('[GameState] White: board=${pieceOnBoardCount(PieceColor.white)} '
        'hand=${pieceInHandCount(PieceColor.white)}');
    print('[GameState] Black: board=${pieceOnBoardCount(PieceColor.black)} '
        'hand=${pieceInHandCount(PieceColor.black)}');
    print('[GameState] moves=$moveCount empty=${emptySquares.length}');
  }
}
