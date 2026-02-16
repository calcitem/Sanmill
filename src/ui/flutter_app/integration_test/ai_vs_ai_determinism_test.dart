// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ai_vs_ai_determinism_test.dart

/// AI vs AI Determinism Integration Test
///
/// Verifies that AI vs AI self-play produces deterministic (reproducible)
/// results under fixed configurations:
///
///   - Rules: Standard Nine Men's Morris (9 pieces, no diagonals)
///   - Thinking Time (moveTime): 0 (depth-only search, no time limit)
///   - Random Move (shuffling): Disabled
///   - Search Algorithm: MTD(f)
///   - Skill Levels tested: 1, 5, 10
///
/// With shuffling disabled and depth-only search, the AI engine should
/// produce identical move sequences for the same skill level on every run.
///
/// ## How to use
///
/// ### First run (calibration)
///
/// Leave [_expectedResults] entries empty (moveSequence: '').
/// Run the test and copy the printed calibration data into [_expectedResults].
///
/// ### Subsequent runs (regression verification)
///
/// With [_expectedResults] filled in, the test compares actual results against
/// the expected baselines. Any deviation indicates the engine has changed.
///
/// ## Running
///
/// ```bash
/// flutter test integration_test/ai_vs_ai_determinism_test.dart -d linux
/// flutter test integration_test/ai_vs_ai_determinism_test.dart -d windows
/// ```

// ignore_for_file: avoid_print, always_specify_types

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/animation/headless_animation_manager.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

import 'backup_service.dart';

// ============================================================
// Configuration constants
// ============================================================

/// Skill levels to test.
const List<int> _testSkillLevels = <int>[1, 5, 10];

/// Safety limit: maximum moves before declaring a stalled game.
const int _maxMovesPerGame = 200;

/// Per-move timeout in milliseconds (2 minutes).
const int _moveTimeoutMs = 120000;

// ============================================================
// Expected results (calibration data)
// ============================================================

/// Holds the expected outcome of a single deterministic AI vs AI game.
///
/// When [moveSequence] is empty the test runs in *calibration mode* for that
/// level: it prints the actual result instead of comparing, so you can copy
/// the output and fill the map below.
class _ExpectedResult {
  const _ExpectedResult({
    required this.winner,
    required this.moveCount,
    required this.moveSequence,
  });

  /// 'white', 'black', 'draw', or 'nobody'.
  final String winner;

  /// Total number of individual moves (not move pairs).
  final int moveCount;

  /// Space-separated flat notation of every move, e.g. "d2 f6 e5 c3 ...".
  final String moveSequence;
}

/// Baseline results captured from a calibration run.
///
/// To recalibrate: clear [moveSequence], run the test, then paste the printed
/// calibration data back here.
///
/// Calibrated on: 2026-02-15
/// Platform: Windows
/// Engine version: Sanmill 7.2.6
const Map<int, _ExpectedResult> _expectedResults = <int, _ExpectedResult>{
  1: _ExpectedResult(
    winner: 'draw',
    moveCount: 30,
    moveSequence:
        'd6 f4 d2 b4 e4 d5 c4 d3 g4 d7 a4 d1 e5 e3 c3 c5 f6 b6 a4-a7 b4-a4 c4-b4 c5-c4 g4-g1 d7-g7 g1-g4 g7-d7 g4-g1 d7-g7 g1-g4 g7-d7',
  ),
  5: _ExpectedResult(
    winner: 'white',
    moveCount: 48,
    moveSequence:
        'd6 f4 d2 b4 g4 d7 a4 d1 d5 d3 e4 f6 f2 b2 b6 g7 a7 c3 d5-c5 c3-c4 e4-e5 c4-c3 d6-d5 xd3 c3-d3 c5-c4 f6-d6 c4-c5 xf4 b4-c4 e5-e4 d6-f6 f2-f4 xd3 b2-b4 e4-e5 xd1 f6-d6 e5-e4 xc4 b4-c4 f4-f6 c4-c3 c5-c4 c3-d3 c4-c3 d3-e3 c3-d3',
  ),
  10: _ExpectedResult(
    winner: 'white',
    moveCount: 118,
    moveSequence:
        'd6 f4 d2 b4 g4 d7 a4 d1 e4 d5 f6 b6 b2 f2 e3 e5 c5 d3 a4-a7 d1-a1 c5-c4 a1-d1 a7-a4 d5-c5 a4-a7 d1-a1 a7-a4 d7-a7 g4-g1 a7-d7 g1-d1 d7-g7 a4-a7 g7-d7 a7-a4 d7-a7 d1-g1 c5-d5 g1-d1 a7-d7 c4-c5 d7-g7 c5-c4 f4-g4 f6-f4 g7-d7 c4-c5 d7-g7 a4-a7 a1-a4 c5-c4 g7-d7 c4-c5 a4-a1 c5-c4 d5-c5 a7-a4 d7-a7 f4-f6 a7-d7 f6-f4 c5-d5 f4-f6 f2-f4 d2-f2 d3-d2 e3-d3 d7-g7 c4-c3 b4-c4 e4-e3 xd2 e5-e4 xb2 d3-d2 c4-c5 d2-d3 xd5 g4-g1 f2-d2 xf4 e4-f4 c3-c4 f4-g4 xc4 d3-c3 c5-d5 f6-f4 g7-d7 c3-d3 xd7 b6-b4 d3-c3 b4-c4 c3-d3 xc4 d5-e5 e3-e4 e5-d5 d3-c3 d5-e5 c3-c4 e5-d5 d2-f2 g4-g7 f4-g4 g7-d7 c4-c5 d7-g7 e4-e5 g7-d7 g4-g7 g1-g4 f2-f4 d7-a7 g7-d7 g4-g1 f4-g4',
  ),
};

