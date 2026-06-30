// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// capture_scenario_test_models.dart

/// A single capture-scenario test case: a move list that is either expected
/// to import cleanly (positive) or to be rejected by the kernel importer
/// (negative, [shouldFailToImport] = true).
class MoveListTestCase {
  const MoveListTestCase({
    required this.id,
    required this.description,
    required this.moveList,
    this.shouldFailToImport = false,
  });

  final String id;
  final String description;
  final String moveList;
  final bool shouldFailToImport;

  @override
  String toString() => 'MoveListTestCase(id: $id)';
}

/// A named batch of capture-scenario cases.
class CaptureScenarioTestConfig {
  const CaptureScenarioTestConfig({
    required this.configName,
    required this.testCases,
  });

  final String configName;
  final List<MoveListTestCase> testCases;
}

/// Outcome of replaying one case through the native pipeline.
class TestCaseResult {
  const TestCaseResult({
    required this.testCase,
    required this.passed,
    this.importFailed = false,
    this.actualSequence = '',
    this.errorMessage,
  });

  final MoveListTestCase testCase;
  final bool passed;

  /// True when the kernel importer rejected the move list.  For negative
  /// cases this is the success condition; for positive cases it is a failure.
  final bool importFailed;

  /// Space-joined search move(s) produced after replaying the imported moves.
  final String actualSequence;

  final String? errorMessage;
}
