// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_page_human_vs_human_test.dart
//
// Integration tests for the Human vs Human game page.
// Verifies mode-specific features like the analysis button,
// and validates basic game operations in this mode.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';

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

  group('Human vs Human Game Page', () {
    testWidgets('Game page loads in HvH mode', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Human vs Human via drawer
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Analysis button is visible in HvH mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // In Human vs Human mode, the analysis button should be available
      // in the top-right corner of the game page
      final Finder analysisButton = find.byKey(
        const Key('game_page_analysis_button'),
      );
      expect(
        analysisButton,
        findsOneWidget,
        reason: 'Analysis button should be visible in HvH mode',
      );
    });

    testWidgets('Toolbar items are present in HvH mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // All main toolbar items should be present
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');
      verifyWidgetExists(tester, 'play_area_toolbar_item_move');
      verifyWidgetExists(tester, 'play_area_toolbar_item_info');
    });

    testWidgets('Start new game in HvH mode', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Start a new game
      await startNewGame(tester);

      // Verify the game page is still displayed after new game
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Game options modal in HvH mode', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Open game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify New Game option is present
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should exist in HvH mode',
      );
    });
  });
}
