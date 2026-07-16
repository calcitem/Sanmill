// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../../../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DB.instance = MockDB();
    AppTheme.boardPadding = 28.0;
    GameController().reset();
    AnalysisMode.disable();
    AnalysisMode.setShowBestMoveArrow(true);
    AnalysisMode.setShowAllBoardResults(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowBestMoveArrow(true);
    AnalysisMode.setShowAllBoardResults(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    DB.instance = null;
  });

  testWidgets(
    'renders the best engine line over mixed database analysis results',
    (WidgetTester tester) async {
      const Size size = Size.square(350);
      final double squareSize = (size.width - boardMargin * 2) / 6;
      final Offset startPoint = pointFromSquare(notationToSquare('a1'), size);

      AnalysisMode.setEngineLineCount(1);
      AnalysisMode.enable(
        const <MoveAnalysisResult>[
          MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.loss),
        ],
        lineResults: const <MoveAnalysisResult>[
          MoveAnalysisResult(
            move: 'a1-d1',
            outcome: AnalysisOutcome.advantage,
            rank: 1,
            depth: 12,
            line: <String>['a1-d1', 'd7'],
          ),
        ],
        source: AnalysisSource.perfectDatabaseAndEngine,
      );

      void paint(Canvas canvas) {
        AnalysisRenderer.render(canvas, size, squareSize);
      }

      expect(
        paint,
        paints
          ..line(p1: startPoint, strokeWidth: 5.0, style: PaintingStyle.stroke),
      );
    },
  );

  testWidgets('hides the best engine line when disabled', (
    WidgetTester tester,
  ) async {
    const Size size = Size.square(350);
    final double squareSize = (size.width - boardMargin * 2) / 6;
    final Offset startPoint = pointFromSquare(notationToSquare('a1'), size);

    AnalysisMode.setShowBestMoveArrow(false);
    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.loss),
      ],
      lineResults: const <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'a1-d1',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 12,
          line: <String>['a1-d1', 'd7'],
        ),
      ],
      source: AnalysisSource.perfectDatabaseAndEngine,
    );

    void paint(Canvas canvas) {
      AnalysisRenderer.render(canvas, size, squareSize);
    }

    expect(
      paint,
      isNot(
        paints
          ..line(p1: startPoint, strokeWidth: 5.0, style: PaintingStyle.stroke),
      ),
    );
  });

  testWidgets('limits focused engine candidates to MultiPV 1 through 3', (
    WidgetTester tester,
  ) async {
    AnalysisMode.enable(
      const <MoveAnalysisResult>[],
      lineResults: const <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'a1-d1',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
        ),
        MoveAnalysisResult(
          move: 'a4-d2',
          outcome: AnalysisOutcome.draw,
          rank: 2,
        ),
        MoveAnalysisResult(
          move: 'a7-d3',
          outcome: AnalysisOutcome.disadvantage,
          rank: 3,
        ),
      ],
      source: AnalysisSource.engine,
    );

    for (int count = 1; count <= 3; count++) {
      AnalysisMode.setEngineLineCount(count);
      expect(
        AnalysisRenderer.visibleFocusedMovesForTesting(),
        <String>['a1-d1', 'a4-d2', 'a7-d3'].take(count).toList(growable: false),
      );
    }
  });

  testWidgets('expands perfect results only when all candidates is enabled', (
    WidgetTester tester,
  ) async {
    const Size size = Size.square(350);
    final double squareSize = (size.width - boardMargin * 2) / 6;
    final Offset thirdPoint = pointFromSquare(notationToSquare('a7'), size);
    AnalysisMode.setEngineLineCount(2);
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
      MoveAnalysisResult(move: 'a4', outcome: AnalysisOutcome.draw),
      MoveAnalysisResult(move: 'a7', outcome: AnalysisOutcome.loss),
    ], source: AnalysisSource.perfectDatabase);

    void focusedPaint(Canvas canvas) {
      AnalysisRenderer.render(canvas, size, squareSize);
    }

    expect(
      focusedPaint,
      isNot(
        paints..circle(
          x: thirdPoint.dx,
          y: thirdPoint.dy,
          radius: squareSize * 0.4,
        ),
      ),
    );

    AnalysisMode.setShowAllBoardResults(true);

    void expandedPaint(Canvas canvas) {
      AnalysisRenderer.render(canvas, size, squareSize);
    }

    expect(
      expandedPaint,
      paints
        ..circle(x: thirdPoint.dx, y: thirdPoint.dy, radius: squareSize * 0.4),
    );
  });

  testWidgets('threat mode keeps the normal best and limits red candidates', (
    WidgetTester tester,
  ) async {
    AnalysisMode.setEngineLineCount(2);
    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(move: 'a1-d1', outcome: AnalysisOutcome.advantage),
    ], source: AnalysisSource.engine);
    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'a4-d2', outcome: AnalysisOutcome.advantage),
        MoveAnalysisResult(move: 'a7-d3', outcome: AnalysisOutcome.draw),
        MoveAnalysisResult(
          move: 'd7-g7',
          outcome: AnalysisOutcome.disadvantage,
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );

    expect(AnalysisRenderer.visibleThreatMovesForTesting(), <String>[
      'a1-d1',
      'a4-d2',
      'a7-d3',
    ]);
  });
}
