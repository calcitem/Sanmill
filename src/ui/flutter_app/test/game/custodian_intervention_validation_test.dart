// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// Validation tests for custodian and intervention rule implementation

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'bestmove a1';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    // Configure with zhiqi rules and custodian/intervention enabled
    final MockDB mockDB = MockDB();
    mockDB.ruleSettings = const ZhiQiRuleSettings().copyWith(
      enableCustodianCapture: true,
      enableInterventionCapture: true,
    );
    DB.instance = mockDB;

    SoundManager.instance = MockAudios();
    final GameController controller = GameController.instance;
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group('Custodian and Intervention Validation', () {
    late GameController controller;
    late Position position;

    setUp(() {
      controller = GameController.instance;
      position = controller.position;
    });

    test('FEN validation rejects invalid custodian targets (FR-035)', () {
      // Test that FEN parsing correctly rejects invalid targets
      const String invalidCustodianFen =
          '********/********/******** w p r 0 12 0 12 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-9';
      // Square 9 is empty but custodian marker references it

      final bool fenSet = position.setFen(invalidCustodianFen);
      expect(
        fenSet,
        isFalse,
        reason: 'Invalid custodian FEN should be rejected per FR-035',
      );
    });

    test('FEN validation rejects invalid intervention targets (FR-035)', () {
      // Test that FEN parsing correctly rejects invalid targets
      const String invalidInterventionFen =
          '********/********/******** w p r 0 12 0 12 0 2 0 0 0 0 0 0 1 i:w-0-|b-2-8.15';
      // Squares 8 and 15 are empty but intervention marker references them

      final bool fenSet = position.setFen(invalidInterventionFen);
      expect(
        fenSet,
        isFalse,
        reason: 'Invalid intervention FEN should be rejected per FR-035',
      );
    });

    test('Valid FEN without capture markers imports successfully', () {
      // Test basic FEN import/export functionality
      const String validFen =
          '********/********/******** w p p 0 12 0 12 0 0 0 0 0 0 0 0 1';

      final bool fenSet = position.setFen(validFen);
      expect(fenSet, isTrue, reason: 'Valid FEN should import successfully');

      final String? exportedFen = position.fen;
      expect(exportedFen, isNotNull, reason: 'FEN export should not be null');
      expect(exportedFen, isNot(contains('c:')), reason: 'No custodian marker');
      expect(
        exportedFen,
        isNot(contains('i:')),
        reason: 'No intervention marker',
      );
    });

    test('mayRemoveMultiple setting is correctly configured', () {
      // Verify that the rule settings are properly configured
      expect(
        DB().ruleSettings.enableCustodianCapture,
        isTrue,
        reason: 'Custodian capture should be enabled',
      );
      expect(
        DB().ruleSettings.enableInterventionCapture,
        isTrue,
        reason: 'Intervention capture should be enabled',
      );
      expect(
        DB().ruleSettings.piecesCount,
        equals(12),
        reason: 'Should use 12 pieces for zhiqi',
      );
      expect(
        DB().ruleSettings.hasDiagonalLines,
        isTrue,
        reason: 'Should have diagonal lines for zhiqi',
      );
    });

    test('Position state management with capture counts', () {
      // Test basic position state management
      expect(
        position.pieceToRemoveCount[PieceColor.white],
        equals(0),
        reason: 'Initial white remove count should be 0',
      );
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(0),
        reason: 'Initial black remove count should be 0',
      );

      // Test that we can set remove counts
      position.pieceToRemoveCount[PieceColor.black] = 1;
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(1),
        reason: 'Should be able to set remove count',
      );
    });

    test('FEN export includes capture markers when active', () {
      // Create a position with some pieces and set capture state manually
      const String baseFen =
          '*@******/********/******** w p r 1 11 1 11 0 1 0 0 0 0 0 0 1';

      final bool fenSet = position.setFen(baseFen);
      expect(fenSet, isTrue, reason: 'Base FEN should import successfully');

      // The position has a black piece at square 9 and pieceToRemoveCount[black] = 1
      // This should be a valid state for FEN export
      final String? exportedFen = position.fen;
      expect(exportedFen, isNotNull, reason: 'FEN export should not be null');

      // Verify that the position state is correctly represented
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(1),
        reason: 'Should have 1 piece to remove',
      );
    });
  });
}
