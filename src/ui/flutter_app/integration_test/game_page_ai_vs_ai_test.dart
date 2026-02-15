// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_page_ai_vs_ai_test.dart
//
// Integration tests for the AI vs AI game page.
// Verifies that AI vs AI mode loads correctly and basic
// operations like starting a new game function properly.

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

  group('AI vs AI Game Page', () {
    testWidgets('AI vs AI page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      // Configure fast AI to avoid long waits
      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Navigate to AI vs AI
      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Toolbar items present in AI vs AI mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Verify toolbar items are present
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');
      verifyWidgetExists(tester, 'play_area_toolbar_item_move');
      verifyWidgetExists(tester, 'play_area_toolbar_item_info');
    });

    testWidgets('Start new game in AI vs AI mode', (WidgetTester tester) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Allow AI to make a few moves
      await delayAndPump(tester, const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Start a new game
      await startNewGame(tester);

      // Verify the game page is still displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Game options modal in AI vs AI mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Open game options
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify the modal opened with the New Game option
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be visible in AI vs AI mode',
      );
    });
  });
}