// ============================================================
// Actual run result
// ============================================================

/// Captures the outcome of one AI vs AI game during the test.
class _GameRunResult {
  const _GameRunResult({
    required this.winner,
    required this.moveCount,
    required this.moveSequence,
    required this.moveHistoryText,
  });

  final String winner;
  final int moveCount;
  final String moveSequence;

  /// Full PGN-style text for human review / debugging.
  final String moveHistoryText;
}

// ============================================================
// Test entry point
// ============================================================

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String logTag = '[AIvsAIDeterminism]';

  group('AI vs AI Determinism Tests', () {
    setUpAll(() async {
      // Initialize environment once for the entire test group
      print('$logTag Setting up test environment...');
      EnvironmentConfig.test = false;
      EnvironmentConfig.devMode = false;
      EnvironmentConfig.catcher = false;

      try {
        // Initialize Hive
        await Hive.initFlutter();
        print('$logTag Hive initialized');
      } catch (e) {
        print('$logTag Hive already initialized: $e');
      }

      try {
        // Initialize database
        await DB.init();
        print('$logTag Database initialized');
      } catch (e) {
        print('$logTag DB init error (may be acceptable): $e');
      }
    });

    testWidgets('Standard Nine Men\'s Morris self-play is deterministic '
        'at Level 1, 5, 10', (WidgetTester tester) async {
      // --------------------------------------------------
      // 1. Backup database (restored in tearDown)
      // --------------------------------------------------
      final Map<String, dynamic> dbBackup = await backupDatabase();
      addTearDown(() async => restoreDatabase(dbBackup));

      // Inject headless animation manager to avoid frame-scheduling
      // errors in the integration-test harness.
      try {
        GameController().animationManager = HeadlessAnimationManager();
      } catch (_) {
        // Ignore if already set
      }

      // --------------------------------------------------
      // 2. Run a game for each skill level and collect results
      // --------------------------------------------------
      final Map<int, _GameRunResult> actualResults = <int, _GameRunResult>{};

      for (final int level in _testSkillLevels) {
        print('$logTag =========================================');
        print('$logTag Starting game: Level $level');
        print('$logTag =========================================');

        // Configure engine settings for determinism
        _configureSettingsForLevel(level);

        // Reset game state and start engine fresh
        await _resetGameState();

        // Log effective settings
        _printCurrentSettings(level);

        // Run the AI vs AI game loop
        final _GameRunResult result = await _runAiVsAiGame(level);
        actualResults[level] = result;

        // Print game result
        _printGameResult(level, result);
      }

      // --------------------------------------------------
      // 3. Print calibration code (always, for convenience)
      // --------------------------------------------------
      _printCalibrationCode(actualResults);

      // --------------------------------------------------
      // 4. Verify results
      // --------------------------------------------------
      bool hasCalibrationGap = false;

      for (final int level in _testSkillLevels) {
        final _ExpectedResult expected = _expectedResults[level]!;
        final _GameRunResult actual = actualResults[level]!;

        // The game must have produced at least one move.
        expect(
          actual.moveCount,
          greaterThan(0),
          reason: 'Level $level: game should have at least one move',
        );

        // Calibration mode: expected values not yet filled in.
        if (expected.moveSequence.isEmpty) {
          print(
            '$logTag Level $level: CALIBRATION MODE '
            '(fill _expectedResults to enable verification)',
          );
          hasCalibrationGap = true;
          continue;
        }

        // Verification mode: compare against expected baseline.
        expect(
          actual.winner,
          equals(expected.winner),
          reason:
              'Level $level: expected winner "${expected.winner}", '
              'got "${actual.winner}"',
        );

        expect(
          actual.moveCount,
          equals(expected.moveCount),
          reason:
              'Level $level: expected ${expected.moveCount} moves, '
              'got ${actual.moveCount}',
        );

        expect(
          actual.moveSequence,
          equals(expected.moveSequence),
          reason:
              'Level $level: move sequence differs from baseline. '
              'The AI engine may no longer be deterministic or '
              'its behaviour has changed.',
        );

        print('$logTag Level $level: PASSED (deterministic)');
      }

      if (hasCalibrationGap) {
        print('$logTag =========================================');
        print('$logTag CALIBRATION NEEDED');
        print(
          '$logTag Copy the calibration data printed above '
          'into _expectedResults.',
        );
        print('$logTag =========================================');
      }

      // Cleanup
      try {
        await GameController().engine.shutdown();
      } catch (_) {
        // Ignore shutdown errors
      }
    }, timeout: const Timeout(Duration(minutes: 30)));
  });
}

