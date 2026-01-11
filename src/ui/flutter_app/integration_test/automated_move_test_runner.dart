// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// automated_move_test_runner.dart

// ignore_for_file: avoid_classes_with_only_static_members, avoid_print, always_specify_types

import 'dart:async';

import 'package:sanmill/game_page/services/animation/headless_animation_manager.dart';
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
      // Initialize a mock AnimationManager to avoid LateInitializationError in headless tests
      // Inject a mock AnimationManager to avoid LateInitializationError in headless tests
      try {
        final GameController controller = GameController();
        controller.animationManager = HeadlessAnimationManager();
      } catch (_) {
        // ignore
      }

      // Reset game controller to clean state
      // Use singleton GameController instance
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

      // Handle negative tests (expected import failure)
      if (testCase.shouldFailToImport) {
        print('$_logTag This is a negative test - expecting import to fail');
        try {
          ImportService.import(testCase.moveList);
          print('$_logTag Import unexpectedly succeeded');

          // Import succeeded but was expected to fail - test fails
          return TestCaseResult(
            testCase: testCase,
            passed: false,
            actualSequence: '',
            importFailed: false,
            errorMessage: 'Expected import to fail, but it succeeded',
            executionTime: DateTime.now().difference(startTime),
          );
        } catch (e) {
          print('$_logTag Import failed as expected: $e');

          // Import failed as expected - test passes
          return TestCaseResult(
            testCase: testCase,
            passed: true,
            actualSequence: '',
            importFailed: true,
            importErrorMessage: e.toString(),
            executionTime: DateTime.now().difference(startTime),
          );
        }
      }

      // Handle positive tests (expected import success)
      try {
        ImportService.import(testCase.moveList);
        print('$_logTag Import completed successfully');

        // Check if newGameRecorder was set
        if (controller.newGameRecorder != null) {
          print(
            '$_logTag newGameRecorder has ${controller.newGameRecorder!.mainlineMoves.length} moves',
          );
        } else {
          print('$_logTag WARNING: newGameRecorder is null after import!');
        }
      } catch (e) {
        print('$_logTag Import failed: $e');
        throw Exception('Failed to import move list: $e');
      }

      // Execute the imported moves using doEachMove (no UI interaction)
      print('$_logTag Calling doEachMove(takeBackAll)...');
      final HistoryResponse takeBackResp = await HistoryNavigator.doEachMove(
        HistoryNavMode.takeBackAll,
      );
      print('$_logTag takeBackAll result: $takeBackResp');

      // Wait for navigation to complete
      await Future<void>.delayed(const Duration(milliseconds: 100));

      print('$_logTag Calling doEachMove(stepForwardAll)...');
      final HistoryResponse stepForwardResp = await HistoryNavigator.doEachMove(
        HistoryNavMode.stepForwardAll,
      );
      print('$_logTag stepForwardAll result: $stepForwardResp');

      // Wait for all moves to be executed
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Capture initial state after executing all imported moves
      final String initialMoves = controller.gameRecorder.moveHistoryText;
      final int moveCount = controller.gameRecorder.mainlineMoves.length;
      print('$_logTag Initial moves after import: $initialMoves');
      print('$_logTag Move count: $moveCount');
      print('$_logTag Game phase: ${controller.position.phase}');
      print('$_logTag Game winner: ${controller.position.winner}');
      print('$_logTag Side to move: ${controller.position.sideToMove}');
      print(
        '$_logTag Is AI to move: ${controller.gameInstance.isAiSideToMove}',
      );

      // Set up game mode for AI to make the next move
      // Make the side to move be controlled by AI
      controller.gameInstance.gameMode = GameMode.humanVsAi;

      // Set which side is AI based on who is to move
      final PieceColor aiSide = controller.position.sideToMove;
      final PieceColor humanSide = aiSide == PieceColor.white
          ? PieceColor.black
          : PieceColor.white;

      controller.gameInstance.getPlayerByColor(aiSide).isAi = true;
      controller.gameInstance.getPlayerByColor(humanSide).isAi = false;

      print('$_logTag Configured AI for $aiSide side');
      print(
        '$_logTag White is AI: ${controller.gameInstance.getPlayerByColor(PieceColor.white).isAi}',
      );
      print(
        '$_logTag Black is AI: ${controller.gameInstance.getPlayerByColor(PieceColor.black).isAi}',
      );

      // Execute "move now" to trigger AI (real AI execution)
      print('$_logTag Executing move now for ${testCase.id}');

      // Execute real AI "move now" functionality
      final String actualSequence = await _executeRealAiMoves(
        controller,
        maxWaitTimeMs,
      );

      final Duration executionTime = DateTime.now().difference(startTime);

      // Check if we should validate unexpected sequences
      // Skip validation if list is empty or contains only empty strings
      if (_shouldValidateSequences(testCase.unexpectedSequences)) {
        // Check if actual sequence matches any unexpected sequence
        final String? matchedUnexpected = _findMatchingSequence(
          actualSequence,
          testCase.unexpectedSequences,
        );

        // If matched an unexpected sequence, test fails
        if (matchedUnexpected != null) {
          return TestCaseResult(
            testCase: testCase,
            passed: false,
            actualSequence: actualSequence,
            matchedUnexpectedSequence: matchedUnexpected,
            errorMessage: 'Matched unexpected sequence: $matchedUnexpected',
            executionTime: executionTime,
          );
        }
      }

      // Check if we should validate expected sequences
      // Skip validation if list is empty or contains only empty strings
      if (_shouldValidateSequences(testCase.expectedSequences)) {
        // Check if actual sequence matches any expected sequence
        final String? matchedExpected = _findMatchingSequence(
          actualSequence,
          testCase.expectedSequences,
        );

        final bool passed = matchedExpected != null;

        return TestCaseResult(
          testCase: testCase,
          passed: passed,
          actualSequence: actualSequence,
          matchedExpectedSequence: matchedExpected,
          errorMessage: passed ? null : 'Did not match any expected sequence',
          executionTime: executionTime,
        );
      }

      // If both validations are skipped, test passes
      return TestCaseResult(
        testCase: testCase,
        passed: true,
        actualSequence: actualSequence,
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
      // Record initial move count and sequence
      final String initialSequence = controller.gameRecorder.moveHistoryText;
      final int initialMoveCount = controller.gameRecorder.mainlineMoves.length;

      print('$_logTag Initial sequence: "$initialSequence"');
      print('$_logTag Initial move count: $initialMoveCount');
      print(
        '$_logTag Game winner before moveNow: ${controller.position.winner}',
      );
      print(
        '$_logTag Is AI to move: ${controller.gameInstance.isAiSideToMove}',
      );
      print(
        '$_logTag Is Human to move: ${controller.gameInstance.isHumanToMove}',
      );

      // Execute engine moves directly (avoid UI/snackbar paths in moveNow)
      // 1) If we are in a removal obligation, perform all required removals
      if (controller.position.action == Act.remove) {
        print('$_logTag Position requires removal action');
        print(
          '$_logTag pieceToRemoveCount[${controller.position.sideToMove}]: '
          '${controller.position.pieceToRemoveCount[controller.position.sideToMove]}',
        );

        int safety = 0;
        while (controller.position.action == Act.remove &&
            controller.position.winner == PieceColor.nobody &&
            safety++ < 16) {
          print('$_logTag Removal iteration $safety');

          final EngineRet ret = await controller.engine.search(moveNow: true);
          ExtMove? best = ret.extMove;

          print('$_logTag Engine returned move: ${best?.move ?? 'null'}');

          // If engine didn't return a removal, try to get opponent pieces manually
          if (best == null || best.type != MoveType.remove) {
            print(
              '$_logTag Engine did not return removal, finding legal removals manually',
            );

            // Find opponent pieces that can be removed
            final PieceColor opponent = controller.position.sideToMove.opponent;
            final List<String> possibleRemovals = <String>[];

            for (int sq = 8; sq <= 31; sq++) {
              if (controller.position.pieceOnGrid(sq) == opponent) {
                possibleRemovals.add('x${ExtMove.sqToNotation(sq)}');
              }
            }

            if (possibleRemovals.isEmpty) {
              throw Exception(
                'Engine returned no removal and no opponent pieces found',
              );
            }

            print(
              '$_logTag Found ${possibleRemovals.length} possible removals: ${possibleRemovals.join(', ')}',
            );
            best = ExtMove(
              possibleRemovals.first,
              side: controller.position.sideToMove,
            );
          }

          print('$_logTag Executing removal: ${best.move}');
          if (!controller.gameInstance.doMove(best)) {
            print('$_logTag doMove returned false, checking game state...');
            print('$_logTag Game winner: ${controller.position.winner}');
            print('$_logTag Game phase: ${controller.position.phase}');
            // If game is over, that's why doMove failed - break the loop
            if (controller.position.winner != PieceColor.nobody ||
                controller.position.phase == Phase.gameOver) {
              print('$_logTag Game ended, stopping removal loop');
              break;
            }
            throw Exception('Failed to apply removal move: ${best.move}');
          }

          // Give the loop a tiny pause to settle state
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        print('$_logTag Removal loop completed');
        print('$_logTag Final game winner: ${controller.position.winner}');
        print('$_logTag Final phase: ${controller.position.phase}');
      } else {
        // 2) Otherwise, make one engine move
        print('$_logTag Making single engine move');
        final EngineRet ret = await controller.engine.search(moveNow: true);
        final ExtMove? best = ret.extMove;
        if (best == null) {
          throw Exception('Engine returned no best move');
        }
        print('$_logTag Executing move: ${best.move}');
        if (!controller.gameInstance.doMove(best)) {
          throw Exception('Failed to apply engine move: ${best.move}');
        }
      }

      // Wait a moment for any chained state updates
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Get the final move sequence after AI execution
      final String finalSequence = controller.gameRecorder.moveHistoryText;
      final int finalMoveCount = controller.gameRecorder.mainlineMoves.length;

      print('$_logTag Final sequence: "$finalSequence"');
      print('$_logTag Final move count: $finalMoveCount');
      print('$_logTag AI made ${finalMoveCount - initialMoveCount} moves');

      // Extract only the new moves made by AI
      final List<ExtMove> newMoves = controller.gameRecorder.mainlineMoves
          .skip(initialMoveCount)
          .toList();
      final String newMovesNotation = newMoves
          .map((ExtMove m) => m.notation)
          .join(' ');

      print('$_logTag New moves only: "$newMovesNotation"');

      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(newMovesNotation);
      }
    } catch (e) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// Determine if a sequence list should be validated
  /// Returns false if:
  /// - The list is null
  /// - The list is empty
  /// - The list contains only empty strings (after normalization)
  static bool _shouldValidateSequences(List<String>? sequences) {
    if (sequences == null || sequences.isEmpty) {
      return false;
    }

    // Check if all sequences are empty (whitespace-only or empty strings)
    final bool allEmpty = sequences.every(
      (String seq) => _normalizeSequence(seq).isEmpty,
    );

    return !allEmpty;
  }

  /// Find if the actual sequence matches any of the given sequences
  /// Only checks non-empty sequences
  /// Returns null if sequences list is null or no match is found
  static String? _findMatchingSequence(
    String actualSequence,
    List<String>? sequences,
  ) {
    if (sequences == null) {
      return null;
    }

    final String normalizedActual = _normalizeSequence(actualSequence);

    for (final String sequence in sequences) {
      final String normalizedSequence = _normalizeSequence(sequence);
      // Skip empty sequences during matching
      if (normalizedSequence.isEmpty) {
        continue;
      }
      if (normalizedActual == normalizedSequence) {
        return sequence;
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
      // Check if failed due to matching unexpected sequence
      if (result.matchedUnexpectedSequence != null) {
        print('$_logTag   FAILURE REASON: Matched unexpected sequence');
        print(
          '$_logTag   Matched unexpected: ${result.matchedUnexpectedSequence}',
        );
        print('$_logTag   Actual: ${result.actualSequence}');

        final List<String>? unexpectedSeqs =
            result.testCase.unexpectedSequences;
        if (unexpectedSeqs != null && unexpectedSeqs.isNotEmpty) {
          print('$_logTag   All unexpected sequences:');
          for (final String unexpected in unexpectedSeqs) {
            print('$_logTag     - $unexpected');
          }
        }
      } else {
        // Failed due to not matching expected sequence
        print('$_logTag   FAILURE REASON: Did not match any expected sequence');

        final List<String>? expectedSeqs = result.testCase.expectedSequences;
        if (expectedSeqs != null && expectedSeqs.isNotEmpty) {
          print('$_logTag   Expected one of:');
          for (final String expected in expectedSeqs) {
            print('$_logTag     - $expected');
          }
        }
        print('$_logTag   Actual: ${result.actualSequence}');
      }

      if (result.errorMessage != null) {
        print('$_logTag   Error: ${result.errorMessage}');
      }
    } else if (result.matchedExpectedSequence != null) {
      print('$_logTag   Matched expected: ${result.matchedExpectedSequence}');
    }

    print(''); // Empty line for readability
  }

  /// Print summary of the entire test batch
  static void _printBatchSummary(TestBatchResult batchResult) {
    // Print detailed information for failed test cases first
    if (batchResult.failedResults.isNotEmpty) {
      print('');
      print(
        '$_logTag =========================================================',
      );
      print('$_logTag ===================== FAILED TESTS ====================');
      print(
        '$_logTag =========================================================',
      );
      print('');

      batchResult.failedResults.forEach(_printFailedTestDetail);
    }

    // Then print the summary statistics
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
  }

  /// Print detailed information for a failed test case
  static void _printFailedTestDetail(TestCaseResult result) {
    print('$_logTag ---------------------------------------------------------');
    print('$_logTag FAILED TEST: ${result.testCase.id}');
    print('$_logTag ---------------------------------------------------------');
    print('$_logTag Description: ${result.testCase.description}');
    print('');

    // Print move list
    print('$_logTag Move List:');
    final List<String> moveLines = result.testCase.moveList
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (final String line in moveLines) {
      print('$_logTag   $line');
    }
    print('');

    // Handle negative tests (expected import failure)
    if (result.testCase.shouldFailToImport) {
      print('$_logTag Test Type: Negative Test (Expected Import Failure)');
      print('');

      if (result.importFailed == false) {
        // Import succeeded when it should have failed
        print('$_logTag ❌ FAILURE REASON: Import succeeded unexpectedly');
        print('$_logTag Expected: Import should fail');
        print('$_logTag Actual: Import succeeded');
      } else {
        // This shouldn't happen (test passed but in failed list)
        print(
          '$_logTag ⚠️ WARNING: Test marked as failed but import failed as expected',
        );
        if (result.importErrorMessage != null) {
          print('$_logTag Import Error: ${result.importErrorMessage}');
        }
      }

      if (result.errorMessage != null) {
        print('');
        print('$_logTag Error Message:');
        print('$_logTag   ${result.errorMessage}');
      }

      print('');
      print(
        '$_logTag Execution Time: ${result.executionTime.inMilliseconds}ms',
      );
      print(
        '$_logTag ---------------------------------------------------------',
      );
      print('');
      return;
    }

    // Handle positive tests (expected import success)
    // Print expected/unexpected sequences
    if (result.matchedUnexpectedSequence != null) {
      // Test failed because it matched an unexpected sequence
      print('$_logTag Unexpected Sequences (should NOT match):');
      final List<String>? unexpectedSeqs = result.testCase.unexpectedSequences;
      if (unexpectedSeqs != null && unexpectedSeqs.isNotEmpty) {
        for (final String unexpected in unexpectedSeqs) {
          if (unexpected == result.matchedUnexpectedSequence) {
            print('$_logTag   ❌ $unexpected (MATCHED - BAD)');
          } else {
            print('$_logTag   - $unexpected');
          }
        }
      }
    } else {
      // Test failed because it didn't match any expected sequence
      print('$_logTag Expected Sequences (should match one of):');
      final List<String>? expectedSeqs = result.testCase.expectedSequences;
      if (expectedSeqs != null && expectedSeqs.isNotEmpty) {
        for (final String expected in expectedSeqs) {
          print('$_logTag   - $expected');
        }
      }

      // Also print unexpected sequences if they exist
      final List<String>? unexpectedSeqs = result.testCase.unexpectedSequences;
      if (unexpectedSeqs != null && unexpectedSeqs.isNotEmpty) {
        print('');
        print('$_logTag Unexpected Sequences (should NOT match):');
        for (final String unexpected in unexpectedSeqs) {
          print('$_logTag   - $unexpected');
        }
      }
    }

    print('');
    print('$_logTag Actual Result:');
    print('$_logTag   ${result.actualSequence}');

    if (result.errorMessage != null) {
      print('');
      print('$_logTag Error Message:');
      print('$_logTag   ${result.errorMessage}');
    }

    print('');
    print('$_logTag Execution Time: ${result.executionTime.inMilliseconds}ms');
    print('$_logTag ---------------------------------------------------------');
    print('');
  }
}
