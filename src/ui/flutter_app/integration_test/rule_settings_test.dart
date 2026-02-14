// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// rule_settings_test.dart
//
// Integration tests for the Rule Settings page.
// Verifies that all rule sections are present, rule toggles work correctly,
// and modal pickers for rule values function as expected.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Rule Settings Page', () {
    testWidgets('Page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Verify the page scaffold
      verifyPageDisplayed(tester, 'rule_settings_scaffold');
    });

    testWidgets('Rule set card is visible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Verify the rule set card
      verifyWidgetExists(tester, 'rule_settings_card_rule_set');

      // Verify the rule set tile
      verifyWidgetExists(tester, 'rule_settings_tile_rule_set');
    });

    testWidgets('Tap rule set tile opens modal', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Tap the rule set tile
      await tester.tap(find.byKey(const Key('rule_settings_tile_rule_set')));
      await tester.pumpAndSettle();

      // Verify the Nine Men's Morris radio button is in the modal
      final Finder nineMensMorrisRadio = find.byKey(
        const Key('radio_nine_mens_morris'),
      );
      expect(
        nineMensMorrisRadio,
        findsOneWidget,
        reason: "Nine Men's Morris radio should be present in rule set modal",
      );

      // Select Nine Men's Morris
      await tester.tap(nineMensMorrisRadio);
      await tester.pumpAndSettle();
    });

    testWidgets('General section items are accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Verify general card
      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_card_general',
        scrollableKey: 'rule_settings_list',
      );

      // Verify pieces count tile
      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_tile_pieces_count',
        scrollableKey: 'rule_settings_list',
        resetScroll: false,
      );
    });

    testWidgets('Toggle diagonal lines switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.hasDiagonalLines;

      // Scroll to and tap the diagonal lines switch
      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_has_diagonal_lines',
        scrollableKey: 'rule_settings_list',
      );

      // Verify state changed
      expect(
        DB().ruleSettings.hasDiagonalLines,
        isNot(equals(initialValue)),
        reason: 'Diagonal lines setting should have toggled',
      );
    });

    testWidgets('Toggle threefold repetition rule', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.threefoldRepetitionRule;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_threefold_repetition_rule',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.threefoldRepetitionRule,
        isNot(equals(initialValue)),
        reason: 'Threefold repetition rule should have toggled',
      );
    });

    testWidgets('Placing phase section is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Scroll to placing phase card
      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_card_placing_phase',
        scrollableKey: 'rule_settings_list',
      );
    });

    testWidgets('Toggle may move in placing phase', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.mayMoveInPlacingPhase;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_may_move_in_placing_phase',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.mayMoveInPlacingPhase,
        isNot(equals(initialValue)),
        reason: 'May move in placing phase should have toggled',
      );
    });

    testWidgets('Moving phase section is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_card_moving_phase',
        scrollableKey: 'rule_settings_list',
      );
    });

    testWidgets('Toggle defender moves first', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.isDefenderMoveFirst;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_is_defender_move_first',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.isDefenderMoveFirst,
        isNot(equals(initialValue)),
        reason: 'Defender moves first should have toggled',
      );
    });

    testWidgets('Toggle restrict repeated mills formation', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue =
          DB().ruleSettings.restrictRepeatedMillsFormation;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_restrict_repeated_mills_formation',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.restrictRepeatedMillsFormation,
        isNot(equals(initialValue)),
        reason: 'Restrict repeated mills formation should have toggled',
      );
    });

    testWidgets('May fly section is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_card_may_fly',
        scrollableKey: 'rule_settings_list',
      );
    });

    testWidgets('Toggle may fly switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.mayFly;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_may_fly',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.mayFly,
        isNot(equals(initialValue)),
        reason: 'May fly should have toggled',
      );
    });

    testWidgets('Removing section is accessible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      await scrollToAndVerify(
        tester,
        targetKey: 'rule_settings_card_removing',
        scrollableKey: 'rule_settings_list',
      );
    });

    testWidgets('Toggle may remove from mills always', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.mayRemoveFromMillsAlways;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_may_remove_from_mills_always',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.mayRemoveFromMillsAlways,
        isNot(equals(initialValue)),
        reason: 'May remove from mills always should have toggled',
      );
    });

    testWidgets('Toggle may remove multiple', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.mayRemoveMultiple;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_may_remove_multiple',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.mayRemoveMultiple,
        isNot(equals(initialValue)),
        reason: 'May remove multiple should have toggled',
      );
    });

    testWidgets('Toggle one time use mill', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      final bool initialValue = DB().ruleSettings.oneTimeUseMill;

      await scrollToAndTap(
        tester,
        targetKey: 'rule_settings_switch_one_time_use_mill',
        scrollableKey: 'rule_settings_list',
      );

      expect(
        DB().ruleSettings.oneTimeUseMill,
        isNot(equals(initialValue)),
        reason: 'One time use mill should have toggled',
      );
    });
  });
}
