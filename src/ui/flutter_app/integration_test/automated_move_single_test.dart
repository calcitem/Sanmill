// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_single_test.dart

// ignore_for_file: avoid_print, always_specify_types

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/main.dart' as app;

import 'automated_move_test_data.dart';
import 'automated_move_test_runner.dart';

/// Integration test for running ONLY sampleTestCase1
///
/// Usage:
///   flutter test integration_test/automated_move_single_test.dart -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Single Test - sample_game_1', () {
    testWidgets('Run sampleTestCase1 only', (WidgetTester tester) async {
      // Launch the app
      print('[IntegrationTest] Launching Sanmill app...');
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[IntegrationTest] App initialized, starting single test...');

      // Execute ONLY sampleTestCase1
      final singleTestConfig = AutomatedMoveTestData.createCustomConfig(
        configName: 'Single Test - sample_game_1',
        batchDescription: 'Run only sampleTestCase1 for debugging',
        testCases: [AutomatedMoveTestData.sampleTestCase1],
        maxWaitTimeMs: 10000,
        stopOnFirstFailure: true,
      );

      final result = await AutomatedMoveTestRunner.runTestBatch(
        singleTestConfig,
      );

      // Print summary
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] Single Test Completed');
      print('[IntegrationTest] Test: sample_game_1');
      print('[IntegrationTest] Passed: ${result.passedCount}');
      print('[IntegrationTest] Failed: ${result.failedCount}');
      print('[IntegrationTest] =====================================');
    });
  });
}
