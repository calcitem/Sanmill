// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test_models.dart

// ignore_for_file: sort_constructors_first, always_specify_types

/// Represents a single test case with move list and expected outcomes
class MoveListTestCase {
  /// Unique identifier for this test case
  final String id;

  /// Description of what this test is validating
  final String description;

  /// The move list to import and execute
  final String moveList;

  /// List of possible expected move sequences after AI execution
  /// Test passes if the actual result matches any of these expected sequences
  /// If null, empty, or contains only empty strings, this check is skipped
  final List<String>? expectedSequences;

  /// List of unexpected move sequences that should cause test failure
  /// Test fails if the actual result matches any of these unexpected sequences
  /// If null, empty, or contains only empty strings, this check is skipped
  /// Defaults to empty list
  final List<String>? unexpectedSequences;

  /// Whether the move list import is expected to fail (negative test)
  /// If true, the test passes when import fails and fails when import succeeds
  /// This is useful for testing invalid move sequences
  final bool shouldFailToImport;

  /// Optional description of the expected import failure
  /// Used for better error messages in negative tests
  final String? expectedImportError;

  /// Whether this test case is currently enabled
  final bool enabled;

  const MoveListTestCase({
    required this.id,
    required this.description,
    required this.moveList,
    this.expectedSequences,
    this.unexpectedSequences,
    this.shouldFailToImport = false,
    this.expectedImportError,
    this.enabled = true,
  });

  @override
  String toString() {
    return 'MoveListTestCase(id: $id, description: $description, enabled: $enabled)';
  }
}

/// Configuration for a batch of automated move tests
class AutomatedMoveTestConfig {
  /// Name of this test configuration
  final String configName;

  /// Overall description of what this test batch validates
  final String batchDescription;

  /// List of test cases to execute
  final List<MoveListTestCase> testCases;

  /// Maximum time to wait for AI moves (in milliseconds)
  final int maxWaitTimeMs;

  /// Whether to stop on first failure or continue with remaining tests
  final bool stopOnFirstFailure;

  const AutomatedMoveTestConfig({
    required this.configName,
    required this.batchDescription,
    required this.testCases,
    this.maxWaitTimeMs = 10000,
    this.stopOnFirstFailure = false,
  });

  /// Get only the enabled test cases
  List<MoveListTestCase> get enabledTestCases =>
      testCases.where((testCase) => testCase.enabled).toList();

  @override
  String toString() {
    return 'AutomatedMoveTestConfig(name: $configName, '
        'enabled cases: ${enabledTestCases.length}/${testCases.length})';
  }
}

/// Result of executing a single test case
class TestCaseResult {
  /// The test case that was executed
  final MoveListTestCase testCase;

  /// Whether the test passed
  final bool passed;

  /// The actual move sequence that was generated
  final String actualSequence;

  /// The expected sequence that was matched (if any)
  final String? matchedExpectedSequence;

  /// The unexpected sequence that was matched (if any)
  /// If not null, this indicates the test failed due to matching an unexpected sequence
  final String? matchedUnexpectedSequence;

  /// Error message if the test failed
  final String? errorMessage;

  /// Whether the import failed (used for negative tests)
  final bool? importFailed;

  /// The import error message (if import failed)
  final String? importErrorMessage;

  /// Duration of the test execution
  final Duration executionTime;

  const TestCaseResult({
    required this.testCase,
    required this.passed,
    required this.actualSequence,
    this.matchedExpectedSequence,
    this.matchedUnexpectedSequence,
    this.errorMessage,
    this.importFailed,
    this.importErrorMessage,
    required this.executionTime,
  });

  @override
  String toString() {
    return 'TestCaseResult(id: ${testCase.id}, passed: $passed, '
        'time: ${executionTime.inMilliseconds}ms)';
  }
}

/// Overall result of executing a test batch
class TestBatchResult {
  /// The configuration that was executed
  final AutomatedMoveTestConfig config;

  /// Results of individual test cases
  final List<TestCaseResult> testResults;

  /// Total execution time
  final Duration totalTime;

  /// Timestamp when the test was executed
  final DateTime executedAt;

  const TestBatchResult({
    required this.config,
    required this.testResults,
    required this.totalTime,
    required this.executedAt,
  });

  /// Number of passed tests
  int get passedCount => testResults.where((r) => r.passed).length;

  /// Number of failed tests
  int get failedCount => testResults.where((r) => !r.passed).length;

  /// Overall success rate as a percentage
  double get successRate =>
      testResults.isEmpty ? 0.0 : (passedCount / testResults.length) * 100;

  /// Get only the failed test results
  List<TestCaseResult> get failedResults =>
      testResults.where((r) => !r.passed).toList();

  @override
  String toString() {
    return 'TestBatchResult(config: ${config.configName}, '
        'passed: $passedCount, failed: $failedCount, '
        'success rate: ${successRate.toStringAsFixed(1)}%)';
  }
}
