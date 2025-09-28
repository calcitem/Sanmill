// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test_data.dart

import 'automated_move_test_models.dart';

/// Sample test configurations for automated move testing
class AutomatedMoveTestData {
  /// Sample test case based on the first example move list provided
  static const MoveListTestCase sampleTestCase1 = MoveListTestCase(
    id: 'sample_game_1',
    description: 'Test AI behavior after importing a complete game sequence',
    moveList: '''
 1.    b2    f6
 2.    g7    e5
 3.    b4    a1
 4.    b6xa1    a7
 5.    d2    c5xb6
 6.    d5xe5xc5    c3
 7.    f2xf6    g1
 8.    e4    d1
 9.    c4    a4
10.    d6    d7
11.    f4    g4
12.    e3    d3xd2
13.    f2-d2xd1xd3    a7-b6
14.    d5-e5xg1    g4-g1
15.    e3-f2xb6    a4-a1xb2
16.    b4-b2
''',
    expectedSequences: [
      // Expected sequences will be determined by running the test and observing AI behavior
      // These are placeholder values that should be updated after initial test runs
      'PLACEHOLDER_EXPECTED_SEQUENCE_1',
      'PLACEHOLDER_EXPECTED_SEQUENCE_2',
    ],
  );

  /// Sample test case based on the second example move list provided
  static const MoveListTestCase sampleTestCase2 = MoveListTestCase(
    id: 'sample_game_2',
    description: 'Test AI response to a shorter game sequence',
    moveList: '''
 1.    f6    f2
 2.    b2    b6
 3.    a7    c5
 4.    e3    g1
 5.    d6    d2
 6.    f4    b4
 7.    a4    d7
 8.    a1xd7    e4
 9.    c3xe4    d3
''',
    expectedSequences: [
      // Expected sequences will be determined by running the test and observing AI behavior
      'PLACEHOLDER_EXPECTED_SEQUENCE_A',
      'PLACEHOLDER_EXPECTED_SEQUENCE_B',
    ],
  );

  /// Test case for edge case handling
  static const MoveListTestCase edgeCaseTest = MoveListTestCase(
    id: 'edge_case_1',
    description: 'Test AI behavior with unusual move patterns',
    moveList: '''
 1.    d2    d6
 2.    a1    g7
 3.    g1    a7
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_EDGE'],
  );

  /// Test case that should be disabled by default
  static const MoveListTestCase disabledTest = MoveListTestCase(
    id: 'disabled_test',
    description: 'This test is disabled for demonstration',
    moveList: '''
 1.    b2    f6
''',
    expectedSequences: ['Any sequence'],
    enabled: false,
  );

  /// Basic test configuration with sample test cases
  static const AutomatedMoveTestConfig
  basicTestConfig = AutomatedMoveTestConfig(
    configName: 'Basic AI Move Tests',
    batchDescription:
        'Basic automated tests to validate AI move generation after importing move lists',
    testCases: [sampleTestCase1, sampleTestCase2, edgeCaseTest, disabledTest],
    maxWaitTimeMs: 15000, // 15 seconds timeout
    stopOnFirstFailure: false,
  );

  /// Comprehensive test configuration
  static const AutomatedMoveTestConfig
  comprehensiveTestConfig = AutomatedMoveTestConfig(
    configName: 'Comprehensive AI Tests',
    batchDescription:
        'Comprehensive suite of AI behavior tests covering various game scenarios',
    testCases: [
      sampleTestCase1,
      sampleTestCase2,
      edgeCaseTest,
      // Add more test cases here as needed
    ],
    maxWaitTimeMs: 20000, // 20 seconds timeout for comprehensive tests
    stopOnFirstFailure: false,
  );

  /// Quick test configuration for rapid validation
  static const AutomatedMoveTestConfig quickTestConfig =
      AutomatedMoveTestConfig(
        configName: 'Quick Validation Tests',
        batchDescription: 'Quick tests for basic AI functionality validation',
        testCases: [
          edgeCaseTest, // Only run the quick edge case test
        ],
        maxWaitTimeMs: 5000, // 5 seconds timeout for quick tests
        stopOnFirstFailure: true,
      );

  /// Get all available test configurations
  static List<AutomatedMoveTestConfig> getAllConfigurations() {
    return [basicTestConfig, comprehensiveTestConfig, quickTestConfig];
  }

  /// Create a custom test configuration
  static AutomatedMoveTestConfig createCustomConfig({
    required String configName,
    required String batchDescription,
    required List<MoveListTestCase> testCases,
    int maxWaitTimeMs = 10000,
    bool stopOnFirstFailure = false,
  }) {
    return AutomatedMoveTestConfig(
      configName: configName,
      batchDescription: batchDescription,
      testCases: testCases,
      maxWaitTimeMs: maxWaitTimeMs,
      stopOnFirstFailure: stopOnFirstFailure,
    );
  }

  /// Helper method to create a test case with single expected sequence
  static MoveListTestCase createSimpleTestCase({
    required String id,
    required String description,
    required String moveList,
    required String expectedSequence,
    bool enabled = true,
  }) {
    return MoveListTestCase(
      id: id,
      description: description,
      moveList: moveList,
      expectedSequences: [expectedSequence],
      enabled: enabled,
    );
  }

  /// Helper method to create a test case with multiple expected sequences
  static MoveListTestCase createMultiOptionTestCase({
    required String id,
    required String description,
    required String moveList,
    required List<String> expectedSequences,
    bool enabled = true,
  }) {
    return MoveListTestCase(
      id: id,
      description: description,
      moveList: moveList,
      expectedSequences: expectedSequences,
      enabled: enabled,
    );
  }
}
