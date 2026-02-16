// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_helpers_test.dart
//
// Tests for top-level mill.dart functions and enums.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
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
  // MoveQuality enum
  // ---------------------------------------------------------------------------
  group('MoveQuality', () {
    test('should have five values', () {
      expect(MoveQuality.values.length, 5);
    });

    test('should include all expected values', () {
      expect(
        MoveQuality.values,
        containsAll(<MoveQuality>[
          MoveQuality.normal,
          MoveQuality.minorGoodMove,
          MoveQuality.majorGoodMove,
          MoveQuality.minorBadMove,
          MoveQuality.majorBadMove,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // isRuleSupportingPerfectDatabase
  // ---------------------------------------------------------------------------
  group('isRuleSupportingPerfectDatabase', () {
    test("default Nine Men's Morris should support perfect DB", () {
      mockDB.ruleSettings = const RuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isTrue);
    });

    test("Twelve Men's Morris should support perfect DB", () {
      mockDB.ruleSettings = const TwelveMensMorrisRuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isTrue);
    });

    test('Lasker Morris (10 pieces, move in placing) should support', () {
      mockDB.ruleSettings = const LaskerMorrisSettings();

      expect(isRuleSupportingPerfectDatabase(), isTrue);
    });

    test(
      'Morabaraba should NOT support (boardFullAction != firstPlayerLose)',
      () {
        mockDB.ruleSettings = const MorabarabaRuleSettings();

        expect(isRuleSupportingPerfectDatabase(), isFalse);
      },
    );

    test('One-time mill should NOT support (oneTimeUseMill = true)', () {
      mockDB.ruleSettings = const OneTimeMillRuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('ChamGonu should NOT support (mayFly = false, markAndDelay)', () {
      mockDB.ruleSettings = const ChamGonuRuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('ZhiQi should NOT support (boardFullAction mismatch)', () {
      mockDB.ruleSettings = const ZhiQiRuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('DaSanQi should NOT support (mayRemoveMultiple = true)', () {
      mockDB.ruleSettings = const DaSanQiRuleSettings();

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('custom with custodian capture should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(enableCustodianCapture: true);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('custom with intervention capture should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(enableInterventionCapture: true);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('custom with mayRemoveFromMillsAlways should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(mayRemoveFromMillsAlways: true);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test(
      'custom with stalemateAction = changeSideToMove should NOT support',
      () {
        mockDB.ruleSettings = const RuleSettings(
          stalemateAction: StalemateAction.changeSideToMove,
        );

        expect(isRuleSupportingPerfectDatabase(), isFalse);
      },
    );

    test('custom with flyPieceCount != 3 should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(flyPieceCount: 4);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('custom with piecesAtLeastCount != 3 should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(piecesAtLeastCount: 2);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('custom with restrictRepeatedMillsFormation should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(
        restrictRepeatedMillsFormation: true,
      );

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test('9 pieces with diagonal should NOT support', () {
      mockDB.ruleSettings = const RuleSettings(hasDiagonalLines: true);

      expect(isRuleSupportingPerfectDatabase(), isFalse);
    });

    test(
      'custom with non-standard mill formation action should NOT support',
      () {
        mockDB.ruleSettings = const RuleSettings(
          millFormationActionInPlacingPhase:
              MillFormationActionInPlacingPhase.markAndDelayRemovingPieces,
        );

        expect(isRuleSupportingPerfectDatabase(), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // GameResult NAG strings
  // ---------------------------------------------------------------------------
  group('GameResult.toNagString', () {
    test('should return correct NAG strings', () {
      expect(GameResult.win.toNagString(), '1-0');
      expect(GameResult.lose.toNagString(), '0-1');
      expect(GameResult.draw.toNagString(), '1/2-1/2');
    });
  });

  // ---------------------------------------------------------------------------
  // GameOverReason enum
  // ---------------------------------------------------------------------------
  group('GameOverReason', () {
    test('should include all expected values', () {
      expect(GameOverReason.values.length, 10);
      expect(
        GameOverReason.values,
        containsAll(<GameOverReason>[
          GameOverReason.loseFewerThanThree,
          GameOverReason.loseNoLegalMoves,
          GameOverReason.loseFullBoard,
          GameOverReason.loseResign,
          GameOverReason.loseTimeout,
          GameOverReason.drawThreefoldRepetition,
          GameOverReason.drawFiftyMove,
          GameOverReason.drawEndgameFiftyMove,
          GameOverReason.drawFullBoard,
          GameOverReason.drawStalemateCondition,
        ]),
      );
    });
  });
}
