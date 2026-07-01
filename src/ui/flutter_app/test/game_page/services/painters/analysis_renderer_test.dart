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
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowBestMoveArrow(true);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    DB.instance = null;
  });

  testWidgets(
    'renders the best engine line over mixed database analysis results',
    (WidgetTester tester) async {
      const Size size = Size.square(350);
      final double squareSize = (size.width - boardMargin * 2) / 6;
      final Offset startPoint = pointFromSquare(notationToSquare('a1'), size);

      AnalysisMode.setEngineLineCount(0);
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
}