// ============================================================
// Settings configuration
// ============================================================

/// Applies the deterministic settings for a given [skillLevel].
///
/// Sets:
///   - Standard Nine Men's Morris rules
///   - moveTime = 0 (depth-limited only)
///   - shufflingEnabled = false
///   - usePerfectDatabase = false
///   - useOpeningBook = false
///   - aiIsLazy = false
///   - searchAlgorithm = MTD(f)
///   - Various other flags pinned for reproducibility
void _configureSettingsForLevel(int skillLevel) {
  // Rule settings: standard Nine Men's Morris
  DB().ruleSettings = const NineMensMorrisRuleSettings();

  // General settings: deterministic configuration
  DB().generalSettings = DB().generalSettings.copyWith(
    skillLevel: skillLevel,
    moveTime: 0,
    shufflingEnabled: false,
    usePerfectDatabase: false,
    useOpeningBook: false,
    aiIsLazy: false,
    isAutoRestart: false,
    isAutoChangeFirstMove: false,
    resignIfMostLose: false,
    searchAlgorithm: SearchAlgorithm.mtdf,
    drawOnHumanExperience: true,
    considerMobility: true,
    focusOnBlockingPaths: false,
    trapAwareness: false,
    showTutorial: false,
    firstRun: false,
  );
}

// ============================================================
// Game state management
// ============================================================

