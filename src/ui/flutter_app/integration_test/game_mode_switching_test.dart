// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_mode_switching_test.dart
//
// Integration tests for switching between game modes and verifying
// cross-feature navigation flows. Tests that the app handles
// transitions between game modes, settings pages, and back correctly.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
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

  group('Game Mode Switching', () {
    testWidgets('Switch from HvAI to HvH and back', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Start on Human vs AI (default)
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Switch to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Switch back to Human vs AI
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Cycle through all game modes', (WidgetTester tester) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Human vs AI (default)
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // AI vs AI
      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Back to Human vs AI
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Game mode to settings to different game mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Start on Human vs AI
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Navigate to General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Navigate directly to Human vs Human (without going back first)
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Settings pages round-trip', (WidgetTester tester) async {
      await initApp(tester);

      // General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Rule Settings (re-expand group if needed)
      await openDrawer(tester);
      final Finder ruleChild = find.byKey(
        const Key('drawer_item_rule_settings_child'),
      );
      if (ruleChild.evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('drawer_item_settings_group')));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(const Key('drawer_item_rule_settings_child')),
      );
      await tester.pumpAndSettle();
      verifyPageDisplayed(tester, 'rule_settings_scaffold');

      // Appearance Settings (re-expand group if needed)
      await openDrawer(tester);
      final Finder appearanceChild = find.byKey(
        const Key('drawer_item_appearance_child'),
      );
      if (appearanceChild.evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('drawer_item_settings_group')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('drawer_item_appearance_child')));
      await tester.pumpAndSettle();
      verifyPageDisplayed(tester, 'appearance_settings_page_scaffold');

      // Back to game
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Game mode to statistics to puzzles to game', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Start on game page
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Go to Statistics
      await navigateToDrawerItem(tester, 'drawer_item_statistics');
      verifyPageDisplayed(tester, 'statistics_page_scaffold');

      // Go to Puzzles
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');
      await tester.pumpAndSettle();

      // Go back to game
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Modify settings then verify game page reflects changes', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Enable history navigation toolbar via DB
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: true,
      );

      // Navigate to game page
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      await tester.pumpAndSettle();

      // Verify history toolbar is present
      verifyWidgetExists(tester, 'play_area_history_nav_take_back');

      // Disable it
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: false,
      );
      await tester.pumpAndSettle();

      // Verify history toolbar is gone
      expect(
        find.byKey(const Key('play_area_history_nav_take_back')),
        findsNothing,
        reason: 'History toolbar should be hidden after disabling',
      );
    });

    testWidgets('Switch game mode via drawer while on settings page', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Appearance Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );
      verifyPageDisplayed(tester, 'appearance_settings_page_scaffold');

      // Switch to AI vs AI directly
      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );
      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Switch to Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Toolbar items persist across mode switches', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Human vs AI - verify toolbar
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');

      // Switch to Human vs Human - toolbar should still be present
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');

      // Switch to Setup Position - toolbar should still be present
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');
    });
  });
}
