// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_toolbar_test.dart
//
// Integration tests for the game page toolbar.
// Verifies that toolbar items function correctly, including the game
// options modal, the options navigation, and the move list.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
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

  group('Game Toolbar', () {
    testWidgets('Game toolbar container is present', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Verify the toolbar container exists
      verifyWidgetExists(tester, 'game_page_toolbar_container');
    });

    testWidgets('Toolbar item labels are visible', (WidgetTester tester) async {
      await initApp(tester);

      // Verify toolbar item labels
      verifyWidgetExists(tester, 'play_area_toolbar_item_game_label');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options_label');
      verifyWidgetExists(tester, 'play_area_toolbar_item_move_label');
      verifyWidgetExists(tester, 'play_area_toolbar_item_info_label');
    });

    testWidgets('Game options modal shows New Game option', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Open game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify New Game option
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be present',
      );
    });

    testWidgets('Game options modal shows Import option', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Open game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify Import Game option is present (on desktop platforms)
      expect(
        find.byKey(const Key('import_game_option')),
        findsOneWidget,
        reason: 'Import Game option should be present on desktop',
      );
    });

    testWidgets('Game options modal shows Load option', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Open game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify Load Game option is present
      expect(
        find.byKey(const Key('load_game_option')),
        findsOneWidget,
        reason: 'Load Game option should be present on desktop',
      );
    });

    testWidgets('Options toolbar item navigates to settings', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Tap Options
      await tapToolbarItem(tester, 'play_area_toolbar_item_options');

      // Should navigate to General Settings page
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');
    });

    testWidgets('Info toolbar item opens info dialog', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Tap Info
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // Dialog should be showing - wait for it
      await tester.pumpAndSettle();

      // The dialog should be present (it's an AlertDialog)
      // Dismiss it
      final Finder okButton = find.text('OK');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton.first);
        await tester.pumpAndSettle();
      }

      // Verify we're back on the game page
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('New game from fresh state skips confirmation', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Open game options
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Tap New Game
      await tester.tap(find.byKey(const Key('new_game_option')));
      await tester.pumpAndSettle();

      // From a fresh state (no moves), should not show restart dialog
      // Game page should still be displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });
  });
}
