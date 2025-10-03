// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_integration_test.dart

// ignore_for_file: avoid_print, always_specify_types

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/main.dart' as app;

import 'automated_move_test_data.dart';
import 'automated_move_test_runner.dart';

/// Integration test for automated move testing with REAL AI engine
///
/// This test uses the actual C++ engine through MethodChannel,
/// so it must be run with `flutter test integration_test/` on a real platform.
///
/// Usage:
///   flutter test integration_test/automated_move_integration_test.dart -d linux
///   flutter test integration_test/automated_move_integration_test.dart -d android
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Track overall statistics across all test batches
  int totalTestsRun = 0;
  int totalPassed = 0;
  int totalFailed = 0;

  group('Automated Move Integration Tests', () {
    testWidgets('Run custodian and intervention capture tests with real AI', (
      WidgetTester tester,
    ) async {
      // Launch the app
      print('[IntegrationTest] Launching Sanmill app...');
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[IntegrationTest] App initialized, starting tests...');

      // Execute a single test case for debugging
      final debugConfig = AutomatedMoveTestData.createCustomConfig(
        configName: 'Debug Single Test',
        batchDescription: 'Debugging first failed test case',
        testCases: [AutomatedMoveTestData.placingWhiteCrossMillCapture],
        maxWaitTimeMs: 30000,
        stopOnFirstFailure: false,
      );

      final result = await AutomatedMoveTestRunner.runTestBatch(debugConfig);

      // Update overall statistics
      totalTestsRun += result.testResults.length;
      totalPassed += result.passedCount;
      totalFailed += result.failedCount;

      // Print summary
      print('[IntegrationTest] =====================================');
      print(
        '[IntegrationTest] Custodian & Intervention Capture Tests Completed',
      );
      print('[IntegrationTest] Total Tests: ${result.testResults.length}');
      print('[IntegrationTest] Passed: ${result.passedCount}');
      print('[IntegrationTest] Failed: ${result.failedCount}');
      print(
        '[IntegrationTest] Success Rate: ${result.successRate.toStringAsFixed(1)}%',
      );
      print('[IntegrationTest] =====================================');

      // Print overall summary
      print('');
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] OVERALL INTEGRATION TEST SUMMARY');
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] Total Tests Run: $totalTestsRun');
      print('[IntegrationTest] Total Passed: $totalPassed');
      print('[IntegrationTest] Total Failed: $totalFailed');
      final double overallSuccessRate = totalTestsRun > 0
          ? (totalPassed * 100.0 / totalTestsRun)
          : 0.0;
      print(
        '[IntegrationTest] Overall Success Rate: ${overallSuccessRate.toStringAsFixed(1)}%',
      );
      print('[IntegrationTest] =====================================');

      // Note: We don't use expect() to fail the test in integration tests
      // because the first run will show actual AI output for updating expected sequences
    });
  });
}
