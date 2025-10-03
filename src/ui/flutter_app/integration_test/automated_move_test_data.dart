// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test_data.dart

// ignore_for_file: avoid_classes_with_only_static_members, always_specify_types, avoid_redundant_argument_values

import 'automated_move_test_models.dart';

/// Sample test configurations for automated move testing
class AutomatedMoveTestData {
  /// Sample test case based on the first example move list provided
  static const MoveListTestCase sampleTestCase1 = MoveListTestCase(
    id: 'sample_game_1',
    description:
        'Moving phase / White / interventionCapture + Mill / interventionCapture will win',
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
      'xa1 xc3',
      'xc3 xa1',
      // TODO: Remove following sequences
      'xd7',
      'xg1',
    ],
  );

  /// Sample test case based on the second example move list provided
  static const MoveListTestCase sampleTestCase2 = MoveListTestCase(
    id: 'sample_game_2',
    description:
        'Moving phase / Black / interventionCapture / interventionCapture will capture piece in mill',
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
      'xc3 xe3',
      'xe3 xc3',
    ],
  );

  /// Test case for edge case handling
  static const MoveListTestCase edgeCaseTest = MoveListTestCase(
    id: 'edge_case_1',
    description: 'Placing phase / White / interventionCapture',
    moveList: '''
 1.    d2    d6
 2.    a1    g7
 3.    g1    a7
''',
    expectedSequences: ['d7'],
  );

  /// Test case for short game with captures
  static const MoveListTestCase shortCaptureTest = MoveListTestCase(
    id: 'short_capture_game',
    description:
        'Placing phase / White / interventionCapture / cross (2 choices intervention) / interventionCapture will capture piece in mill',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4
''',
    expectedSequences: ['xb2 xb6', 'xb6 xb2', 'xa4 xc4', 'xc4 xa4'],
  );

  /// Test case for short game without captures
  static const MoveListTestCase shortSimpleTest = MoveListTestCase(
    id: 'short_simple_game',
    description:
        'Placing phase / White / interventionCapture / cross (2 choices intervention) / interventionCapture will capture piece in mill / Already capture 2 pieces',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4xa4xc4
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_SHORT_SIMPLE'],
  );

  /// Test case for 5-move opening
  static const MoveListTestCase fiveMoveTest = MoveListTestCase(
    id: 'five_move_opening',
    description: 'Test AI response to 5-move opening sequence',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    c5    e5
 5.    a7    b6
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_FIVE_MOVE'],
  );

  /// Test case for 6-move development
  static const MoveListTestCase sixMoveTest = MoveListTestCase(
    id: 'six_move_development',
    description: 'Test AI response to 6-move development sequence',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    d3    c5
 5.    e3    g7
 6.    b6    a7
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_SIX_MOVE'],
  );

  /// Test case for complex endgame with movements
  static const MoveListTestCase complexMovementTest = MoveListTestCase(
    id: 'complex_movement_game',
    description: 'Test AI response to complex game with piece movements',
    moveList: '''
1.    b2    f2
 2.    g1    e3
 3.    a7    a1
 4.    c3    d6
 5.    d7    g7
 6.    d5xd6    c5
 7.    e5    f4
 8.    f6    b6
 9.    g4    e4
10.    d1    b4
11.    a4    c4
12.    d2    d3
13.    f6-d6xg7    f4-f6xd6
14.    d7-g7xc4    f6-f4
15.    g7-f6    b6-d6
16.    a7-b6
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_COMPLEX_MOVEMENT'],
  );

  /// Test case for 12-move midgame
  static const MoveListTestCase twelveMoveTest = MoveListTestCase(
    id: 'twelve_move_midgame',
    description: 'Test AI response to 12-move midgame sequence',
    moveList: '''
1.    b6    b2
 2.    f2    f6
 3.    e5    g7
 4.    c3    a1
 5.    d7    e3
 6.    g1    c5
 7.    a7    b4
 8.    d2    f4
 9.    d6    d5
10.    g4    e4
11.    c4    a4
12.    d3    d1
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_TWELVE_MOVE'],
  );

  /// Test case for complex capture sequences
  static const MoveListTestCase complexCaptureTest = MoveListTestCase(
    id: 'complex_capture_game',
    description: 'Test AI response to complex capture and movement sequences',
    moveList: '''
 1.    b2    b6
 2.    f6    f2
 3.    d3    a1
 4.    a7    c3xb2
 5.    c5xb6    e3xd3
 6.    d2    d6
 7.    b4    g7
 8.    g1    e5xf6
 9.    e4xe5xe3    f4
10.    g4xf4    c4
11.    d5    a4xb4
12.    d7xd6    d1
13.    d2-b2xc3xa1    f2-f4
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_COMPLEX_CAPTURE'],
  );

  /// Test case for advanced tactical sequences
  static const MoveListTestCase advancedTacticalTest = MoveListTestCase(
    id: 'advanced_tactical_game',
    description:
        'Test AI response to advanced tactical sequences with multiple captures',
    moveList: '''
 1.    b2    b6
 2.    c5    a7
 3.    g1    c3
 4.    f6    a4
 5.    g4    a1xg4
 6.    e4    e5
 7.    g7    d3
 8.    e3    f2xg1xe3
 9.    d1    d6
10.    d5    d7
11.    f4    b4
12.    c4    d2
13.    g7-g4xf2    d2-f2
14.    g4-g1    f2-e3xe4xf4
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_ADVANCED_TACTICAL'],
  );

  /// Test case for long tactical game
  static const MoveListTestCase longTacticalTest = MoveListTestCase(
    id: 'long_tactical_game',
    description:
        'Test AI response to long tactical game with complex movements',
    moveList: '''
1.    b2    f6
 2.    e5    c3
 3.    a1    c5
 4.    c4    b6
 5.    g7xf6    a7xc4
 6.    g1    d3
 7.    e3    f2
 8.    g4xf2    e4
 9.    d6    d1
10.    f4    d2xe5
11.    d5    d7
12.    b4    a4
13.    d5-e5xe4    c5-d5xd6
14.    e3-e4xa4    d5-c5xe5
15.    f4-f2
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_LONG_TACTICAL'],
  );

  /// Test case for alternative long tactical sequence
  static const MoveListTestCase altLongTacticalTest = MoveListTestCase(
    id: 'alt_long_tactical_game',
    description: 'Test AI response to alternative long tactical sequence',
    moveList: '''
1.    b2    f6
 2.    e5    c3
 3.    a1    c5
 4.    c4    b6
 5.    g7xf6    a7xc4
 6.    g1    d3
 7.    e3    f2
 8.    g4xf2    e4
 9.    d6    d1
10.    f4    d2xe5
11.    d5    d7
12.    b4    a4
13.    d5-e5xe4    c3-c4
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_ALT_LONG_TACTICAL'],
  );

  /// Test case for complex endgame positioning
  static const MoveListTestCase complexEndgameTest = MoveListTestCase(
    id: 'complex_endgame_positioning',
    description:
        'Test AI response to complex endgame with multiple captures and movements',
    moveList: '''
1.    b2    f6
 2.    e5    c3
 3.    g7xf6    a1xb2
 4.    b6    c5
 5.    g1    c4xg7
 6.    g4    e3
 7.    d7    a7xb6
 8.    b4    d3xd7
 9.    d1    f2
10.    f4    a4xf4
11.    d6    d5
12.    d2    e4
13.    d6-b6    c3-b2xd2
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_COMPLEX_ENDGAME'],
  );

  /// Test case for strategic positioning
  static const MoveListTestCase strategicPositioningTest = MoveListTestCase(
    id: 'strategic_positioning_game',
    description: 'Test AI response to strategic positioning with movements',
    moveList: '''
 1.    d2    b4
 2.    f4    d6
 3.    c4    d5
 4.    d7    b6
 5.    b2    f6xd7
 6.    d7    e5
 7.    e4    c3
 8.    f2xc3    c5xd7
 9.    d7    d1
10.    d2-d3    d1-d2
11.    d3-e3    d2-d1
12.    e3-d3    d1-a1
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_STRATEGIC_POSITIONING'],
  );

  /// Test case for very long tactical game
  static const MoveListTestCase veryLongTacticalTest = MoveListTestCase(
    id: 'very_long_tactical_game',
    description:
        'Test AI response to very long tactical game with extensive movements',
    moveList: '''
1.    d2    c4
 2.    f4    d6
 3.    b4    b6
 4.    d1    d3
 5.    c5    f6xb4
 6.    b4    d7
 7.    d5    g7
 8.    e5xc4    a7xb4
 9.    b2    f2
10.    c5-c4    d3-e3
11.    c4-c5xe3    b6-b4
12.    d2-d3    b4-b6xf4
13.    b2-d2xf2    g7-g4
14.    d2-f2    g4-g7xd3
15.    e5-e4    f6-f4
16.    e4-e5xf4    a7-a4
17.    d1-d2    d7-a7
18.    d2-b2    a4-a1
19.    f2-f4    d6-d7xf4
20.    d5-d6    a7-a4
21.    d6-d5xd7    b6-b4
22.    d5-d6    g7-g4
23.    d6-d5xa4    a1-d6
24.    c5-c4    g4-g1
25.    b2-d2    g1-d7
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_VERY_LONG_TACTICAL'],
  );

  /// Test case for standard 12-move opening
  static const MoveListTestCase standardTwelveMoveTest = MoveListTestCase(
    id: 'standard_twelve_move_opening',
    description: 'Test AI response to standard 12-move opening sequence',
    moveList: '''
 1.    f6    f2
 2.    b2    b6
 3.    g1    e3
 4.    a7    c5
 5.    d6    a1
 6.    c3    g7
 7.    e5    f4
 8.    d2    b4
 9.    g4    e4
10.    a4    c4
11.    d7    d5
12.    d1    d3
''',
    expectedSequences: ['PLACEHOLDER_EXPECTED_SEQUENCE_STANDARD_TWELVE'],
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
    testCases: [
      sampleTestCase1,
      sampleTestCase2,
      edgeCaseTest,
      shortCaptureTest,
      shortSimpleTest,
      disabledTest,
    ],
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
      shortCaptureTest,
      shortSimpleTest,
      fiveMoveTest,
      sixMoveTest,
      complexMovementTest,
      twelveMoveTest,
      complexCaptureTest,
      advancedTacticalTest,
      longTacticalTest,
      altLongTacticalTest,
      complexEndgameTest,
      strategicPositioningTest,
      veryLongTacticalTest,
      standardTwelveMoveTest,
    ],
    maxWaitTimeMs: 30000, // 30 seconds timeout for comprehensive tests
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

  /// Single test configuration for debugging sampleTestCase1
  static const AutomatedMoveTestConfig singleTestConfig =
      AutomatedMoveTestConfig(
        configName: 'Single Test - sample_game_1',
        batchDescription: 'Run only sampleTestCase1 for debugging',
        testCases: [sampleTestCase1],
        maxWaitTimeMs: 10000, // 10 seconds timeout
        stopOnFirstFailure: true,
      );

  /// New test cases configuration for recently added test cases
  static const AutomatedMoveTestConfig newTestCasesConfig =
      AutomatedMoveTestConfig(
        configName: 'New Test Cases',
        batchDescription:
            'Recently added test cases for various game scenarios',
        testCases: [
          shortCaptureTest,
          shortSimpleTest,
          fiveMoveTest,
          sixMoveTest,
          complexMovementTest,
          twelveMoveTest,
          complexCaptureTest,
          advancedTacticalTest,
          longTacticalTest,
          altLongTacticalTest,
          complexEndgameTest,
          strategicPositioningTest,
          veryLongTacticalTest,
          standardTwelveMoveTest,
        ],
        maxWaitTimeMs: 25000, // 25 seconds timeout for new test cases
        stopOnFirstFailure: false,
      );

  /// Get all available test configurations
  static List<AutomatedMoveTestConfig> getAllConfigurations() {
    return [
      basicTestConfig,
      comprehensiveTestConfig,
      quickTestConfig,
      newTestCasesConfig,
    ];
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
