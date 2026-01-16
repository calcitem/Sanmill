// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Integration test: Engine startup during app lifecycle changes

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/shared/services/logger.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Engine Lifecycle Tests', () {
    testWidgets(
      'Engine should remain functional after rapid background/foreground transitions',
      (WidgetTester tester) async {
        // Build the game page
        await tester.pumpWidget(
          MaterialApp(home: GamePage(GameMode.humanVsAi)),
        );

        // Wait for initial build
        await tester.pumpAndSettle();

        // Simulate app going to background during engine startup
        logger.i('[TEST] Simulating lifecycle: paused');
        final TestWidgetsFlutterBinding binding = tester.binding;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 50));

        // Simulate app resuming
        logger.i('[TEST] Simulating lifecycle: resumed');
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 100));

        // Wait for engine to be ready
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Verify controller is ready
        expect(
          GameController().isControllerReady,
          true,
          reason: 'Controller should be ready after resume',
        );

        expect(
          GameController().isControllerActive,
          true,
          reason: 'Controller should be active after resume',
        );

        // Try to tap on the board
        // Find a valid square on the board (center position)
        final Finder boardFinder = find.byType(CustomPaint).first;
        expect(boardFinder, findsOneWidget);

        // Tap on the center of the board
        await tester.tap(boardFinder);
        await tester.pumpAndSettle();

        // The tap should have been processed
        // (We can't easily verify the exact game state, but we verify no crash)
        logger.i('[TEST] Tap processed successfully');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'Multiple rapid lifecycle changes should not break engine',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: GamePage(GameMode.humanVsAi)),
        );

        await tester.pumpAndSettle();

        final TestWidgetsFlutterBinding binding = tester.binding;

        // Simulate rapid background/foreground cycles
        for (int i = 0; i < 3; i++) {
          logger.i('[TEST] Cycle $i: paused');
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump(const Duration(milliseconds: 100));

          logger.i('[TEST] Cycle $i: resumed');
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Wait for stabilization
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Verify system is still functional
        expect(GameController().isControllerReady, true);
        expect(GameController().isControllerActive, true);

        // Try to interact
        final Finder boardFinder = find.byType(CustomPaint).first;
        await tester.tap(boardFinder);
        await tester.pumpAndSettle();

        logger.i('[TEST] System remains functional after multiple cycles');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
