// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test_data.dart

// ignore_for_file: avoid_classes_with_only_static_members, always_specify_types, avoid_redundant_argument_values

import 'automated_move_test_models.dart';

/// Sample test configurations for automated move testing
class AutomatedMoveTestData {
  /// Sample test case based on the first example move list provided
  static const MoveListTestCase movingWhiteInterventionWin = MoveListTestCase(
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
  static const MoveListTestCase movingBlackMillCapture = MoveListTestCase(
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
  static const MoveListTestCase placingWhiteIntervention = MoveListTestCase(
    id: 'edge_case_1',
    description:
        'Placing phase / White / interventionCapture / Already capture 1 piece',
    moveList: '''
 1.    d2    d6
 2.    a1    g7
 3.    g1    a7
 4.    d7
''',
    expectedSequences: ['xa7 xg7', 'xg7 xa7'],
  );

  /// Test case for short game with captures
  static const MoveListTestCase placingWhiteCrossMillCapture = MoveListTestCase(
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
  static const MoveListTestCase placingWhiteTwoCaptured = MoveListTestCase(
    id: 'short_simple_game',
    description:
        'Placing phase / White / interventionCapture / cross (2 choices intervention) / interventionCapture will capture piece in mill / Already capture 2 pieces',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4xa4xc4
''',
    unexpectedSequences: ['xb2 xb6', 'xb6 xb2'],
  );

  /// Test case for intervention capture - single piece from cross line
  static const MoveListTestCase placingWhiteSingleCaptureA4 = MoveListTestCase(
    id: 'intervention_single_a4',
    description:
        'Placing phase / White / interventionCapture / cross center / Capture only one piece (a4) from cross line',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4xa4
''',
    expectedSequences: ['xc4'],
  );

  /// Test case for intervention capture - single piece from square edge line
  static const MoveListTestCase placingWhiteSingleCaptureB2 = MoveListTestCase(
    id: 'intervention_single_b2',
    description:
        'Placing phase / White / interventionCapture / cross center / Capture only one piece (b2) from square edge line',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4xb2
''',
    // AI can choose either line, but must remove both pieces from the same line
    expectedSequences: ['xb6'],
  );

  /// Test case for intervention capture - both pieces from square edge line
  static const MoveListTestCase
  placingWhiteVerticalLineCaptured = MoveListTestCase(
    id: 'intervention_vertical_line',
    description:
        'Placing phase / White / interventionCapture / cross center / Capture both pieces from square edge line (vertical)',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4xb2xb6
''',
    unexpectedSequences: ['xa4 xc4', 'xc4 xa4'],
  );

  /// Test case for 5-move opening
  static const MoveListTestCase placingBlackInterventionMill = MoveListTestCase(
    id: 'five_move_opening',
    description: 'Placing phase / Black / interventionCapture + Mill',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    c5    e5
 5.    a7    b6
''',
    expectedSequences: ['xa7 xc5', 'xc5 xa7', 'xa4', 'xb2', 'xc4'],
  );

  /// Test case for 6-move development
  static const MoveListTestCase placingBlackSixMoveMill = MoveListTestCase(
    id: 'six_move_development',
    description: 'Placing phase / Black / InterventionCapture + Mill',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    d3    c5
 5.    e3    g7
 6.    b6    a7
''',
    expectedSequences: ['xb6', 'xa4', 'xb2', 'xc4', 'xd3', 'xe3'],
  );

  /// Test case for complex endgame with movements
  static const MoveListTestCase movingWhiteCustodianMill = MoveListTestCase(
    id: 'complex_movement_game',
    description:
        'Moving phase / White / custodianCapture + Mill / Select Mill capture / Do not continue to custodianCapture',
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
14.    d7-g7xc4
''',
    unexpectedSequences: ['xf6'],
  );

  /// Test case for 12-move midgame
  static const MoveListTestCase placingWhiteBoardFull = MoveListTestCase(
    id: 'twelve_move_midgame',
    description: 'Placing phase / White / Board full',
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
    expectedSequences: ['xd5 xe5', 'xb4 xe5', 'xb2 xe5'],
  );

  /// Test case for complex capture sequences
  static const MoveListTestCase movingBlackIntervention = MoveListTestCase(
    id: 'complex_capture_game',
    description: 'Moving phase / Black / interventionCapture',
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
    expectedSequences: ['xe4 xg4', 'xg4 xe4'],
  );

  /// Test case for advanced tactical sequences
  static const MoveListTestCase advancedMultipleCaptures = MoveListTestCase(
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
14.    g4-g1    f2-e3xe4
''',
    expectedSequences: ['f4-e4'],
  );

  /// Test case for long tactical game
  static const MoveListTestCase placingWhiteOneCaptured = MoveListTestCase(
    id: 'long_tactical_game',
    description:
        'Placing phase / White / interventionCapture / Already Capture one',
    moveList: '''
1.    b2    f6
 2.    e5    c3
 3.    a1    c5
 4.    c4xc5
''',
    expectedSequences: ['xc3'],
  );

  /// Test case for alternative long tactical sequence
  static const MoveListTestCase placingWhiteCrossOneCaptured = MoveListTestCase(
    id: 'alt_long_tactical_game',
    description:
        'Placing phase / White / interventionCapture / cross (2 choices intervention) / Already capture 1 pieces',
    moveList: '''
 1.    d6    b6
 2.    d3    b2
 3.    d5    c4
 4.    e4    a4
 5.    b4xb6
''',
    expectedSequences: ['xb2'],
  );

  /// Test case for complex endgame positioning
  static const MoveListTestCase placingWhiteBothInMill = MoveListTestCase(
    id: 'complex_endgame_positioning',
    description:
        'Placing phase / White / interventionCapture / Capture one of two pieces / two pieces are all in mill',
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
13.    d6-b6
''',
    // TODO: Why can two steps?
    expectedSequences: ['xa7 xc5', 'xc5 xa7'],
  );

  /// Test case for strategic positioning
  static const MoveListTestCase placingWhiteCustodian = MoveListTestCase(
    id: 'strategic_positioning_game',
    description: 'Placing phase / White / custodianCapture',
    moveList: '''
 1.    d2    b4
 2.    f4    d6
 3.    c4    d5
 4.    d7    b6
 5.    b2    f6xd7
 6.    a4
''',
    expectedSequences: ['xb4'],
  );

  /// Test case for very long tactical game
  static const MoveListTestCase placingWhiteDoubleCustodian = MoveListTestCase(
    id: 'very_long_tactical_game',
    description:
        'Placing phase / White / 2 custodianCapture / Already capture 1 pieces',
    moveList: '''
 1.    d2    c4
 2.    f4    d6
 3.    b4    b6
 4.    d1    d3
 5.    c5    f6xb4
 6.    e3    a1
 7.    c3xc4
''',
    unexpectedSequences: ['xd3'],
  );

  /// Test case for standard 12-move opening
  static const MoveListTestCase placingBlackFullBoard = MoveListTestCase(
    id: 'standard_twelve_move_opening',
    description: 'Placing phase / Black / custodianCapture / Board is full',
    moveList: '''
  1.    f6    f2
 2.    b2    b6
 3.    g1    e3
 4.    a7    c5
 5.    d6    a1
 6.    c3    g7
 7.    e5    g4
 8.    f4    d1
 9.    d2    d5
10.    a4    b4
11.    c4xb4    e4xf4
12.    d3    d7
''',
    expectedSequences: ['xd6'],
  );

  /// Test case that should be disabled by default
  static const MoveListTestCase disabledDemo = MoveListTestCase(
    id: 'disabled_test',
    description: 'This test is disabled for demonstration',
    moveList: '''
 1.    b2    f6
''',
    expectedSequences: ['Any sequence'],
    enabled: false,
  );

  /// Example test case demonstrating unexpected sequences
  static const MoveListTestCase unexpectedSequenceExample = MoveListTestCase(
    id: 'unexpected_sequence_example',
    description: 'Example test with unexpected sequences',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
''',
    expectedSequences: [
      // Any sequence that is NOT in unexpectedSequences will pass
      // This is useful when there are many possible good moves
      // but only a few bad moves to avoid
      'PLACEHOLDER_EXPECTED',
    ],
    unexpectedSequences: [
      // These specific sequences should cause test failure
      'b4',
      'd3',
    ],
    enabled: false, // Disabled by default for demonstration
  );

  /// Test case for custodian capture with mill - piece in mill already removed
  static const MoveListTestCase
  placingBlackCustodianMillRemoved = MoveListTestCase(
    id: 'placing_black_custodian_mill_removed',
    description:
        'Placing phase / Black / custodianCapture + Mill / Already remove piece in mill',
    moveList: '''
 1.    a1    b6
 2.    d5    d3
 3.    a7    d2
 4.    e5    d1xa1
 5.    c5xd2
''',
    unexpectedSequences: ['xb6'],
  );

  /// Test case for intervention capture with mill - other piece already removed
  static const MoveListTestCase
  placingBlackInterventionMillOtherRemoved = MoveListTestCase(
    id: 'placing_black_intervention_mill_other_removed',
    description:
        'Placing phase / Black / interventionCapture + Mill / Already remove other piece',
    moveList: '''
 1.    a1    c5
 2.    d6    a7
 3.    f6    b4
 4.    b6xb4
''',
    unexpectedSequences: ['xa7', 'xc5'],
  );

  /// Test case for intervention capture with mill - one intervention piece already removed
  static const MoveListTestCase
  placingWhiteInterventionMillOneRemoved = MoveListTestCase(
    id: 'placing_white_intervention_mill_one_removed',
    description:
        'Placing phase / White / interventionCapture + Mill / Already remove one of interventionCapture pieces',
    moveList: '''
 1.    a1    c5
 2.    d6    a7
 3.    f6    b4
 4.    b6xa7
''',
    expectedSequences: ['xc5'],
  );

  /// Custodian capture and intervention capture test configuration
  /// Comprehensive tests for both capture mechanisms across all game phases
  static const AutomatedMoveTestConfig
  custodianCaptureAndInterventionCaptureTestConfig = AutomatedMoveTestConfig(
    configName: 'Custodian & Intervention Capture Tests',
    batchDescription:
        'Comprehensive tests for custodian capture and intervention capture mechanisms across all game phases',
    testCases: [
      movingWhiteInterventionWin,
      movingBlackMillCapture,
      placingWhiteIntervention,
      placingWhiteCrossMillCapture,
      placingWhiteTwoCaptured,
      placingWhiteSingleCaptureA4,
      placingWhiteSingleCaptureB2,
      placingWhiteVerticalLineCaptured,
      placingBlackInterventionMill,
      placingBlackSixMoveMill,
      movingWhiteCustodianMill,
      placingWhiteBoardFull,
      movingBlackIntervention,
      advancedMultipleCaptures,
      placingWhiteOneCaptured,
      placingWhiteCrossOneCaptured,
      placingWhiteBothInMill,
      placingWhiteCustodian,
      placingWhiteDoubleCustodian,
      placingBlackFullBoard,
      placingBlackCustodianMillRemoved,
      placingBlackInterventionMillOtherRemoved,
      placingWhiteInterventionMillOneRemoved,
      disabledDemo,
    ],
    maxWaitTimeMs: 30000, // 30 seconds timeout for comprehensive capture tests
    stopOnFirstFailure: false,
  );

  /// Get all available test configurations
  static List<AutomatedMoveTestConfig> getAllConfigurations() {
    return [custodianCaptureAndInterventionCaptureTestConfig];
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
    List<String>? unexpectedSequences,
    bool enabled = true,
  }) {
    return MoveListTestCase(
      id: id,
      description: description,
      moveList: moveList,
      expectedSequences: [expectedSequence],
      unexpectedSequences: unexpectedSequences,
      enabled: enabled,
    );
  }

  /// Helper method to create a test case with multiple expected sequences
  static MoveListTestCase createMultiOptionTestCase({
    required String id,
    required String description,
    required String moveList,
    List<String>? expectedSequences,
    List<String>? unexpectedSequences,
    bool enabled = true,
  }) {
    return MoveListTestCase(
      id: id,
      description: description,
      moveList: moveList,
      expectedSequences: expectedSequences,
      unexpectedSequences: unexpectedSequences,
      enabled: enabled,
    );
  }
}
