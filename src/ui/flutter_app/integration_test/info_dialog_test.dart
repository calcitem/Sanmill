// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// info_dialog_test.dart
//
// Integration tests for the Info dialog.
// Verifies that the info dialog opens from the toolbar, displays
// game information, and can be dismissed properly.

import 'package:flutter/material.dart';
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

  group('Info Dialog', () {
    testWidgets('Info dialog opens from toolbar', (WidgetTester tester) async {
      await initApp(tester);

      // Tap the Info toolbar item
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // The info dialog should be displayed as an AlertDialog
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'Info dialog (AlertDialog) should be displayed',
      );
    });

    testWidgets('Info dialog has OK button', (WidgetTester tester) async {
      await initApp(tester);

      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // Look for the OK button to dismiss
      final Finder okButton = find.text('OK');
      expect(
        okButton,
        findsWidgets,
        reason: 'OK button should be present in info dialog',
      );
    });

    testWidgets('Info dialog can be dismissed', (WidgetTester tester) async {
      await initApp(tester);

      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // Verify dialog is shown
      expect(find.byType(AlertDialog), findsOneWidget);

      // Dismiss by tapping OK
      final Finder okButton = find.text('OK');
      await tester.tap(okButton.first);
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Info dialog should be dismissed after tapping OK',
      );

      // Game page should still be displayed
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Info dialog in Human vs Human mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Open info dialog
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // Verify dialog is shown
      expect(find.byType(AlertDialog), findsOneWidget);

      // Dismiss
      final Finder okButton = find.text('OK');
      await tester.tap(okButton.first);
      await tester.pumpAndSettle();
    });

    testWidgets('Info dialog in Setup Position mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      // Open info dialog
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');

      // Verify dialog is shown
      expect(find.byType(AlertDialog), findsOneWidget);

      // Dismiss
      final Finder okButton = find.text('OK');
      await tester.tap(okButton.first);
      await tester.pumpAndSettle();
    });
  });
}
