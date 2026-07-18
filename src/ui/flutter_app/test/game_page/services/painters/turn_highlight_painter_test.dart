// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../../../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB();
    AppTheme.boardPadding = 28;
  });

  tearDown(() {
    DB.instance = null;
  });

  group('MillTurnHighlight', () {
    test('treats a placement awaiting removal as provisional', () {
      final MillTurnHighlight? highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('a7', side: PieceColor.white),
      ], isRemovalPending: true);

      expect(highlight, isNotNull);
      expect(highlight!.side, PieceColor.white);
      expect(highlight.primaryType, MoveType.place);
      expect(highlight.toSquare, notationToSquare('a7'));
      expect(highlight.removedSquares, isEmpty);
      expect(highlight.isComplete, isFalse);
    });

    test('combines a movement and every removal into one completed turn', () {
      final MillTurnHighlight? highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('d7', side: PieceColor.black),
        ExtMove('a7-d7', side: PieceColor.white),
        ExtMove('xa1', side: PieceColor.white),
        ExtMove('xg1', side: PieceColor.white),
      ], isRemovalPending: false);

      expect(highlight, isNotNull);
      expect(highlight!.primaryType, MoveType.move);
      expect(highlight.fromSquare, notationToSquare('a7'));
      expect(highlight.toSquare, notationToSquare('d7'));
      expect(highlight.removedSquares, <int>[
        notationToSquare('a1'),
        notationToSquare('g1'),
      ]);
      expect(highlight.isComplete, isTrue);
    });

    test('keeps already recorded removals provisional while more are due', () {
      final MillTurnHighlight? highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('d7', side: PieceColor.black),
        ExtMove('a7', side: PieceColor.white),
        ExtMove('xa1', side: PieceColor.white),
      ], isRemovalPending: true);

      expect(highlight, isNotNull);
      expect(highlight!.removedSquares, <int>[notationToSquare('a1')]);
      expect(highlight.isComplete, isFalse);
    });

    test('uses only the latest side turn', () {
      final MillTurnHighlight? highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('a7', side: PieceColor.white),
        ExtMove('d7', side: PieceColor.black),
      ], isRemovalPending: false);

      expect(highlight, isNotNull);
      expect(highlight!.side, PieceColor.black);
      expect(highlight.toSquare, notationToSquare('d7'));
    });

    test('supports a removal-only imported path', () {
      final MillTurnHighlight? highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('xa1', side: PieceColor.black),
      ], isRemovalPending: false);

      expect(highlight, isNotNull);
      expect(highlight!.primaryType, isNull);
      expect(highlight.removedSquares, <int>[notationToSquare('a1')]);
    });

    test('does not highlight draw and none sentinels', () {
      expect(
        MillTurnHighlight.fromPath(<ExtMove>[
          ExtMove('draw', side: PieceColor.draw),
        ], isRemovalPending: false),
        isNull,
      );
      expect(
        MillTurnHighlight.fromPath(<ExtMove>[
          ExtMove('none', side: PieceColor.nobody),
        ], isRemovalPending: false),
        isNull,
      );
    });
  });

  group('TurnHighlightPainter', () {
    testWidgets('paints a completed placement as a solid ring', (
      WidgetTester tester,
    ) async {
      const Size size = Size.square(350);
      final MillTurnHighlight highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('a7', side: PieceColor.white),
      ], isRemovalPending: false)!;
      const TurnHighlightPainter painter = TurnHighlightPainter(
        highlight: null,
        color: Colors.blue,
        pieceWidth: 1,
      );
      final TurnHighlightPainter activePainter = TurnHighlightPainter(
        highlight: highlight,
        color: Colors.blue,
        pieceWidth: 1,
      );
      final Offset point = pointFromSquare(notationToSquare('a7'), size);

      void paint(Canvas canvas) => activePainter.paint(canvas, size);

      expect(
        paint,
        paints..circle(
          x: point.dx,
          y: point.dy,
          style: PaintingStyle.stroke,
          strokeWidth: 3.0,
        ),
      );
      expect(activePainter.shouldRepaint(painter), isTrue);
      expect(
        activePainter.shouldRepaint(
          TurnHighlightPainter(
            highlight: highlight,
            color: Colors.blue,
            pieceWidth: 1,
          ),
        ),
        isFalse,
      );
    });

    testWidgets('paints a completed movement as an arrowless trail', (
      WidgetTester tester,
    ) async {
      const Size size = Size.square(350);
      final MillTurnHighlight highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('a7-d7', side: PieceColor.white),
      ], isRemovalPending: false)!;
      final TurnHighlightPainter painter = TurnHighlightPainter(
        highlight: highlight,
        color: Colors.blue,
        pieceWidth: 1,
      );
      final Offset start = pointFromSquare(notationToSquare('a7'), size);
      final Offset end = pointFromSquare(notationToSquare('d7'), size);

      void paint(Canvas canvas) => painter.paint(canvas, size);

      expect(
        paint,
        paints
          ..line(strokeWidth: 3.0)
          ..circle(
            x: start.dx,
            y: start.dy,
            style: PaintingStyle.stroke,
            strokeWidth: 3.0,
          )
          ..circle(
            x: end.dx,
            y: end.dy,
            style: PaintingStyle.stroke,
            strokeWidth: 3.0,
          ),
      );
    });

    testWidgets('paints completed removal points as solid crosses', (
      WidgetTester tester,
    ) async {
      final MillTurnHighlight highlight = MillTurnHighlight.fromPath(<ExtMove>[
        ExtMove('a7', side: PieceColor.white),
        ExtMove('xd7', side: PieceColor.white),
      ], isRemovalPending: false)!;
      final TurnHighlightPainter painter = TurnHighlightPainter(
        highlight: highlight,
        color: Colors.blue,
        pieceWidth: 1,
      );

      void paint(Canvas canvas) =>
          painter.paint(canvas, const Size.square(350));

      expect(
        paint,
        paints
          ..circle(style: PaintingStyle.stroke, strokeWidth: 3.0)
          ..line(strokeWidth: 3.0)
          ..line(strokeWidth: 3.0),
      );
    });
  });
}
