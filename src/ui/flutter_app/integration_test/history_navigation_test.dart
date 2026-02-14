// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// history_navigation_test.dart
//
// Integration tests for the history navigation toolbar.
// Verifies that the history toolbar appears when enabled, and that
// its buttons (take back, step forward, etc.) are present.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
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

  group('History Navigation Toolbar', () {
    testWidgets('History toolbar visible when enabled', (
      WidgetTester tester,
    ) async {
      // Enable the history navigation toolbar
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: true,
      );

      await initApp(tester);

      // Verify history navigation buttons are present
      verifyWidgetExists(tester, 'play_area_history_nav_take_back_all');
      verifyWidgetExists(tester, 'play_area_history_nav_take_back');
      verifyWidgetExists(tester, 'play_area_history_nav_step_forward');
      verifyWidgetExists(tester, 'play_area_history_nav_step_forward_all');
    });

    testWidgets('History toolbar hidden when disabled', (
      WidgetTester tester,
    ) async {
      // Disable the history navigation toolbar
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: false,
      );

      await initApp(tester);

      // Verify history navigation buttons are NOT present
      expect(
        find.byKey(const Key('play_area_history_nav_take_back_all')),
        findsNothing,
        reason:
            'Take back all button should not exist when toolbar is disabled',
      );
    });

    testWidgets('Move now button visible on desktop', (
      WidgetTester tester,
    ) async {
      // Enable the history navigation toolbar
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: true,
      );

      await initApp(tester);

      // On desktop (non-small screens), the Move Now button should be present
      final Finder moveNowButton = find.byKey(
        const Key('play_area_history_nav_move_now'),
      );
      // This may or may not be present depending on screen size detection
      // On Linux desktop, it should typically be present
      expect(
        moveNowButton,
        findsOneWidget,
        reason:
            'Move Now button should be visible on desktop (non-small screen)',
      );
    });

    testWidgets('History toolbar buttons in HvH mode', (
      WidgetTester tester,
    ) async {
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: true,
      );

      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // History navigation should still be available
      verifyWidgetExists(tester, 'play_area_history_nav_take_back_all');
      verifyWidgetExists(tester, 'play_area_history_nav_take_back');
      verifyWidgetExists(tester, 'play_area_history_nav_step_forward');
      verifyWidgetExists(tester, 'play_area_history_nav_step_forward_all');
    });

    testWidgets('Toggle history toolbar via display settings', (
      WidgetTester tester,
    ) async {
      // Start with toolbar enabled
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: true,
      );

      await initApp(tester);

      // Verify toolbar is visible
      verifyWidgetExists(tester, 'play_area_history_nav_take_back');

      // Disable toolbar
      DB().displaySettings = DB().displaySettings.copyWith(
        isHistoryNavigationToolbarShown: false,
      );
      await tester.pumpAndSettle();

      // Verify toolbar is hidden
      expect(
        find.byKey(const Key('play_area_history_nav_take_back')),
        findsNothing,
        reason: 'Take back button should disappear when toolbar is disabled',
      );
    });
  });
}
