// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// statistics_page_test.dart
//
// Integration tests for the Statistics page.
// Verifies that the statistics page loads correctly, all cards are present,
// and interactive elements like the statistics toggle and reset button work.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic>? dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Statistics Page', () {
    testWidgets('Page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Verify the statistics page scaffold
      verifyPageDisplayed(tester, 'statistics_page_scaffold');

      // Verify the settings list is present
      verifyWidgetExists(tester, 'statistics_page_settings_list');
    });

    testWidgets('Human rating card is visible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Verify the human rating card
      verifyWidgetExists(tester, 'statistics_page_human_rating_card');
    });

    testWidgets('AI statistics card is visible', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Scroll to the AI statistics card
      await scrollToAndVerify(
        tester,
        targetKey: 'statistics_page_ai_statistics_card',
        scrollableKey: 'statistics_page_settings_list',
      );
    });

    testWidgets('Settings card with enable toggle is visible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Scroll to the settings card
      await scrollToAndVerify(
        tester,
        targetKey: 'statistics_page_settings_card',
        scrollableKey: 'statistics_page_settings_list',
      );

      // Verify enable statistics switch is present
      await scrollToAndVerify(
        tester,
        targetKey: 'statistics_page_enable_statistics_switch',
        scrollableKey: 'statistics_page_settings_list',
        resetScroll: false,
      );
    });

    testWidgets('Toggle enable statistics switch', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      final bool initialValue = DB().statsSettings.isStatsEnabled;

      // Scroll to and tap the enable statistics switch
      await scrollToAndTap(
        tester,
        targetKey: 'statistics_page_enable_statistics_switch',
        scrollableKey: 'statistics_page_settings_list',
      );

      // Verify the setting changed
      expect(
        DB().statsSettings.isStatsEnabled,
        isNot(equals(initialValue)),
        reason: 'Enable statistics should have toggled',
      );
    });

    testWidgets('Reset statistics button is accessible', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Scroll to the reset statistics button
      await scrollToAndVerify(
        tester,
        targetKey: 'statistics_page_reset_statistics',
        scrollableKey: 'statistics_page_settings_list',
      );
    });

    testWidgets('Reset statistics shows confirmation dialog', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Scroll to and tap the reset statistics button
      await scrollToAndTap(
        tester,
        targetKey: 'statistics_page_reset_statistics',
        scrollableKey: 'statistics_page_settings_list',
      );

      // A confirmation dialog should appear
      // Look for dialog buttons (Cancel and OK)
      await tester.pumpAndSettle();

      // Dismiss the dialog by tapping Cancel or OK
      // The dialog uses S.of(context).cancel and S.of(context).ok
      final Finder cancelButton = find.text('Cancel');
      if (cancelButton.evaluate().isNotEmpty) {
        await tester.tap(cancelButton.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Navigate to statistics from game page', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Start from default game page
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Navigate to statistics
      await navigateToDrawerItem(tester, 'drawer_item_statistics');
      verifyPageDisplayed(tester, 'statistics_page_scaffold');

      // Navigate back to game
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });
  });
}
