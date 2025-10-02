// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// automated_move_test_runner.dart

// ignore_for_file: avoid_classes_with_only_static_members, avoid_print, always_specify_types

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import 'automated_move_test_models.dart';

/// Main class responsible for executing automated move tests
/// This version is designed for integration tests and uses the REAL AI engine
class AutomatedMoveTestRunner {
  static const String _logTag = '[AutomatedMoveTestRunner]';

  /// Execute a batch of automated move tests
  static Future<TestBatchResult> runTestBatch(
    AutomatedMoveTestConfig config,
  ) async {
    print('$_logTag Starting test batch: ${config.configName}');
    print('$_logTag Batch description: ${config.batchDescription}');

    final DateTime startTime = DateTime.now();
    final List<TestCaseResult> results = <TestCaseResult>[];

    // Print current DB settings (no need to initialize, already done by app)
    _printCurrentSettings();

    for (final MoveListTestCase testCase in config.enabledTestCases) {
      print('$_logTag Executing test case: ${testCase.id}');

      final TestCaseResult result = await _executeTestCase(
        testCase,
        config.maxWaitTimeMs,
      );

      results.add(result);

      // Print immediate result
      _printTestCaseResult(result);

      // Stop on first failure if configured
      if (!result.passed && config.stopOnFirstFailure) {
        print('$_logTag Stopping on first failure as configured');
        break;
      }

      // Small delay between tests to ensure clean state
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final Duration totalTime = DateTime.now().difference(startTime);

    final TestBatchResult batchResult = TestBatchResult(
      config: config,
      testResults: results,
      totalTime: totalTime,
      executedAt: startTime,
    );

    _printBatchSummary(batchResult);
    return batchResult;
  }

  /// Print current database settings
  static void _printCurrentSettings() {
    try {
      final generalSettings = DB().generalSettings;
      final ruleSettings = DB().ruleSettings;

      print('$_logTag Current AI Settings:');
      print('$_logTag AI Skill Level: ${generalSettings.skillLevel}');
      print('$_logTag Move Time: ${generalSettings.moveTime}');
      print('$_logTag Search Algorithm: ${generalSettings.searchAlgorithm}');
      print('$_logTag Perfect Database: ${generalSettings.usePerfectDatabase}');
      print('$_logTag AI Is Lazy: ${generalSettings.aiIsLazy}');
      print('$_logTag Shuffling: ${generalSettings.shufflingEnabled}');
      print('$_logTag Pieces Count: ${ruleSettings.piecesCount}');
      print('$_logTag Has Diagonal Lines: ${ruleSettings.hasDiagonalLines}');
      print('$_logTag May Fly: ${ruleSettings.mayFly}');
    } catch (e) {
      print('$_logTag Warning: Could not read DB settings: $e');
    }
  }

  /// Execute a single test case
  static Future<TestCaseResult> _executeTestCase(
    MoveListTestCase testCase,
    int maxWaitTimeMs,
  ) async {
    final DateTime startTime = DateTime.now();

    try {
      // Reset game controller to clean state
      final GameController controller = GameController();
      controller.reset(force: true);

      // Set game mode to Human vs Human
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Ensure engine is started and configured with real DB settings
      print('$_logTag Starting and configuring AI engine...');
      await controller.engine.startup();
      print('$_logTag AI engine configured with DB settings');

      // Import the move list using real import service
      print('$_logTag Importing move list for ${testCase.id}');
      try {
        ImportService.import(testCase.moveList);
        print('$_logTag Import completed successfully');
      } catch (e) {
        print('$_logTag Import failed: $e');
        throw Exception('Failed to import move list: $e');
      }

      // Capture initial state
      final String initialMoves = controller.gameRecorder.moveHistoryText;
      print('$_logTag Initial moves after import: $initialMoves');

      // Execute "move now" to trigger AI (real AI execution)
      print('$_logTag Executing move now for ${testCase.id}');

      // Execute real AI "move now" functionality
      final String actualSequence = await _executeRealAiMoves(
        controller,
        maxWaitTimeMs,
      );

      final Duration executionTime = DateTime.now().difference(startTime);

      // Check if actual sequence matches any expected sequence
      final String? matchedExpected = _findMatchingExpectedSequence(
        actualSequence,
        testCase.expectedSequences,
      );

      final bool passed = matchedExpected != null;

      return TestCaseResult(
        testCase: testCase,
        passed: passed,
        actualSequence: actualSequence,
        matchedExpectedSequence: matchedExpected,
        executionTime: executionTime,
      );
    } catch (e) {
      final Duration executionTime = DateTime.now().difference(startTime);

      return TestCaseResult(
        testCase: testCase,
        passed: false,
        actualSequence: '',
        errorMessage: e.toString(),
        executionTime: executionTime,
      );
    }
  }

  /// Execute real AI moves with timeout protection
  static Future<String> _executeRealAiMoves(
    GameController controller,
    int maxWaitTimeMs,
  ) async {
    final Completer<String> completer = Completer<String>();
    Timer? timeoutTimer;

    // Set up timeout
    timeoutTimer = Timer(Duration(milliseconds: maxWaitTimeMs), () {
      if (!completer.isCompleted) {
        completer.completeError('Timeout waiting for AI moves');
      }
    });

    try {
      // Get a real BuildContext from the test environment
      final BuildContext context = WidgetsBinding.instance.rootElement!;

      // Record initial move count and sequence
      final String initialSequence = controller.gameRecorder.moveHistoryText;
      final int initialMoveCount = controller.gameRecorder.mainlineMoves.length;

      print('$_logTag Initial sequence: "$initialSequence"');
      print('$_logTag Initial move count: $initialMoveCount');

      // Execute move now which triggers REAL AI to make moves
      print('$_logTag Calling REAL AI moveNow...');
      await controller.moveNow(context);

      // Wait a bit for AI to potentially make multiple moves
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Get the final move sequence after AI execution
      final String finalSequence = controller.gameRecorder.moveHistoryText;
      final int finalMoveCount = controller.gameRecorder.mainlineMoves.length;

      print('$_logTag Final sequence: "$finalSequence"');
      print('$_logTag Final move count: $finalMoveCount');
      print('$_logTag AI made ${finalMoveCount - initialMoveCount} moves');

      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(finalSequence);
      }
    } catch (e) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// Find if the actual sequence matches any of the expected sequences
  static String? _findMatchingExpectedSequence(
    String actualSequence,
    List<String> expectedSequences,
  ) {
    final String normalizedActual = _normalizeSequence(actualSequence);

    for (final String expected in expectedSequences) {
      final String normalizedExpected = _normalizeSequence(expected);
      if (normalizedActual == normalizedExpected) {
        return expected;
      }
    }

    return null;
  }

  /// Normalize a move sequence for comparison by removing extra whitespace
  static String _normalizeSequence(String sequence) {
    return sequence.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Print the result of a single test case
  static void _printTestCaseResult(TestCaseResult result) {
    final String status = result.passed ? 'PASSED' : 'FAILED';
    final String timeStr = '${result.executionTime.inMilliseconds}ms';

    print('$_logTag [$status] ${result.testCase.id} ($timeStr)');

    if (result.testCase.description.isNotEmpty) {
      print('$_logTag   Description: ${result.testCase.description}');
    }

    if (!result.passed) {
      print('$_logTag   Expected one of:');
      for (final String expected in result.testCase.expectedSequences) {
        print('$_logTag     - $expected');
      }
      print('$_logTag   Actual: ${result.actualSequence}');

      if (result.errorMessage != null) {
        print('$_logTag   Error: ${result.errorMessage}');
      }
    } else if (result.matchedExpectedSequence != null) {
      print('$_logTag   Matched: ${result.matchedExpectedSequence}');
    }

    print(''); // Empty line for readability
  }

  /// Print summary of the entire test batch
  static void _printBatchSummary(TestBatchResult batchResult) {
    print('$_logTag =====================================');
    print('$_logTag TEST BATCH SUMMARY');
    print('$_logTag =====================================');
    print('$_logTag Configuration: ${batchResult.config.configName}');
    print('$_logTag Total Tests: ${batchResult.testResults.length}');
    print('$_logTag Passed: ${batchResult.passedCount}');
    print('$_logTag Failed: ${batchResult.failedCount}');
    print(
      '$_logTag Success Rate: ${batchResult.successRate.toStringAsFixed(1)}%',
    );
    print('$_logTag Total Time: ${batchResult.totalTime.inMilliseconds}ms');
    print('$_logTag =====================================');

    if (batchResult.failedResults.isNotEmpty) {
      print('$_logTag FAILED TESTS:');
      for (final TestCaseResult failedResult in batchResult.failedResults) {
        print(
          '$_logTag - ${failedResult.testCase.id}: ${failedResult.testCase.description}',
        );
      }
      print('$_logTag =====================================');
    }
  }
}
