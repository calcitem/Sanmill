// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test.dart

// ignore_for_file: avoid_print, always_specify_types, prefer_const_declarations

import 'package:flutter_test/flutter_test.dart';

import 'automated_move_test_data.dart';
import 'automated_move_test_models.dart';
import 'automated_move_test_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Note: We are NOT mocking the engine channel because we want to use the real AI engine
  // The C++ engine must be compiled and available for these tests to work properly

  setUp(() {
    // No engine mocking - we want real AI execution
    print('[AutomatedMoveTest] Using real AI engine for testing');
  });

  tearDown(() {
    // No cleanup needed since we're not using mocks
  });

  group("Automated Move Tests", () {
    test("Run basic automated move tests", () async {
      // Execute the basic test configuration
      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.basicTestConfig,
      );

      // Verify that tests were executed
      expect(
        result.testResults,
        isNotEmpty,
        reason: 'Should have executed at least one test',
      );

      // Print detailed results for manual verification
      print('Test batch completed: ${result.config.configName}');
      print('Total tests: ${result.testResults.length}');
      print('Passed: ${result.passedCount}');
      print('Failed: ${result.failedCount}');
      print('Success rate: ${result.successRate.toStringAsFixed(1)}%');

      // Note: The first time you run these tests, they will likely fail because
      // the expected sequences are placeholders. Check the test output to see
      // the actual AI-generated sequences, then update the test data with the
      // correct expected sequences for future runs.
    });

    test("Run quick validation tests", () async {
      // Execute the quick test configuration
      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.quickTestConfig,
      );

      // Verify that the quick test was executed
      expect(
        result.testResults,
        hasLength(1),
        reason: 'Quick test should execute exactly one test case',
      );

      // Verify that the test case was the expected one
      expect(
        result.testResults.first.testCase.id,
        equals('edge_case_1'),
        reason: 'Should execute the edge case test',
      );
    });

    test("Test configuration with disabled test cases", () async {
      // Create a configuration that includes a disabled test
      final AutomatedMoveTestConfig configWithDisabled =
          AutomatedMoveTestData.createCustomConfig(
            configName: 'Test with Disabled Cases',
            batchDescription: 'Testing that disabled test cases are skipped',
            testCases: [
              AutomatedMoveTestData.sampleTestCase1,
              AutomatedMoveTestData.disabledTest, // This should be skipped
            ],
          );

      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        configWithDisabled,
      );

      // Should only execute the enabled test case
      expect(
        result.testResults,
        hasLength(1),
        reason: 'Should skip disabled test cases',
      );

      expect(
        result.testResults.first.testCase.id,
        equals('sample_game_1'),
        reason: 'Should execute only the enabled test case',
      );
    });

    test("Test custom test case creation", () async {
      // Create a custom test case
      final MoveListTestCase customTest =
          AutomatedMoveTestData.createSimpleTestCase(
            id: 'custom_test_1',
            description: 'Custom test case for validation',
            moveList: '''
 1.    d2    d6
 2.    a1    g7
''',
            expectedSequence: 'Custom expected sequence',
          );

      // Create a configuration with the custom test
      final AutomatedMoveTestConfig customConfig =
          AutomatedMoveTestData.createCustomConfig(
            configName: 'Custom Test Configuration',
            batchDescription: 'Testing custom test case creation',
            testCases: [customTest],
            maxWaitTimeMs: 5000,
            stopOnFirstFailure: true,
          );

      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        customConfig,
      );

      // Verify the custom test was executed
      expect(result.testResults, hasLength(1));
      expect(result.testResults.first.testCase.id, equals('custom_test_1'));
      expect(
        result.testResults.first.testCase.description,
        equals('Custom test case for validation'),
      );
    });

    test("Test multi-option expected sequences", () async {
      // Create a test case with multiple expected sequences
      final MoveListTestCase multiOptionTest =
          AutomatedMoveTestData.createMultiOptionTestCase(
            id: 'multi_option_test',
            description: 'Test with multiple valid expected outcomes',
            moveList: '''
 1.    b2    f6
 2.    g7    e5
''',
            expectedSequences: [
              'Option A sequence',
              'Option B sequence',
              'Option C sequence',
            ],
          );

      final AutomatedMoveTestConfig multiOptionConfig =
          AutomatedMoveTestData.createCustomConfig(
            configName: 'Multi-Option Test',
            batchDescription: 'Testing multiple expected sequence validation',
            testCases: [multiOptionTest],
          );

      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        multiOptionConfig,
      );

      // Verify the test was executed
      expect(result.testResults, hasLength(1));
      expect(result.testResults.first.testCase.expectedSequences, hasLength(3));
    });

    test("Run new test cases configuration", () async {
      // Execute the new test cases configuration
      final TestBatchResult result = await AutomatedMoveTestRunner.runTestBatch(
        AutomatedMoveTestData.newTestCasesConfig,
      );

      // Verify that new test cases were executed
      expect(
        result.testResults,
        isNotEmpty,
        reason: 'Should have executed new test cases',
      );

      // Verify that we have the expected number of new test cases
      expect(
        result.testResults.length,
        equals(14), // 14 new test cases added
        reason: 'Should execute all 14 new test cases',
      );

      print('New test cases executed: ${result.testResults.length}');
      print('Configuration: ${result.config.configName}');
    });
  });

  group("Test Data Validation", () {
    test("Validate basic test configuration", () {
      final AutomatedMoveTestConfig config =
          AutomatedMoveTestData.basicTestConfig;

      expect(config.configName, isNotEmpty);
      expect(config.batchDescription, isNotEmpty);
      expect(config.testCases, isNotEmpty);
      expect(config.maxWaitTimeMs, greaterThan(0));

      // Check that we have both enabled and disabled test cases
      final int enabledCount = config.enabledTestCases.length;
      final int totalCount = config.testCases.length;
      expect(
        enabledCount,
        lessThan(totalCount),
        reason: 'Should have some disabled test cases for testing',
      );
    });

    test("Validate test case structure", () {
      final MoveListTestCase testCase = AutomatedMoveTestData.sampleTestCase1;

      expect(testCase.id, isNotEmpty);
      expect(testCase.description, isNotEmpty);
      expect(testCase.moveList, isNotEmpty);
      expect(testCase.expectedSequences, isNotEmpty);
      expect(testCase.enabled, isTrue);

      // Verify move list format (should contain numbered moves)
      expect(testCase.moveList, contains('1.'));
      expect(testCase.moveList, contains('2.'));
    });

    test("Validate all available configurations", () {
      final List<AutomatedMoveTestConfig> allConfigs =
          AutomatedMoveTestData.getAllConfigurations();

      expect(allConfigs, isNotEmpty);

      for (final AutomatedMoveTestConfig config in allConfigs) {
        expect(config.configName, isNotEmpty);
        expect(config.batchDescription, isNotEmpty);
        expect(config.testCases, isNotEmpty);
        expect(config.maxWaitTimeMs, greaterThan(0));
      }
    });
  });
}
