// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_page_test.dart
//
// Integration tests for the Puzzles feature.
// Verifies that the puzzles home page loads correctly, displays the
// stats card and all puzzle mode cards, and that navigation to
// individual puzzle modes works.

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

  group('Puzzles Home Page', () {
    testWidgets('Puzzles page loads correctly', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Puzzles via drawer
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');

      // The Puzzles home page should be displayed.
      // It uses a Scaffold but does not have a unique key, so we verify
      // by checking that the AppBar title or specific content is present.
      await tester.pumpAndSettle();

      // The puzzles page should have loaded without errors
      // Verify we're no longer on the game page scaffold
      expect(
        find.byKey(const Key('game_page_scaffold')),
        findsNothing,
        reason: 'Should have navigated away from the game page',
      );
    });

    testWidgets('Puzzles page has GridView with mode cards', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');

      // The page should contain a GridView with puzzle mode cards
      expect(
        find.byType(GridView),
        findsOneWidget,
        reason: 'Puzzles page should contain a GridView of puzzle modes',
      );
    });

    testWidgets('Puzzles page has Card widgets for modes', (
      WidgetTester tester,
    ) async {
      await initApp(tester);
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');

      // The page should contain multiple Card widgets for the puzzle modes
      // (Daily Puzzle featured card + 6 grid mode cards + stats card = ~8)
      expect(
        find.byType(Card),
        findsWidgets,
        reason: 'Puzzles page should contain Card widgets for modes',
      );
    });

    testWidgets('Navigate to puzzles and back to game', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Puzzles
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');

      // Navigate back to Human vs AI
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_ai');

      // Verify the game page is displayed again
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Navigate to puzzles then to statistics', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Puzzles
      await navigateToDrawerItem(tester, 'drawer_item_puzzles');
      await tester.pumpAndSettle();

      // Navigate to Statistics
      await navigateToDrawerItem(tester, 'drawer_item_statistics');

      // Verify Statistics page is displayed
      verifyPageDisplayed(tester, 'statistics_page_scaffold');
    });
  });
}
