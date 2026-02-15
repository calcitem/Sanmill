// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_page_setup_position_test.dart
//
// Integration tests for the Setup Position game page.
// Verifies that the setup position mode loads correctly
// and unique UI elements for this mode are present.

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

  group('Setup Position Game Page', () {
    testWidgets('Setup position page loads correctly', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Verify the game page scaffold is displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Camera button visible in setup position mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // In Setup Position mode, the camera (image recognition) button
      // should be visible in the top-right corner
      final Finder cameraButton = find.byKey(
        const Key('game_page_image_recognition_button'),
      );
      expect(
        cameraButton,
        findsOneWidget,
        reason: 'Camera button should be visible in Setup Position mode',
      );
    });

    testWidgets('Toolbar items present in setup position mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Main toolbar items should still be present
      verifyWidgetExists(tester, 'play_area_toolbar_item_game');
      verifyWidgetExists(tester, 'play_area_toolbar_item_options');
      verifyWidgetExists(tester, 'play_area_toolbar_item_move');
      verifyWidgetExists(tester, 'play_area_toolbar_item_info');
    });

    testWidgets('Drawer icon present in setup position mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Drawer overlay button should be present
      verifyWidgetExists(tester, 'custom_drawer_drawer_overlay_button');
    });
  });
}
