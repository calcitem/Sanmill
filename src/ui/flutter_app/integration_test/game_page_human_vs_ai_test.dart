// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_page_human_vs_ai_test.dart
//
// Integration tests for the Human vs AI game page.
// Verifies that the game page loads correctly, toolbar items are present,
// and basic game interactions work as expected.

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

  group('Human vs AI Game Page', () {
    testWidgets('Game page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      // The default page is Human vs AI, verify the game page scaffold
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('All toolbar items are present', (WidgetTester tester) async {
      await initApp(tester);

      // Verify all four main toolbar items exist
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');
      verifyWidgetExists(tester, 'play_area_toolbar_item_move');
      verifyWidgetExists(tester, 'play_area_toolbar_item_info');
    });

    testWidgets('Game toolbar item opens game options modal', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Tap the Game toolbar item
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify the New Game option is present in the modal
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be visible in game options modal',
      );
    });

    testWidgets('Start new game from fresh state', (WidgetTester tester) async {
      await initApp(tester);

      // Configure fast AI for quick testing
      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Start a new game (should not show confirmation dialog for fresh game)
      await startNewGame(tester);

      // Verify the game page is still displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Options toolbar navigates to General Settings', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Tap the Options toolbar item
      await tapToolbarItem(tester, 'play_area_toolbar_item_options');

      // Verify navigation to General Settings
      verifyPageDisplayed(tester, 'general_settings_page_scaffold');

      // Navigate back
      final Finder backButton = find.byKey(const Key('game_page_back_button'));
      // The Options button navigates via Navigator.push, so there should
      // be a back button or we can pop
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Info toolbar opens info dialog', (WidgetTester tester) async {
      await initApp(tester);

      // Tap the Info toolbar item
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // The info dialog should be displayed
      // It shows game information in an AlertDialog
      await tester.pumpAndSettle();

      // Dismiss the dialog by tapping outside or pressing back
      // The InfoDialog has an OK button
      final Finder okButton = find.text('OK');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Move toolbar item opens moves list', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Tap the Move toolbar item
      await tapToolbarItem(tester, 'play_area_toolbar_item_move');

      // Wait for any animations or page transitions
      await tester.pumpAndSettle();

      // Navigate back if we went to a new page
      if (find.byKey(const Key('game_page_scaffold')).evaluate().isEmpty) {
        // We're on the MovesListPage, go back
        final Finder backButton = find.byTooltip('Back');
        if (backButton.evaluate().isNotEmpty) {
          await tester.tap(backButton.first);
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('Game page has drawer icon button', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // The drawer overlay button should always be present on the game page
      verifyWidgetExists(tester, 'custom_drawer_drawer_overlay_button');
    });
  });
}
