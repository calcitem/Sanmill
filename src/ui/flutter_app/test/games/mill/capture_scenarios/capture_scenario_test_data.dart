// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// capture_scenario_test_data.dart
//
// Curated custodian / intervention capture move lists, migrated from master
// `integration_test/automated_move_test_data.dart`.
//
// Only the scenarios that import cleanly under the canonical Rust `tgf-mill`
// rules are kept here.  Master shipped ~16 additional compound-capture move
// lists whose `expectedSequences` were explicit placeholders ("determined by
// running the test and observing AI behavior", "TODO: Why can two steps?").
// Those encode multi-capture outcomes that the oracle-validated Rust rules do
// not reproduce (e.g. a single placement removing two pieces off different
// lines), so they were dropped rather than asserted against placeholder data.
// Rule correctness for custodian / intervention captures is covered directly
// by `crates/tgf-mill/src/rules/tests.rs` and the legacy oracle replay.

import 'capture_scenario_test_models.dart';

abstract final class CaptureScenarioTestData {
  // ---- Positive cases: import cleanly through the native kernel -----------

  /// Placing / White / interventionCapture (already captured 1 piece).
  static const MoveListTestCase placingWhiteIntervention = MoveListTestCase(
    id: 'edge_case_1',
    description: 'Placing / White / interventionCapture',
    moveList: '''
 1.    d2    d6
 2.    a1    g7
 3.    g1    a7
 4.    d7
''',
  );

  /// Placing / White / interventionCapture on a cross line (2 choices).
  static const MoveListTestCase placingWhiteCrossMillCapture = MoveListTestCase(
    id: 'short_capture_game',
    description: 'Placing / White / interventionCapture (cross, 2 choices)',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    b6    b4
''',
  );

  /// Placing / Black / interventionCapture + Mill (5-move opening).
  static const MoveListTestCase placingBlackInterventionMill = MoveListTestCase(
    id: 'five_move_opening',
    description: 'Placing / Black / interventionCapture + Mill',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    c5    e5
 5.    a7    b6
''',
  );

  /// Placing / Black / interventionCapture + Mill (6-move development).
  static const MoveListTestCase placingBlackSixMoveMill = MoveListTestCase(
    id: 'six_move_development',
    description: 'Placing / Black / interventionCapture + Mill',
    moveList: '''
 1.    a4    d6
 2.    c4    d7
 3.    b2    f6
 4.    d3    c5
 5.    e3    g7
 6.    b6    a7
''',
  );

  /// Placing / White / custodianCapture.
  static const MoveListTestCase placingWhiteCustodian = MoveListTestCase(
    id: 'strategic_positioning_game',
    description: 'Placing / White / custodianCapture',
    moveList: '''
 1.    d2    b4
 2.    f4    d6
 3.    c4    d5
 4.    d7    b6
 5.    b2    f6xd7
 6.    a4
''',
  );

  /// Placing / Black / interventionCapture + Mill (other piece already removed).
  static const MoveListTestCase placingBlackInterventionMillOtherRemoved =
      MoveListTestCase(
        id: 'placing_black_intervention_mill_other_removed',
        description:
            'Placing / Black / interventionCapture + Mill (other removed)',
        moveList: '''
 1.    a1    c5
 2.    d6    a7
 3.    f6    b4
 4.    b6xb4
''',
      );

  /// Placing / White / interventionCapture + Mill (one piece already removed).
  static const MoveListTestCase placingWhiteInterventionMillOneRemoved =
      MoveListTestCase(
        id: 'placing_white_intervention_mill_one_removed',
        description:
            'Placing / White / interventionCapture + Mill (one removed)',
        moveList: '''
 1.    a1    c5
 2.    d6    a7
 3.    f6    b4
 4.    b6xa7
''',
      );

  // ---- Negative cases: must be rejected by the kernel importer ------------

  /// Invalid compound capture (removes pieces off two different lines).
  static const MoveListTestCase invalidCaptureImport = MoveListTestCase(
    id: 'invalid_capture_import',
    description: 'Negative: invalid compound capture must fail to import',
    moveList: '''
 1.    d6    c5
 2.    b4    c3
 3.    f6    e3
 4.    b2    a7
 5.    b6xc3xc5
''',
    shouldFailToImport: true,
  );

  /// Invalid capture targeting a piece off the capture line.
  static const MoveListTestCase invalidCaptureImport2 = MoveListTestCase(
    id: 'invalid_capture_import_2',
    description: 'Negative: invalid capture target must fail to import',
    moveList: '''
 1.    d6    c5
 2.    b4    c3
 3.    f6    e3
 4.    b2    a7
 5.    b6xe3xc5
''',
    shouldFailToImport: true,
  );

  /// Invalid double removal from a single placement.
  static const MoveListTestCase invalidMoveNotationImport = MoveListTestCase(
    id: 'invalid_move_notation_import',
    description: 'Negative: invalid double removal must fail to import',
    moveList: '''
 1.    a1    b6
 2.    d5    d3
 3.    a7    d2
 4.    e5    d1xa1
 5.    c5xd2xb6
''',
    shouldFailToImport: true,
  );

  /// Full curated batch consumed by the search test.
  static const CaptureScenarioTestConfig
  custodianCaptureAndInterventionCaptureTestConfig = CaptureScenarioTestConfig(
    configName: 'Custodian & Intervention Capture Tests',
    testCases: <MoveListTestCase>[
      placingWhiteIntervention,
      placingWhiteCrossMillCapture,
      placingBlackInterventionMill,
      placingBlackSixMoveMill,
      placingWhiteCustodian,
      placingBlackInterventionMillOtherRemoved,
      placingWhiteInterventionMillOneRemoved,
      invalidCaptureImport,
      invalidCaptureImport2,
      invalidMoveNotationImport,
    ],
  );

  /// Positive (importable) cases only.
  static const List<MoveListTestCase> positives = <MoveListTestCase>[
    placingWhiteIntervention,
    placingWhiteCrossMillCapture,
    placingBlackInterventionMill,
    placingBlackSixMoveMill,
    placingWhiteCustodian,
    placingBlackInterventionMillOtherRemoved,
    placingWhiteInterventionMillOneRemoved,
  ];

  /// Negative (must-fail-to-import) cases only.
  static const List<MoveListTestCase> negatives = <MoveListTestCase>[
    invalidCaptureImport,
    invalidCaptureImport2,
    invalidMoveNotationImport,
  ];
}
