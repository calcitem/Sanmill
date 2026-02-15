// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_interaction_test.dart
//
// Integration tests for board interactions.
// Verifies that tapping on the game board works in different game modes,
// pieces can be placed, and the game state updates correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
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

  group('Board Interaction', () {
    testWidgets('Tap on game board in Human vs AI mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Configure fast AI
      DB().generalSettings = DB().generalSettings.copyWith(
        skillLevel: 1,
        moveTime: 0,
      );

      // Start a new game to ensure clean state
      await startNewGame(tester);

      // Find the game board by looking for CustomPaint widgets
      final Finder customPaintWidgets = find.byType(CustomPaint);
      expect(
        customPaintWidgets,
        findsWidgets,
        reason: 'There should be CustomPaint widgets for the game board',
      );

      // Tap on the center of the board area
      // The board is rendered as a CustomPaint, tap on the first one
      await tester.tap(customPaintWidgets.first);
      await tester.pumpAndSettle();

      // The app should not crash after tapping the board
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Tap on board in Human vs Human mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Start a new game
      await startNewGame(tester);

      // Find the board
      final Finder customPaintWidgets = find.byType(CustomPaint);
      expect(customPaintWidgets, findsWidgets);

      // Tap on the board area
      await tester.tap(customPaintWidgets.first);
      await tester.pumpAndSettle();

      // App should not crash
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Multiple taps on board do not crash', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Human vs Human for predictable behavior
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Start fresh
      await startNewGame(tester);

      final Finder customPaintWidgets = find.byType(CustomPaint);
      expect(customPaintWidgets, findsWidgets);

      // Perform multiple taps at different positions
      final Finder firstPaint = customPaintWidgets.first;
      final Offset center = tester.getCenter(firstPaint);
      final Size size = tester.getSize(firstPaint);

      // Tap at various positions around the board
      for (int i = 0; i < 5; i++) {
        final double dx = center.dx + (i - 2) * (size.width / 8);
        final double dy = center.dy + (i - 2) * (size.height / 8);
        await tester.tapAt(Offset(dx, dy));
        await tester.pumpAndSettle();
      }

      // App should remain functional
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Board tap in setup position mode', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Navigate to Setup Position
      await navigateToDrawerItem(tester, 'drawer_item_setup_position');

      final Finder customPaintWidgets = find.byType(CustomPaint);
      expect(customPaintWidgets, findsWidgets);

      // Tap on the board to place a piece in setup mode
      await tester.tap(customPaintWidgets.first);
      await tester.pumpAndSettle();

      // App should not crash
      verifyPageDisplayed(tester, 'game_page_scaffold');
    });

    testWidgets('Game page background renders correctly', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Verify the background container or image is present
      final Finder backgroundContainer = find.byKey(
        const Key('game_page_background_container'),
      );
      final Finder backgroundImage = find.byKey(
        const Key('game_page_background_image'),
      );

      // One of them should be present (either solid color or image)
      expect(
        backgroundContainer.evaluate().isNotEmpty ||
            backgroundImage.evaluate().isNotEmpty,
        isTrue,
        reason: 'Either background container or image should be present',
      );
    });

    testWidgets('Game page stack structure is correct', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      // Verify the game page stack exists
      verifyWidgetExists(tester, 'game_page_stack');

      // Verify the align for the game board exists
      verifyWidgetExists(tester, 'game_page_align_gameboard');

      // Verify the drawer icon alignment exists
      verifyWidgetExists(tester, 'game_page_drawer_icon_align');
    });

    testWidgets('New game resets the board state', (WidgetTester tester) async {
      await initApp(tester);

      // Navigate to Human vs Human
      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');

      // Start a new game to have clean state
      await startNewGame(tester);

      // Verify the game controller is in a fresh state
      expect(
        GameController().position.phase,
        equals(Phase.placing),
        reason: 'After new game, position should be in placing phase',
      );
    });

    testWidgets('Game recorder is empty after new game', (
      WidgetTester tester,
    ) async {
      await initApp(tester);

      await navigateToDrawerItem(tester, 'drawer_item_human_vs_human');
      await startNewGame(tester);

      // After a new game, the game recorder should have no moves
      expect(
        GameController().gameRecorder.mainlineMoves.isEmpty,
        isTrue,
        reason: 'Game recorder should be empty after new game',
      );
    });
  });
}
