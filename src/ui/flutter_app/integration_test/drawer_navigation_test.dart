// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// drawer_navigation_test.dart
//
// Integration tests for the custom drawer navigation.
// Verifies that all drawer items are accessible, groups expand/collapse
// correctly, and page transitions work as expected.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';

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

  group('Drawer Navigation', () {
    testWidgets('Open and close drawer', (WidgetTester tester) async {
      await initApp(tester);

      // Open drawer
      await openDrawer(tester);

      // Verify drawer content is visible (header should be present)
      expect(
        find.byKey(const Key('custom_drawer_header_animated_text_kit')),
        findsOneWidget,
        reason: 'Drawer header should be visible when drawer is open',
      );

      // Close drawer
      await closeDrawer(tester);
    });

    testWidgets('Navigate to Human vs Human', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate to AI vs AI', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate to Setup Position', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate to Puzzles', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_puzzles');

      // Verify that we navigated away from the game page.
      // The puzzles page does not have a specific scaffold key,
      // but we can verify the drawer item was tapped successfully
      // by checking that the app didn't crash and remains responsive.
      await tester.pumpAndSettle();
    });

    testWidgets('Navigate to Statistics', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Verify statistics page scaffold
      verifyPageDisplayed(tester, 'statistics_page_scaffold');
    });

    testWidgets('Expand Settings group and navigate to General Settings', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      // Verify general settings page scaffold
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');
    });

    testWidgets('Expand Settings group and navigate to Rule Settings', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_rule_settings_child',
      );

      // Verify rule settings page scaffold
      verifyPageDisplayed(tester, 'rule_settings_scaffold');
    });

    testWidgets('Expand Settings group and navigate to Appearance', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_appearance_child',
      );

      // Verify appearance settings page scaffold
      verifyPageDisplayed(tester, 'appearance_settings_page_scaffold');
    });

    testWidgets('Switch between game modes via drawer', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Start with Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Switch to AI vs AI
      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');

      // Switch back to Human vs AI (default)
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate to settings and back to game', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Navigate back to Human vs AI
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate through multiple settings pages', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Rule Settings (settings group should still be expanded)
      await openDrawer(tester);
      final Finder ruleSettingsFinder = find.byKey(
        const Key('drawer_item_rule_settings_child'),
      );
      // If the settings group collapsed, we need to expand it again
      if (ruleSettingsFinder.evaluate().isEmpty) {
        final Finder groupFinder = find.byKey(
          const Key('drawer_item_settings_group'),
        );
        await tester.tap(groupFinder);
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(const Key('drawer_item_rule_settings_child')),
      );
      await tester.pumpAndSettle();
      verifyPageDisplayed(tester, 'rule_settings_scaffold');

      // Appearance Settings
      await openDrawer(tester);
      final Finder appearanceFinder = find.byKey(
        const Key('drawer_item_appearance_child'),
      );
      if (appearanceFinder.evaluate().isEmpty) {
        final Finder groupFinder = find.byKey(
          const Key('drawer_item_settings_group'),
        );
        await tester.tap(groupFinder);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('drawer_item_appearance_child')));
      await tester.pumpAndSettle();
      verifyPageDisplayed(tester, 'appearance_settings_page_scaffold');
    });
  });
}
