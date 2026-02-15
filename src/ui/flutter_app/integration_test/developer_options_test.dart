// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// developer_options_test.dart
//
// Integration tests for the Developer Options page.
// Verifies that the developer options page is accessible from
// General Settings, and that its settings items are present.

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

  Map<String, dynamic>? dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Developer Options Page', () {
    testWidgets('Navigate to developer options from general settings', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // First navigate to General Settings
      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Scroll to and tap the Developer Options entry
      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      // Verify the developer options page scaffold is displayed
      verifyPageDisplayed(tester, 'developer_options_page_scaffold');
    });

    testWidgets('Developer options page has settings list', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      // Verify the settings list exists
      verifyWidgetExists(tester, 'developer_options_page_settings_list');
    });

    testWidgets('Auto restart switch is present', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      // Verify the auto restart switch tile
      verifyWidgetExists(
        tester,
        'developer_options_page_settings_card_auto_restart',
      );
    });

    testWidgets('Toggle auto restart switch', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      final bool initialValue = DB().generalSettings.isAutoRestart;

      // Tap the auto restart switch
      await tester.tap(
        find.byKey(
          const Key('developer_options_page_settings_card_auto_restart'),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the state changed
      expect(
        DB().generalSettings.isAutoRestart,
        isNot(equals(initialValue)),
        reason: 'Auto restart should have toggled',
      );
    });

    testWidgets('Logs entry is present', (WidgetTester tester) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      // Verify the logs entry
      verifyWidgetExists(tester, 'developer_options_page_settings_card_logs');
    });

    testWidgets('Navigate back from developer options', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToGroupChild(
        tester,
        'drawer_item_settings_group',
        'drawer_item_general_settings_child',
      );

      await scrollToAndTap(
        tester,
        targetKey: 'general_settings_page_settings_card_developer_options',
      );

      verifyPageDisplayed(tester, 'developer_options_page_scaffold');

      // Press back button (Navigator pop)
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();

      // Should be back on general settings
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');
    });
  });
}
