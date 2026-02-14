// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_options_modal_test.dart
//
// Integration tests for the Game Options modal dialog.
// Verifies that the modal displays the correct set of options
// depending on the game state (fresh vs active game), and that
// selecting options produces the expected behavior.

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

  late Map<String, dynamic> dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('Game Options Modal', () {
    testWidgets('Modal opens with essential options', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Open the game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify essential options are present
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should always be present',
      );

      expect(
        find.byKey(const Key('load_game_option')),
        findsOneWidget,
        reason: 'Load Game option should be present on desktop',
      );

      expect(
        find.byKey(const Key('import_game_option')),
        findsOneWidget,
        reason: 'Import Game option should be present on desktop',
      );
    });

    testWidgets('New game from fresh state - no confirmation dialog', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Open modal and tap New Game
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');
      await tester.tap(find.byKey(const Key('new_game_option')));
      await tester.pumpAndSettle();

      // From fresh state, restart dialog should not appear
      expect(
        find.byKey(const Key('restart_game_yes_button')),
        findsNothing,
        reason: 'Restart confirmation should not appear for a fresh game',
      );

      // Game page should still be displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Modal in Human vs Human mode', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Open the game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify New Game option is present
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be present in HvH mode',
      );
    });

    testWidgets('Modal in AI vs AI mode', (WidgetTester tester) async {
      await initApp(tester);

      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Navigate to AI vs AI
      await navigateToDrawerItem(tester, 'drawer_item_ai_vs_ai');

      // Open the game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify New Game option is present
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be present in AI vs AI mode',
      );
    });

    testWidgets('Modal in Setup Position mode', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Open the game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify New Game and Import options are present
      expect(
        find.byKey(const Key('new_game_option')),
        findsOneWidget,
        reason: 'New Game option should be present in Setup Position mode',
      );
      expect(
        find.byKey(const Key('import_game_option')),
        findsOneWidget,
        reason: 'Import option should be present in Setup Position mode',
      );
    });

    testWidgets('Dismiss modal without selecting an option', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Open the game options modal
      await tapToolbarItem(tester, 'play_area_toolbar_item_game');

      // Verify modal is open
      expect(find.byKey(const Key('new_game_option')), findsOneWidget);

      // Dismiss by tapping outside the modal (press Escape or tap barrier)
      // Since this is a SimpleDialog, tapping outside should dismiss it
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // Game page should still be displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });
  });
}
