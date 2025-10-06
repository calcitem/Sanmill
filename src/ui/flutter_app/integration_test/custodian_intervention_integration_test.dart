// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// Integration tests for custodian and intervention rules with zhiqi configuration

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Custodian and Intervention Integration Tests', () {
    setUp(() async {
      // Configure zhiqi (直棋) rules with custodian and intervention enabled
      final RuleSettings zhiqiRules = const ZhiQiRuleSettings().copyWith(
        enableCustodianCapture: true,
        enableInterventionCapture: true,
        custodianCaptureInPlacingPhase: true,
        custodianCaptureInMovingPhase: true,
        interventionCaptureInPlacingPhase: true,
        interventionCaptureInMovingPhase: true,
      );

      // Apply the rule settings
      await DB().setRuleSettings(zhiqiRules);

      // Reset game controller with new rules
      final GameController controller = GameController.instance;
      controller.reset(force: true);
    });

    testWidgets('Custodian capture works in zhiqi rules', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController.instance;
      final Position position = controller.position;

      // Set up a position where custodian capture can occur
      const fenWithCustodianSetup =
          'O@O*****/********/******** w p r 3 6 3 6 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-1';

      final bool fenSet = position.setFen(fenWithCustodianSetup);
      expect(fenSet, isTrue, reason: 'FEN should be set successfully');

      // Verify custodian state is active
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(1),
        reason: 'Should have 1 piece to remove for custodian',
      );

      // Export FEN and verify custodian marker
      final String? exportedFen = position.fen;
      expect(
        exportedFen,
        contains('c:'),
        reason: 'Should contain custodian marker',
      );
    });

    testWidgets('Intervention capture works in zhiqi rules', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController.instance;
      final Position position = controller.position;

      // Set up a position where intervention capture can occur
      const fenWithInterventionSetup =
          '**@*O*@**/********/******** w p r 3 6 3 6 0 2 0 0 0 0 0 0 1 i:w-0-|b-2-2.6';

      final bool fenSet = position.setFen(fenWithInterventionSetup);
      expect(fenSet, isTrue, reason: 'FEN should be set successfully');

      // Verify intervention state is active
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(2),
        reason: 'Should have 2 pieces to remove for intervention',
      );

      // Export FEN and verify intervention marker
      final String? exportedFen = position.fen;
      expect(
        exportedFen,
        contains('i:'),
        reason: 'Should contain intervention marker',
      );
    });

    testWidgets('FEN round-trip consistency with custodian and intervention', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController.instance;
      final Position position = controller.position;

      // Test FEN with both custodian and intervention markers
      const originalFen =
          'O@O*O*@**/********/******** w p r 4 5 4 5 0 3 0 0 0 0 0 0 1 c:w-0-|b-1-1 i:w-0-|b-2-5.7';

      // Import FEN
      final bool fenSet = position.setFen(originalFen);
      expect(fenSet, isTrue, reason: 'FEN should import successfully');

      // Export FEN
      final String? exportedFen = position.fen;
      expect(exportedFen, isNotNull, reason: 'FEN export should not be null');

      // Re-import exported FEN
      controller.reset(force: true);
      final bool reImported = controller.position.setFen(exportedFen!);
      expect(reImported, isTrue, reason: 'Re-import should succeed');

      // Export again and compare
      final String? secondExport = controller.position.fen;
      expect(
        secondExport,
        equals(exportedFen),
        reason: 'Round-trip should be consistent',
      );
    });

    testWidgets('Invalid FEN with missing custodian targets is rejected', (
      WidgetTester tester,
    ) async {
      final GameController controller = GameController.instance;
      final Position position = controller.position;

      // FEN with custodian marker but target square is empty (should be rejected per FR-035)
      const invalidFen =
          'O*O*****/********/******** w p r 2 7 3 6 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-1';
      // Square 1 is empty but custodian marker references it

      final bool fenSet = position.setFen(invalidFen);
      expect(
        fenSet,
        isFalse,
        reason: 'Invalid FEN should be rejected per FR-035',
      );
    });

    testWidgets('mayRemoveMultiple=false with custodian and intervention', (
      WidgetTester tester,
    ) async {
      // Configure rules with mayRemoveMultiple=false
      final RuleSettings modifiedRules = const ZhiQiRuleSettings().copyWith(
        enableCustodianCapture: true,
        enableInterventionCapture: true,
        mayRemoveMultiple: false,
      );
      await DB().setRuleSettings(modifiedRules);

      final GameController controller = GameController.instance;
      controller.reset(force: true);
      final Position position = controller.position;

      // Test that custodian capture still works with mayRemoveMultiple=false
      const fenCustodian =
          'O@O*****/********/******** w p r 3 6 3 6 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-1';

      final bool fenSet = position.setFen(fenCustodian);
      expect(fenSet, isTrue, reason: 'FEN should be set successfully');

      // Even with mayRemoveMultiple=false, custodian capture should work
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(1),
        reason: 'Custodian capture should work with mayRemoveMultiple=false',
      );

      // Test that intervention capture requires 2 captures even with mayRemoveMultiple=false
      const fenIntervention =
          '**@*O*@**/********/******** w p r 3 6 3 6 0 2 0 0 0 0 0 0 1 i:w-0-|b-2-2.6';

      final bool fenSet2 = position.setFen(fenIntervention);
      expect(fenSet2, isTrue, reason: 'FEN should be set successfully');

      // Intervention should override mayRemoveMultiple=false (FR-038)
      expect(
        position.pieceToRemoveCount[PieceColor.black],
        equals(2),
        reason:
            'Intervention should require 2 captures despite mayRemoveMultiple=false',
      );
    });
  });
}
