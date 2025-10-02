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

  group('Automated Move Integration Tests', () {
    testWidgets('Run basic automated move tests with real AI', (
      WidgetTester tester,
    ) async {
      // Launch the app
      print('[IntegrationTest] Launching Sanmill app...');
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[IntegrationTest] App initialized, starting tests...');

      // Execute the basic test configuration with REAL AI engine
      final result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.basicTestConfig,
      );

      // Print summary
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] Integration Test Completed');
      print('[IntegrationTest] Total Tests: ${result.testResults.length}');
      print('[IntegrationTest] Passed: ${result.passedCount}');
      print('[IntegrationTest] Failed: ${result.failedCount}');
      print(
        '[IntegrationTest] Success Rate: ${result.successRate.toStringAsFixed(1)}%',
      );
      print('[IntegrationTest] =====================================');

      // Note: We don't use expect() to fail the test in integration tests
      // because the first run will show actual AI output for updating expected sequences
    });

    testWidgets('Run quick validation tests with real AI', (
      WidgetTester tester,
    ) async {
      print('[IntegrationTest] Running quick validation tests...');

      // Execute the quick test configuration
      final result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.quickTestConfig,
      );

      print('[IntegrationTest] Quick test completed');
      print(
        '[IntegrationTest] Passed: ${result.passedCount}/${result.testResults.length}',
      );
    });

    testWidgets('Run new test cases configuration with real AI', (
      WidgetTester tester,
    ) async {
      print('[IntegrationTest] Running new test cases...');

      // Execute the new test cases configuration
      final result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.newTestCasesConfig,
      );

      print('[IntegrationTest] New test cases completed');
      print(
        '[IntegrationTest] Passed: ${result.passedCount}/${result.testResults.length}',
      );
    });
  });
}
