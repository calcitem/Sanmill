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

  group('Single Test - placingBlackInterventionMill', () {
    testWidgets('Run placingBlackInterventionMill only', (
      WidgetTester tester,
    ) async {
      // Launch the app
      print('[IntegrationTest] Launching Sanmill app...');
      app.main();
      await tester.pumpAndSettle();

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[IntegrationTest] App initialized, starting single test...');

      // Execute ONLY placingBlackInterventionMill (first failed test case)
      final singleTestConfig = AutomatedMoveTestData.createCustomConfig(
        configName: 'Single Test - placingBlackInterventionMill',
        batchDescription: 'Run only placingBlackInterventionMill for debugging',
        testCases: [AutomatedMoveTestData.placingBlackInterventionMill],
        stopOnFirstFailure: true,
      );

      final result = await AutomatedMoveTestRunner.runTestBatch(
        singleTestConfig,
      );

      // Print summary
      print('[IntegrationTest] =====================================');
      print('[IntegrationTest] Single Test Completed');
      print('[IntegrationTest] Test: placingBlackInterventionMill');
      print('[IntegrationTest] ID: five_move_opening');
      print('[IntegrationTest] Passed: ${result.passedCount}');
      print('[IntegrationTest] Failed: ${result.failedCount}');
      print('[IntegrationTest] =====================================');
    });
  });
}
