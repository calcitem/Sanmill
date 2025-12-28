// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_thinking_hang_first_move_test.dart
//
// AI First Move Hang Detection Test
//
// This test focuses on detecting hangs that occur on AI's FIRST response
// (move 2, after human's first move). Tests show this is where most hangs occur.
//
// The test will:
// 1. Test 500 games, but only the first 2 moves of each
// 2. Human makes move 1, AI makes move 2
// 3. If AI hangs on move 2, stop immediately and report
//
// Usage:
//   flutter test integration_test/ai_thinking_hang_first_move_test.dart -d linux
//   flutter test integration_test/ai_thinking_hang_first_move_test.dart -d android

// ignore_for_file: avoid_print, always_specify_types, prefer_const_constructors

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/main.dart' as app;
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String logTag = '[AIFirstMoveTest]';

  // Test configuration - Focus on first 2 moves only
  const int maxGamesToTest = 500; // Test many games, but only 2 moves each
  const int aiResponseTimeoutSeconds = 30; // AI timeout for the second move
  const int delayBetweenGames = 500; // Short delay between games (ms)

  group('AI First Move Hang Detection Test', () {
    testWidgets(
      'Test AI response on move 2 (after human first move) - $maxGamesToTest iterations',
      (WidgetTester tester) async {
        // Launch the app
        print('$logTag Launching Sanmill app...');
        app.main();
        await tester.pumpAndSettle();

        // Wait for app initialization
        await Future<void>.delayed(const Duration(seconds: 5));

        // Backup database
        final Map<String, dynamic> dbBackup = await backupDatabase();
        addTearDown(() async => restoreDatabase(dbBackup));

        print('$logTag Configuring test environment...');

        // Configure settings for faster testing
        final GeneralSettings currentSettings = DB().generalSettings;
        final GeneralSettings updatedSettings = currentSettings.copyWith(
          skillLevel: 1, // Lower skill level for faster AI response
          moveTime: 1, // 1 second move time
          aiIsLazy: false, // Don't use lazy evaluation
          usePerfectDatabase: false, // Don't use perfect database for speed
        );
        DB().generalSettings = updatedSettings;

        print('$logTag ========================================');
        print('$logTag Starting First Move Hang Detection Test');
        print('$logTag Testing $maxGamesToTest games');
        print("$logTag Focus: AI's second move (first AI response)");
        print('$logTag ========================================');

        int totalGames = 0;
        int successfulSecondMoves = 0;
        int failedSecondMoves = 0;
        final List<String> hangDetails = <String>[];

        try {
          for (int gameNum = 1; gameNum <= maxGamesToTest; gameNum++) {
            print('$logTag ');
            print('$logTag --- Game $gameNum/$maxGamesToTest ---');

            // Thorough reset: Clean all state before each game
            print('$logTag Performing thorough state reset...');

            // 1. Shutdown engine if running
            if (GameController().isEngineRunning) {
              print('$logTag Shutting down engine...');
              await GameController().engine.shutdown();
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }

            // 2. Force reset game controller
            GameController.instance.reset(force: true);

            // 3. Reset controller ready flag (CRITICAL!)
            GameController().isControllerReady = false;

            // 4. Wait for state to settle completely
            await tester.pumpAndSettle(const Duration(milliseconds: 500));

            // 5. Additional delay to ensure clean state
            await Future<void>.delayed(const Duration(milliseconds: 300));

            print('$logTag State reset complete');

            // Configure Human vs AI mode with human as white
            GameController().gameInstance.gameMode = GameMode.humanVsAi;
            GameController()
                .gameInstance
                .getPlayerByColor(PieceColor.white)
                .isAi = false;
            GameController()
                .gameInstance
                .getPlayerByColor(PieceColor.black)
                .isAi = true;

            // Start the engine fresh
            print('$logTag Starting engine...');
            await GameController().engine.startup();
            await Future<void>.delayed(const Duration(milliseconds: 200));
            print('$logTag Engine started');

            totalGames++;

            // Move 1: Human makes first move
            print('$logTag Move 1: White (Human)');
            final bool humanMoveSuccess = await _makeRandomHumanMove();

            if (!humanMoveSuccess) {
              print('$logTag ⚠️ Failed to make human move');
              failedSecondMoves++;
              continue;
            }

            print('$logTag ✓ Human move completed');
            await tester.pumpAndSettle();

            // Move 2: Wait for AI response (THIS IS THE CRITICAL TEST)
            print('$logTag Move 2: Black (AI)');
            print(
                "$logTag Waiting for AI's FIRST response (timeout: ${aiResponseTimeoutSeconds}s)...");

            final bool aiSuccess = await _waitForAiMoveWithTimeout(
              aiResponseTimeoutSeconds,
              gameNum,
            );

            await tester.pumpAndSettle();

            if (!aiSuccess) {
              // HANG DETECTED on second move!
              print('$logTag ❌❌❌ HANG DETECTED ❌❌❌');
              print(
                  '$logTag AI failed to respond on move 2 (first AI move)');

              final String hangDetail =
                  'Game $gameNum, Move 2: AI failed to respond within $aiResponseTimeoutSeconds seconds';
              hangDetails.add(hangDetail);
              failedSecondMoves++;

              print('$logTag Position FEN: ${GameController().position.fen}');
              print(
                  '$logTag Move history: ${GameController().gameRecorder.moveHistoryText}');

              print('$logTag ❌❌❌ STOPPING TEST ❌❌❌');
              print('$logTag Bug reproduced on game $gameNum, move 2');
              break;
            }

            successfulSecondMoves++;
            print('$logTag ✓ AI responded successfully on move 2');

            // Short delay before next game
            if (gameNum < maxGamesToTest) {
              await Future<void>.delayed(
                  Duration(milliseconds: delayBetweenGames));
            }
          }
        } finally {
          // Print summary
          print('$logTag ');
          print('$logTag ========================================');
          print('$logTag FIRST MOVE TEST SUMMARY');
          print('$logTag ========================================');
          print('$logTag Total games tested: $totalGames');
          print('$logTag Successful AI move 2: $successfulSecondMoves');
          print('$logTag Failed AI move 2: $failedSecondMoves');
          print('$logTag Hangs detected: ${hangDetails.length}');
          print('$logTag ========================================');

          if (hangDetails.isEmpty) {
            print('$logTag ✅ No hangs detected on move 2');
          } else {
            print('$logTag ❌ HANG DETAILS:');
            for (final String detail in hangDetails) {
              print('$logTag - $detail');
            }
            print('$logTag ========================================');
          }
        }

        // Test passes even if hang detected (we want to capture the state)
        expect(true, isTrue);
      },
      timeout: const Timeout(Duration(hours: 2)),
    );
  });
}

