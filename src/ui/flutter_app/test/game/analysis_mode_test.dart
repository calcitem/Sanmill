// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
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
    // Always start with a clean state
    AnalysisMode.disable();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    AnalysisMode.disable();
  });

  // All known GameOutcome instances for exhaustive testing
  final List<GameOutcome> allOutcomes = <GameOutcome>[
    GameOutcome.win,
    GameOutcome.draw,
    GameOutcome.loss,
    GameOutcome.advantage,
    GameOutcome.disadvantage,
    GameOutcome.unknown,
  ];

  // ---------------------------------------------------------------------------
  // Enable / Disable
  // ---------------------------------------------------------------------------
  group('AnalysisMode enable/disable', () {
    test('should start disabled', () {
      expect(AnalysisMode.isEnabled, isFalse);
      expect(AnalysisMode.isAnalyzing, isFalse);
      expect(AnalysisMode.analysisResults, isEmpty);
      expect(AnalysisMode.trapMoves, isEmpty);
    });

    test('enable should set isEnabled to true', () {
      AnalysisMode.enable(<MoveAnalysisResult>[]);

      expect(AnalysisMode.isEnabled, isTrue);
      expect(AnalysisMode.isAnalyzing, isFalse);
    });

    test('enable should store analysis results', () {
      final List<MoveAnalysisResult> results = <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'a1', outcome: GameOutcome.win, score: 100),
        MoveAnalysisResult(move: 'b4', outcome: GameOutcome.draw, score: 0),
      ];

      AnalysisMode.enable(results);

      expect(AnalysisMode.analysisResults.length, 2);
      expect(AnalysisMode.analysisResults[0].move, 'a1');
      expect(AnalysisMode.analysisResults[1].move, 'b4');
    });

    test('enable with trap moves should store them', () {
      AnalysisMode.enable(
        <MoveAnalysisResult>[],
        trapMoves: <String>['a1', 'd5'],
      );

      expect(AnalysisMode.trapMoves, <String>['a1', 'd5']);
    });

    test('disable should reset all state', () {
      AnalysisMode.enable(
        <MoveAnalysisResult>[
          MoveAnalysisResult(move: 'a1', outcome: GameOutcome.win, score: 100),
        ],
        trapMoves: <String>['a1'],
      );

      AnalysisMode.disable();

      expect(AnalysisMode.isEnabled, isFalse);
      expect(AnalysisMode.isAnalyzing, isFalse);
      expect(AnalysisMode.analysisResults, isEmpty);
      expect(AnalysisMode.trapMoves, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // isTrapMove
  // ---------------------------------------------------------------------------
  group('AnalysisMode.isTrapMove', () {
    test('should return true for known trap moves', () {
      AnalysisMode.enable(
        <MoveAnalysisResult>[],
        trapMoves: <String>['a1', 'd5', 'g7'],
      );

      expect(AnalysisMode.isTrapMove('a1'), isTrue);
      expect(AnalysisMode.isTrapMove('d5'), isTrue);
      expect(AnalysisMode.isTrapMove('g7'), isTrue);
    });

    test('should return false for non-trap moves', () {
      AnalysisMode.enable(<MoveAnalysisResult>[], trapMoves: <String>['a1']);

      expect(AnalysisMode.isTrapMove('b4'), isFalse);
      expect(AnalysisMode.isTrapMove(''), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // setAnalyzing
  // ---------------------------------------------------------------------------
  group('AnalysisMode.setAnalyzing', () {
    test('should update isAnalyzing flag', () {
      AnalysisMode.setAnalyzing(true);
      expect(AnalysisMode.isAnalyzing, isTrue);

      AnalysisMode.setAnalyzing(false);
      expect(AnalysisMode.isAnalyzing, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // toggle
  // ---------------------------------------------------------------------------
  group('AnalysisMode.toggle', () {
    test('should enable when disabled and results are provided', () {
      final List<MoveAnalysisResult> results = <MoveAnalysisResult>[
        MoveAnalysisResult(move: 'a1', outcome: GameOutcome.win, score: 100),
      ];

      AnalysisMode.toggle(results);

      expect(AnalysisMode.isEnabled, isTrue);
    });

    test('should disable when currently enabled', () {
      AnalysisMode.enable(<MoveAnalysisResult>[]);

      AnalysisMode.toggle(null);

      expect(AnalysisMode.isEnabled, isFalse);
    });

    test('should not enable when results are null', () {
      AnalysisMode.toggle(null);

      expect(AnalysisMode.isEnabled, isFalse);
    });

    test('should not enable when results are empty', () {
      AnalysisMode.toggle(<MoveAnalysisResult>[]);

      expect(AnalysisMode.isEnabled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // getColorForOutcome / getOpacityForOutcome
  // ---------------------------------------------------------------------------
  group('AnalysisMode colors and opacity', () {
    test('getColorForOutcome should return distinct colors', () {
      final Color winColor = AnalysisMode.getColorForOutcome(GameOutcome.win);
      final Color lossColor = AnalysisMode.getColorForOutcome(GameOutcome.loss);
      final Color drawColor = AnalysisMode.getColorForOutcome(GameOutcome.draw);

      expect(winColor, isNot(lossColor));
      expect(winColor, isNot(drawColor));
    });

    test('getColorForOutcome should handle all outcomes', () {
      for (final GameOutcome outcome in allOutcomes) {
        final Color color = AnalysisMode.getColorForOutcome(outcome);
        expect(color, isNotNull, reason: 'Color for ${outcome.name}');
      }
    });

    test('getOpacityForOutcome should return values between 0 and 1', () {
      for (final GameOutcome outcome in allOutcomes) {
        final double opacity = AnalysisMode.getOpacityForOutcome(outcome);
        expect(
          opacity,
          greaterThanOrEqualTo(0),
          reason: 'Opacity for ${outcome.name} >= 0',
        );
        expect(
          opacity,
          lessThanOrEqualTo(1),
          reason: 'Opacity for ${outcome.name} <= 1',
        );
      }
    });

    test('win should have higher opacity than loss', () {
      final double winOpacity = AnalysisMode.getOpacityForOutcome(
        GameOutcome.win,
      );
      final double lossOpacity = AnalysisMode.getOpacityForOutcome(
        GameOutcome.loss,
      );

      expect(winOpacity, greaterThan(lossOpacity));
    });
  });

  // ---------------------------------------------------------------------------
  // GameOutcome
  // ---------------------------------------------------------------------------
  group('GameOutcome', () {
    test('predefined outcomes should have correct names', () {
      expect(GameOutcome.win.name, 'win');
      expect(GameOutcome.draw.name, 'draw');
      expect(GameOutcome.loss.name, 'loss');
      expect(GameOutcome.advantage.name, 'advantage');
      expect(GameOutcome.disadvantage.name, 'disadvantage');
      expect(GameOutcome.unknown.name, 'unknown');
    });

    test('equality should be based on name', () {
      expect(GameOutcome.win, const GameOutcome('win'));
      expect(GameOutcome.draw, const GameOutcome('draw'));
      expect(GameOutcome.win, isNot(GameOutcome.loss));
    });

    test('withValue should preserve name and add value', () {
      final GameOutcome outcome = GameOutcome.withValue(GameOutcome.win, '100');

      expect(outcome.name, 'win');
      expect(outcome.valueStr, '100');
    });

    test('withValueAndSteps should preserve all information', () {
      final GameOutcome outcome = GameOutcome.withValueAndSteps(
        GameOutcome.loss,
        '-50',
        15,
      );

      expect(outcome.name, 'loss');
      expect(outcome.valueStr, '-50');
      expect(outcome.stepCount, 15);
    });

    test('displayString should include name', () {
      expect(GameOutcome.win.displayString, contains('win'));
      expect(GameOutcome.draw.displayString, contains('draw'));
    });

    test('displayString with value and steps', () {
      final GameOutcome outcome = GameOutcome.withValueAndSteps(
        GameOutcome.win,
        '100',
        10,
      );

      expect(outcome.displayString, contains('win'));
      expect(outcome.displayString, contains('100'));
      expect(outcome.displayString, contains('10'));
    });
  });
}
