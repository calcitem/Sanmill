// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// position_analysis_result_test.dart
//
// Tests for PositionAnalysisResult and MoveAnalysisResult data classes.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // PositionAnalysisResult
  // ---------------------------------------------------------------------------
  group('PositionAnalysisResult', () {
    test('should store possible moves', () {
      final PositionAnalysisResult result = PositionAnalysisResult(
        possibleMoves: <MoveAnalysisResult>[
          MoveAnalysisResult(
            move: 'a1',
            outcome: GameOutcome.win,
            score: 100,
          ),
        ],
      );

      expect(result.possibleMoves.length, 1);
      expect(result.possibleMoves.first.move, 'a1');
      expect(result.isValid, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('should store trap moves', () {
      final PositionAnalysisResult result = PositionAnalysisResult(
        possibleMoves: <MoveAnalysisResult>[],
        trapMoves: <String>['d5', 'e4'],
      );

      expect(result.trapMoves, <String>['d5', 'e4']);
    });

    test('default trapMoves should be empty', () {
      final PositionAnalysisResult result = PositionAnalysisResult(
        possibleMoves: <MoveAnalysisResult>[],
      );

      expect(result.trapMoves, isEmpty);
    });

    test('error factory should create invalid result', () {
      final PositionAnalysisResult result = PositionAnalysisResult.error(
        'Analysis failed',
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, 'Analysis failed');
      expect(result.possibleMoves, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // MoveAnalysisResult
  // ---------------------------------------------------------------------------
  group('MoveAnalysisResult', () {
    test('should store move, outcome, and score', () {
      final MoveAnalysisResult result = MoveAnalysisResult(
        move: 'd6',
        outcome: GameOutcome.win,
        score: 100,
      );

      expect(result.move, 'd6');
      expect(result.outcome, GameOutcome.win);
      expect(result.score, 100);
    });

    test('should work with all outcome types', () {
      final List<GameOutcome> outcomes = <GameOutcome>[
        GameOutcome.win,
        GameOutcome.draw,
        GameOutcome.loss,
        GameOutcome.advantage,
        GameOutcome.disadvantage,
        GameOutcome.unknown,
      ];

      for (final GameOutcome outcome in outcomes) {
        final MoveAnalysisResult result = MoveAnalysisResult(
          move: 'a1',
          outcome: outcome,
          score: 0,
        );
        expect(result.outcome.name, outcome.name);
      }
    });

    test('should store negative scores', () {
      final MoveAnalysisResult result = MoveAnalysisResult(
        move: 'b4',
        outcome: GameOutcome.loss,
        score: -100,
      );

      expect(result.score, -100);
    });
  });
}
