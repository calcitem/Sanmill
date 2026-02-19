// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_tap_helper.dart
//
// Provides utilities for tapping specific board positions in integration tests.
// Converts logical board positions (square numbers, algebraic notation) into
// screen coordinates and performs precise taps on the game board widget.

// ignore_for_file: avoid_print

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

/// All 24 valid board positions as grid-coordinate offsets.
///
/// These correspond to the `points` list in board_utils.dart.
/// Each offset maps to one of the 24 intersections on the board.
const List<Offset> boardPoints = <Offset>[
  Offset.zero, // index 0
  Offset(0, 3), // index 1
  Offset(0, 6), // index 2
  Offset(1, 1), // index 3
  Offset(1, 3), // index 4
  Offset(1, 5), // index 5
  Offset(2, 2), // index 6
  Offset(2, 3), // index 7
  Offset(2, 4), // index 8
  Offset(3, 0), // index 9
  Offset(3, 1), // index 10
  Offset(3, 2), // index 11
  Offset(3, 4), // index 12
  Offset(3, 5), // index 13
  Offset(3, 6), // index 14
  Offset(4, 2), // index 15
  Offset(4, 3), // index 16
  Offset(4, 4), // index 17
  Offset(5, 1), // index 18
  Offset(5, 3), // index 19
  Offset(5, 5), // index 20
  Offset(6, 0), // index 21
  Offset(6, 3), // index 22
  Offset(6, 6), // index 23
];

/// Helper class for tapping specific positions on the game board.
class BoardTapHelper {
  const BoardTapHelper._();
  /// Finder for the game board gesture detector.
  static final Finder _boardFinder = find.byKey(
    const Key('gesture_detector_game_board'),
  );

  /// Tap a board position identified by its engine square number (8-31).
  ///
  /// Computes the screen coordinates for the given square and performs
  /// a tap at that position. Returns true if the tap was performed
  /// successfully, false if the board widget was not found.
  static Future<bool> tapSquare(WidgetTester tester, int square) async {
    if (!_isBoardVisible(tester)) {
      print('[BoardTap] Board widget not found, cannot tap square $square');
      return false;
    }

    final Offset? screenOffset = _screenOffsetForSquare(tester, square);
    if (screenOffset == null) {
      print('[BoardTap] Cannot compute offset for square $square');
      return false;
    }

    await tester.tapAt(screenOffset);
    await tester.pump(const Duration(milliseconds: 50));
    return true;
  }

  /// Tap a board position identified by algebraic notation (e.g. 'a7', 'd5').
  ///
  /// Converts the notation to a square number and delegates to [tapSquare].
  static Future<bool> tapNotation(WidgetTester tester, String notation) async {
    final int square = notationToSquare(notation);
    if (square < 0) {
      print('[BoardTap] Invalid notation: $notation');
      return false;
    }
    return tapSquare(tester, square);
  }

  /// Get all 24 valid square numbers (8-31).
  static List<int> getAllSquares() {
    return squareToIndex.keys.toList();
  }

  /// Check if the game board widget is currently visible.
  static bool _isBoardVisible(WidgetTester tester) {
    return _boardFinder.evaluate().isNotEmpty;
  }

  /// Compute the screen offset for a given square number.
  ///
  /// Uses the same coordinate transformation as the production code to
  /// ensure taps land on the correct board intersections, accounting for
  /// inner ring size scaling.
  static Offset? _screenOffsetForSquare(WidgetTester tester, int square) {
    final int? gridIndex = squareToIndex[square];
    if (gridIndex == null) {
      return null;
    }

    // Find the grid-coordinate Offset for this grid index.
    Offset? gridPoint;
    for (int i = 0; i < boardPoints.length; i++) {
      // Convert board point to the flat 7x7 index:
      // index = row * 7 + col  (where row = dy, col = dx)
      final int flatIndex =
          (boardPoints[i].dy.toInt() * 7) + boardPoints[i].dx.toInt();
      if (flatIndex == gridIndex) {
        gridPoint = boardPoints[i];
        break;
      }
    }

    if (gridPoint == null) {
      return null;
    }

    // Get the board widget's top-left position and size.
    final Offset boardTopLeft = tester.getTopLeft(_boardFinder);
    final Size boardSize = tester.getSize(_boardFinder);

    // Convert grid point to screen offset, mirroring
    // offsetFromPointWithInnerSize() in board_utils.dart.
    final Offset localOffset = _gridPointToLocalOffset(gridPoint, boardSize);

    return boardTopLeft + localOffset;
  }

  /// Convert a grid-coordinate point to a local offset within the board
  /// widget, applying the inner-ring size scaling.
  ///
  /// This mirrors the logic in offsetFromPointWithInnerSize() from
  /// board_utils.dart so that taps match the visual rendering.
  static Offset _gridPointToLocalOffset(Offset point, Size size) {
    final double margin = AppTheme.boardPadding;
    final double innerRingSize = DB().displaySettings.boardInnerRingSize;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double unitDistance = (size.width - margin * 2) / 6;

    // Default (unscaled) position.
    final Offset originalPos = (point * unitDistance) + Offset(margin, margin);
    final Offset vectorFromCenter = originalPos - center;

    // Determine ring index (0=center, 1=inner, 2=middle, 3=outer).
    final int ringOriginal = _ringOf(point);
    if (ringOriginal == 0) {
      return originalPos;
    }

    // Target radial lengths after scaling.
    const double targetOuter = 3.0;
    final double targetInner = innerRingSize;
    final double targetMiddle = (targetOuter + targetInner) / 2.0;

    double targetLen;
    switch (ringOriginal) {
      case 1:
        targetLen = targetInner;
      case 2:
        targetLen = targetMiddle;
      case 3:
      default:
        targetLen = targetOuter;
    }

    final double scaleFactor = targetLen / ringOriginal;
    final Offset scaledVector = vectorFromCenter * scaleFactor;

    return center + scaledVector;
  }

  /// Determine which ring a grid point belongs to.
  ///
  /// Returns 0 (center), 1 (inner), 2 (middle), or 3 (outer).
  static int _ringOf(Offset point) {
    final int dx = (point.dx - 3).abs().toInt().clamp(0, 3);
    final int dy = (point.dy - 3).abs().toInt().clamp(0, 3);
    return dx > dy ? dx : dy;
  }

  /// Perform a tap at a random position on the board (not necessarily a
  /// valid intersection).
  ///
  /// Useful for simulating erratic user behavior in monkey tests.
  static Future<bool> tapRandomBoardArea(WidgetTester tester) async {
    if (!_isBoardVisible(tester)) {
      return false;
    }

    final Offset boardTopLeft = tester.getTopLeft(_boardFinder);
    final Size boardSize = tester.getSize(_boardFinder);

    // Tap somewhere inside the board bounds (random-ish but deterministic
    // for reproducibility in tests).
    final Offset center =
        boardTopLeft + Offset(boardSize.width / 2, boardSize.height / 2);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    return true;
  }
}