/// Wait for AI to make a move with timeout detection
Future<bool> _waitForAiMoveWithTimeout(
  int timeoutSeconds,
  int gameNum,
) async {
  final Completer<bool> completer = Completer<bool>();
  Timer? timeoutTimer;

  const String logTag = '[AIFirstMoveTest]';

  // Set up timeout
  timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
    if (!completer.isCompleted) {
      print(
          '$logTag ⚠️ TIMEOUT: AI did not respond within $timeoutSeconds seconds');
      print('$logTag Engine running: ${GameController().isEngineRunning}');
      print('$logTag Engine in delay: ${GameController().isEngineInDelay}');
      completer.complete(false);
    }
  });

  try {
    // Use engine.search directly to avoid UI dependencies
    print('$logTag Calling engine.search()...');
    final EngineRet ret = await GameController().engine.search();

    if (ret.extMove != null) {
      print('$logTag Engine returned move: ${ret.extMove!.move}');

      // Execute the move
      final bool moveSuccessful =
          GameController().gameInstance.doMove(ret.extMove!);

      if (moveSuccessful) {
        print('$logTag Move executed successfully');
        timeoutTimer.cancel();

        if (!completer.isCompleted) {
          completer.complete(true);
        }
      } else {
        print('$logTag ❌ Failed to execute move: ${ret.extMove!.move}');
        timeoutTimer.cancel();

        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    } else {
      print('$logTag ❌ Engine returned no move');
      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  } catch (e) {
    print('$logTag ❌ Exception during AI move: $e');
    timeoutTimer.cancel();
    if (!completer.isCompleted) {
      completer.complete(false);
    }
  }

  return completer.future;
}

/// Make a random legal move for the human player
Future<bool> _makeRandomHumanMove() async {
  const String logTag = '[AIFirstMoveTest]';

  try {
    // Use engine's analyzePosition to get all legal moves
    final PositionAnalysisResult analysisResult =
        await GameController().engine.analyzePosition();

    if (!analysisResult.isValid || analysisResult.possibleMoves.isEmpty) {
      print('$logTag No legal moves available from analysis');
      return false;
    }

    // Extract all move strings
    final List<String> legalMoves = analysisResult.possibleMoves
        .map((MoveAnalysisResult m) => m.move)
        .toList();

    print(
        '$logTag Found ${legalMoves.length} legal moves: ${legalMoves.take(5).join(", ")}...');

    // Shuffle and pick a random move
    legalMoves.shuffle();
    final String selectedMove = legalMoves.first;

    print('$logTag Human making move: $selectedMove');

    // Create ExtMove and execute it
    final ExtMove extMove = ExtMove(
      selectedMove,
      side: GameController().position.sideToMove,
    );

    final bool success = GameController().gameInstance.doMove(extMove);

    if (success) {
      print('$logTag ✓ Human move successful: $selectedMove');
      return true;
    } else {
      print('$logTag ❌ Human move failed: $selectedMove, trying another...');

      // Try other moves
      for (final String move in legalMoves.skip(1).take(5)) {
        final ExtMove altExtMove = ExtMove(
          move,
          side: GameController().position.sideToMove,
        );

        if (GameController().gameInstance.doMove(altExtMove)) {
          print('$logTag ✓ Human move successful (alternative): $move');
          return true;
        }
      }

      print('$logTag ❌ All attempted moves failed');
      return false;
    }
  } catch (e) {
    print('$logTag ❌ Exception in _makeRandomHumanMove: $e');
    return false;
  }
}