/// Shuts down the engine, resets the game controller, configures AI vs AI
/// mode, and restarts the engine so it picks up the current DB settings.
Future<void> _resetGameState() async {
  const String logTag = '[AIvsAIDeterminism]';

  // Shutdown engine if it is still running from a previous game.
  if (GameController().isEngineRunning) {
    await GameController().engine.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  // Force-reset the game controller (clears position, recorder, etc.).
  GameController.instance.reset(force: true);
  GameController().isControllerReady = false;

  // Wait for internal state to settle.
  await Future<void>.delayed(const Duration(milliseconds: 500));

  // Set game mode to AI vs AI (both sides controlled by engine).
  GameController().gameInstance.gameMode = GameMode.aiVsAi;

  // Start the engine fresh (reads DB settings via setGeneralOptions /
  // setRuleOptions internally).
  await GameController().engine.startup();
  await Future<void>.delayed(const Duration(milliseconds: 300));

  print('$logTag Game state reset complete');
}

// ============================================================
// AI vs AI game loop
// ============================================================

/// Runs a full AI vs AI game and returns the result.
///
/// On each iteration the engine is asked for a best move, which is then
/// executed.  The loop ends when the game is over, the engine returns no
/// move, or the safety limit [_maxMovesPerGame] is reached.
Future<_GameRunResult> _runAiVsAiGame(int skillLevel) async {
  const String logTag = '[AIvsAIDeterminism]';

  int moveCount = 0;

  // CRITICAL: Activate controller so engine search doesn't bail early.
  GameController().isControllerActive = true;

  while (moveCount < _maxMovesPerGame) {
    // Check whether the game has already ended.
    if (GameController().position.winner != PieceColor.nobody ||
        GameController().position.phase == Phase.gameOver) {
      print(
        '$logTag Game over detected before move ${moveCount + 1}. '
        'Winner: ${_pieceColorToString(GameController().position.winner)}',
      );
      break;
    }

    // Ask the engine for the best move.
    late EngineRet engineRet;
    try {
      engineRet = await GameController().engine.search().timeout(
        const Duration(milliseconds: _moveTimeoutMs),
        onTimeout: () => throw TimeoutException(
          'AI move timed out at move ${moveCount + 1}',
        ),
      );
    } catch (e) {
      print('$logTag Move ${moveCount + 1}: Engine error: $e');
      break;
    }

    final ExtMove? bestMove = engineRet.extMove;
    if (bestMove == null) {
      print('$logTag Move ${moveCount + 1}: Engine returned no best move');
      break;
    }

    // Execute the move on the game model.
    final bool success = GameController().gameInstance.doMove(bestMove);
    if (!success) {
      // doMove can return false if the game ended during execution.
      if (GameController().position.winner != PieceColor.nobody ||
          GameController().position.phase == Phase.gameOver) {
        print(
          '$logTag Game ended during doMove at move ${moveCount + 1}. '
          'Winner: ${_pieceColorToString(GameController().position.winner)}',
        );
      } else {
        print(
          '$logTag Move ${moveCount + 1}: doMove failed for ${bestMove.move}',
        );
      }
      break;
    }

    moveCount++;

    // Progress logging every 5 moves.
    if (moveCount % 5 == 0 || moveCount <= 3) {
      final String side =
          GameController().position.sideToMove == PieceColor.white ? 'W' : 'B';
      print('$logTag Move $moveCount: ${bestMove.move} (next: $side)');
    }

    // Tiny delay to let internal state settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  if (moveCount >= _maxMovesPerGame) {
    print(
      '$logTag WARNING: Game did not finish within $_maxMovesPerGame moves',
    );
  }

  // Deactivate controller now that the game loop is done.
  GameController().isControllerActive = false;

  // Collect results from the game recorder.
  final List<String> moveNotations = GameController().gameRecorder.mainlineMoves
      .map((ExtMove m) => m.notation)
      .toList();

  return _GameRunResult(
    winner: _pieceColorToString(GameController().position.winner),
    moveCount: moveNotations.length,
    moveSequence: moveNotations.join(' '),
    moveHistoryText: GameController().gameRecorder.moveHistoryText,
  );
}

// ============================================================
// Utility / printing helpers
// ============================================================

String _pieceColorToString(PieceColor color) {
  switch (color) {
    case PieceColor.white:
      return 'white';
    case PieceColor.black:
      return 'black';
    case PieceColor.draw:
      return 'draw';
    case PieceColor.nobody:
      return 'nobody';
    case PieceColor.none:
    case PieceColor.marked:
      return 'unknown';
  }
}

void _printCurrentSettings(int level) {
  const String logTag = '[AIvsAIDeterminism]';
  final GeneralSettings gs = DB().generalSettings;
  final RuleSettings rs = DB().ruleSettings;

  print('$logTag --- Settings for Level $level ---');
  print('$logTag Skill Level: ${gs.skillLevel}');
  print('$logTag Move Time: ${gs.moveTime}');
  print('$logTag Shuffling Enabled: ${gs.shufflingEnabled}');
  print('$logTag Perfect Database: ${gs.usePerfectDatabase}');
  print('$logTag Opening Book: ${gs.useOpeningBook}');
  print('$logTag AI Is Lazy: ${gs.aiIsLazy}');
  print('$logTag Search Algorithm: ${gs.searchAlgorithm}');
  print('$logTag Pieces Count: ${rs.piecesCount}');
  print('$logTag Has Diagonal Lines: ${rs.hasDiagonalLines}');
  print('$logTag May Fly: ${rs.mayFly}');
  print('$logTag --- End Settings ---');
}

void _printGameResult(int level, _GameRunResult result) {
  const String logTag = '[AIvsAIDeterminism]';

  print('$logTag -----------------------------------------');
  print('$logTag RESULT: Level $level');
  print('$logTag -----------------------------------------');
  print('$logTag Winner: ${result.winner}');
  print('$logTag Move count: ${result.moveCount}');
  print('$logTag Move sequence:');
  print('$logTag   ${result.moveSequence}');
  print('$logTag Move history (PGN):');
  // Print PGN line by line for readability.
  for (final String line in result.moveHistoryText.split('\n')) {
    if (line.trim().isNotEmpty) {
      print('$logTag   $line');
    }
  }
  print('$logTag -----------------------------------------');
}

/// Prints copy-pasteable Dart code for [_expectedResults].
void _printCalibrationCode(Map<int, _GameRunResult> results) {
  const String logTag = '[AIvsAIDeterminism]';

  print('$logTag =========================================');
  print('$logTag CALIBRATION DATA');
  print('$logTag Copy the map below into _expectedResults:');
  print('$logTag =========================================');
  print(
    'const Map<int, _ExpectedResult> _expectedResults = '
    '<int, _ExpectedResult>{',
  );

  for (final int level in _testSkillLevels) {
    final _GameRunResult r = results[level]!;

    // Escape single quotes in the move sequence (unlikely but safe).
    final String escaped = r.moveSequence.replaceAll("'", "\\'");

    print("  $level: _ExpectedResult(");
    print("    winner: '${r.winner}',");
    print("    moveCount: ${r.moveCount},");
    print("    moveSequence: '$escaped',");
    print("  ),");
  }

  print('};');
  print('$logTag =========================================');
}
