// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_single_test.dart

// ignore_for_file: avoid_print, always_specify_types

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/main.dart' as app;

import 'automated_move_test_data.dart';
import 'automated_move_test_runner.dart';

/// Integration test for running a SINGLE test case for debugging
///
/// Usage:
///   flutter test integration_test/automated_move_single_test.dart -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Single Test - placingWhiteSingleCaptureB2', () {
    testWidgets('Run placingWhiteSingleCaptureB2 only', (
      WidgetTester tester,
    ) async {
      // Launch the app
      print('[IntegrationTest] Launching Sanmill app...');
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[IntegrationTest] App initialized, starting single test...');

      // Execute ONLY placingWhiteSingleCaptureB2 (first failed test case)
      final singleTestConfig = AutomatedMoveTestData.createCustomConfig(
        configName: 'Single Test - placingWhiteSingleCaptureB2',
        batchDescription: 'Run only placingWhiteSingleCaptureB2 for debugging',
        testCases: [AutomatedMoveTestData.placingWhiteSingleCaptureB2],
        stopOnFirstFailure: true,
      );

      final result = await AutomatedMoveTestRunner.runTestBatch(
        singleTestConfig,
      );

      // Print summary
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] Single Test Completed');
      print('[IntegrationTest] Test: placingWhiteSingleCaptureB2');
      print('[IntegrationTest] ID: intervention_single_b2');
      print('[IntegrationTest] Passed: ${result.passedCount}');
      print('[IntegrationTest] Failed: ${result.failedCount}');
      print('[IntegrationTest] =====================================');
    });
  });
}
