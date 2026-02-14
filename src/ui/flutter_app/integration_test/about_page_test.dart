// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// about_page_test.dart
//
// Integration tests for the About page.
// Verifies that the about page loads correctly and all information
// tiles (version, license, source code, etc.) are present.
//
// Note: The about page is skipped in EnvironmentConfig.test mode,
// so these tests set test=false temporarily.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/shared/services/environment_config.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> dbBackup;
  late bool originalTestMode;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
    initBitboards();

    // Save original test mode so we can restore it
    originalTestMode = EnvironmentConfig.test;
    // About page is skipped when test=true, so we keep it false
    EnvironmentConfig.test = false;
  });

  tearDownAll(() async {
    EnvironmentConfig.test = originalTestMode;
    await restoreDatabase(dbBackup);
  });

  group('About Page', () {
    testWidgets('Page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Help group → About
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify the about page scaffold
      verifyPageDisplayed(tester, 'about_page_scaffold');
    });

    testWidgets('Version info tile is present', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify version info tile
      verifyWidgetExists(tester, 'settings_list_tile_version_info');
    });

    testWidgets('License tile is present', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify license tile
      verifyWidgetExists(tester, 'settings_list_tile_license');
    });

    testWidgets('Source code tile is present', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify source code tile
      verifyWidgetExists(tester, 'settings_list_tile_source_code');
    });

    testWidgets('OSS licenses tile is present', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify OSS licenses tile
      verifyWidgetExists(tester, 'settings_list_tile_oss_licenses');
    });

    testWidgets('Help improve translate tile is present', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify help improve translate tile
      verifyWidgetExists(tester, 'settings_list_tile_help_improve_translate');
    });

    testWidgets('Thanks tile is present', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Verify thanks tile
      verifyWidgetExists(tester, 'settings_list_tile_thanks');
    });

    testWidgets('EULA tile is present on Linux', (WidgetTester tester) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // On Linux/Windows/Android, the EULA tile should be present
      verifyWidgetExists(tester, 'settings_list_tile_eula');
    });

    testWidgets('Version info tile opens version dialog', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );

      // Tap version info tile
      await tester.tap(
        find.byKey(const Key('settings_list_tile_version_info')),
      );
      await tester.pumpAndSettle();

      // Verify the version dialog appeared
      final Finder versionDialog = find.byKey(const Key('version_dialog'));
      expect(
        versionDialog,
        findsOneWidget,
        reason: 'Version dialog should be displayed',
      );

      // Dismiss the dialog
      final Finder okButton = find.byKey(const Key('version_dialog_ok_button'));
      expect(okButton, findsOneWidget);
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    });

    testWidgets('Navigate to about and back to game', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to About
      await navigateToGroupChild(
        tester,
        'drawer_item_help_group',
        'drawer_item_about_child',
      );
      verifyPageDisplayed(tester, 'about_page_scaffold');

      // Navigate back to game
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });
  });
}
