// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Integration test: Engine startup during app lifecycle changes

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/services/logger.dart';

import 'helpers.dart' show disposeTestAudio, initApp;
import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initTestEnvironment);

  setUp(() {
    SoundManager().mute();
    addTearDown(disposeTestAudio);
  });

  group('Engine Lifecycle Tests', () {
    testWidgets(
      'Engine should remain functional after rapid background/foreground transitions',
      (WidgetTester tester) async {
        await initApp(tester);

        final TestWidgetsFlutterBinding binding = tester.binding;
        await _simulateLifecycleRoundTrip(tester, binding);

        await _waitForControllerReady(tester);

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
        await tester.pump(const Duration(milliseconds: 200));

        // The tap should have been processed
        // (We can't easily verify the exact game state, but we verify no crash)
        logger.i('[TEST] Tap processed successfully');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      'Multiple rapid lifecycle changes should not break engine',
      (WidgetTester tester) async {
        await initApp(tester);

        final TestWidgetsFlutterBinding binding = tester.binding;

        // Simulate rapid background/foreground cycles
        for (int i = 0; i < 3; i++) {
          await _simulateLifecycleRoundTrip(tester, binding, cycle: i);
        }

        await _waitForControllerReady(tester);

        // Verify system is still functional
        expect(GameController().isControllerReady, true);
        expect(GameController().isControllerActive, true);

        // Try to interact
        final Finder boardFinder = find.byType(CustomPaint).first;
        await tester.tap(boardFinder);
        await tester.pump(const Duration(milliseconds: 200));

        logger.i('[TEST] System remains functional after multiple cycles');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}

Future<void> _simulateLifecycleRoundTrip(
  WidgetTester tester,
  TestWidgetsFlutterBinding binding, {
  int? cycle,
}) async {
  final String prefix = cycle == null ? '[TEST]' : '[TEST] Cycle $cycle:';

  logger.i('$prefix paused');
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

  logger.i('$prefix resumed');
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitForControllerReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    if (GameController().isControllerReady &&
        GameController().isControllerActive) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    GameController().isControllerReady,
    true,
    reason: 'Controller should become ready within $timeout',
  );
  expect(
    GameController().isControllerActive,
    true,
    reason: 'Controller should become active within $timeout',
  );
}
