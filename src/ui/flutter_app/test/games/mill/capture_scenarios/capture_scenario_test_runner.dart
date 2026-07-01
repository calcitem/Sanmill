// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// capture_scenario_test_runner.dart
//
// Replays imported move lists through [NativeMillGameSession] and exercises
// the Rust/FRB search path.  Migrated from master `automated_move_test_runner`
// (legacy Position + UCI engine), reduced to the invariants that hold under
// the canonical Rust rules:
//
//   * negative cases must be rejected by the importer;
//   * positive cases must import, replay, and yield a legal search move.

import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';

import 'capture_scenario_test_models.dart';

abstract final class CaptureScenarioTestRunner {
  static Future<TestCaseResult> runTestCase(
    MoveListTestCase testCase, {
    int searchDepth = 6,
    int moveLimitMs = 2000,
  }) async {
    // Phase 1: import.  The importer validates every move against the Rust
    // kernel, so a rejection here is the negative-case success condition.
    bool imported;
    String? importError;
    try {
      ImportService.import(testCase.moveList);
      imported = true;
    } catch (e) {
      imported = false;
      importError = e.toString();
    }

    if (testCase.shouldFailToImport) {
      return TestCaseResult(
        testCase: testCase,
        passed: !imported,
        importFailed: !imported,
        errorMessage: imported
            ? 'Expected import to fail, but it succeeded'
            : null,
      );
    }

    if (!imported) {
      return TestCaseResult(
        testCase: testCase,
        passed: false,
        importFailed: true,
        errorMessage: 'Import rejected on native kernel: $importError',
      );
    }

    final GameRecorder? recorder = GameController().newGameRecorder;
    if (recorder == null) {
      return TestCaseResult(
        testCase: testCase,
        passed: false,
        errorMessage: 'Import succeeded but newGameRecorder is null',
      );
    }

    final NativeMillGameSession session = NativeMillGameSession();
    try {
      final bool replayOk = await session.replayMainline(
        recorder.mainlineMoves,
      );
      if (!replayOk) {
        return TestCaseResult(
          testCase: testCase,
          passed: false,
          errorMessage: 'Failed to replay imported mainline through kernel',
        );
      }

      final String actualSequence = await _executeNativeAiMoves(
        session,
        depth: searchDepth,
        moveLimitMs: moveLimitMs,
      );

      // Invariant: a non-terminal position must yield at least one legal
      // search move.
      final bool passed =
          session.outcome.isTerminal || actualSequence.isNotEmpty;
      return TestCaseResult(
        testCase: testCase,
        passed: passed,
        actualSequence: actualSequence,
        errorMessage: passed ? null : 'Search produced no legal move',
      );
    } catch (e) {
      return TestCaseResult(
        testCase: testCase,
        passed: false,
        errorMessage: e.toString(),
      );
    } finally {
      session.dispose();
    }
  }

  static Future<String> _executeNativeAiMoves(
    NativeMillGameSession session, {
    required int depth,
    required int moveLimitMs,
  }) async {
    final List<String> newMoves = <String>[];

    bool requiresRemoval() => session.legalActions.any(
      (GameAction action) => action.type == MillActionTypes.remove,
    );

    if (requiresRemoval()) {
      int safety = 0;
      while (requiresRemoval() &&
          !session.outcome.isTerminal &&
          safety++ < 16) {
        final GameAction? action = await session.searchAndApplyBestAction(
          depth: depth,
          moveLimitMs: moveLimitMs,
        );
        if (action == null) {
          throw StateError('Engine returned no removal move');
        }
        final String? move = MillActionCodec.moveStringFrom(action);
        if (move == null) {
          throw StateError('Removal action has no move notation');
        }
        newMoves.add(move);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } else if (!session.outcome.isTerminal) {
      final GameAction? action = await session.searchAndApplyBestAction(
        depth: depth,
        moveLimitMs: moveLimitMs,
      );
      if (action == null) {
        throw StateError('Engine returned no best move');
      }
      final String? move = MillActionCodec.moveStringFrom(action);
      if (move == null) {
        throw StateError('Best action has no move notation');
      }
      newMoves.add(move);
    }

    return newMoves.join(' ');
  }
}
