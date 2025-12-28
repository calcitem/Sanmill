// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_thinking_hang_test.dart

// AI Thinking Hang Detection Test
//
// This test attempts to reproduce a rare bug where the AI gets stuck in
// "thinking..." state after a human move and never responds.
//
// The test will:
// 1. Start multiple games in Human vs AI mode
// 2. Make human moves and wait for AI responses
// 3. Monitor for timeouts (AI not responding within reasonable time)
// 4. Stop immediately when the bug is detected
//
// Usage:
//   flutter test integration_test/ai_thinking_hang_test.dart -d linux
//   flutter test integration_test/ai_thinking_hang_test.dart -d android

// ignore_for_file: avoid_print, always_specify_types

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

  const String logTag = '[AIThinkingHangTest]';

  // Test configuration
  const int maxGamesToTest = 100; // Run many games to increase chance of reproducing
  const int aiResponseTimeoutSeconds = 30; // AI should respond within 30 seconds
  const int maxMovesPerGame = 50; // Limit moves per game to speed up testing

  group('AI Thinking Hang Detection Tests', () {
    testWidgets('Detect AI hanging in thinking state', (
      WidgetTester tester,
    ) async {
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

      print('$logTag Starting AI hang detection test...');
      print('$logTag Will run up to $maxGamesToTest games');
      print('$logTag AI timeout threshold: $aiResponseTimeoutSeconds seconds');

      int gamesPlayed = 0;
      int totalMoves = 0;
      int hangsDetected = 0;
      final List<String> hangDetails = <String>[];

      try {
        for (int gameNum = 1; gameNum <= maxGamesToTest; gameNum++) {
          print('$logTag =====================================');
          print('$logTag Starting game $gameNum/$maxGamesToTest');
          print('$logTag =====================================');

          // Thorough reset: Clean all state before each game
          print('$logTag Performing thorough state reset...');
          
          // 1. Shutdown engine if running
          if (GameController().isEngineRunning) {
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

          print('$logTag Configured: Human (White) vs AI (Black)');

          // Start the engine fresh
          await GameController().engine.startup();
          await Future<void>.delayed(const Duration(milliseconds: 200));

          int moveNum = 0;
          bool gameOver = false;

          while (!gameOver && moveNum < maxMovesPerGame) {
            moveNum++;
            totalMoves++;

            final PieceColor currentSide =
                GameController().position.sideToMove;
            final bool isAiTurn =
                GameController().gameInstance.isAiSideToMove;

            print(
              '$logTag Game $gameNum, Move $moveNum: ${currentSide == PieceColor.white ? "White" : "Black"}${isAiTurn ? " (AI)" : " (Human)"}',
            );

            if (isAiTurn) {
              // AI's turn - trigger AI move and monitor for hang
              final bool aiResponded = await _waitForAiMoveWithTimeout(
                aiResponseTimeoutSeconds,
                gameNum,
                moveNum,
              );

              if (!aiResponded) {
                hangsDetected++;
                final String hangDetail =
                    'Game $gameNum, Move $moveNum: AI failed to respond within $aiResponseTimeoutSeconds seconds';
                hangDetails.add(hangDetail);
                print('$logTag ❌ HANG DETECTED: $hangDetail');
                print('$logTag Position FEN: ${GameController().position.fen}');
                print(
                  '$logTag Move history: ${GameController().gameRecorder.moveHistoryText}',
                );
                print('$logTag STOPPING TEST - Bug reproduced!');

                // Stop immediately on first hang detection
                break;
              }

              print('$logTag ✓ AI responded successfully');
            } else {
              // Human's turn - make a random legal move
              final bool humanMoved = await _makeRandomHumanMove();

              if (!humanMoved) {
                print('$logTag No legal moves available for human');
                gameOver = true;
                break;
              }

              print('$logTag ✓ Human move completed');
            }

            // Check if game is over
            if (GameController().position.winner != PieceColor.nobody) {
              gameOver = true;
              print(
                '$logTag Game over: ${GameController().position.winner}',
              );
            }

            // Small delay between moves
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }

          gamesPlayed++;

          // If we detected a hang, stop testing
          if (hangsDetected > 0) {
            break;
          }

          print('$logTag Game $gameNum completed: $moveNum moves');
        }
      } finally {
        // Print summary
        print('$logTag =====================================');
        print('$logTag TEST SUMMARY');
        print('$logTag =====================================');
        print('$logTag Games played: $gamesPlayed');
        print('$logTag Total moves: $totalMoves');
        print('$logTag Hangs detected: $hangsDetected');

        if (hangsDetected > 0) {
          print('$logTag =====================================');
          print('$logTag HANG DETAILS:');
          for (final String detail in hangDetails) {
            print('$logTag - $detail');
          }
          print('$logTag =====================================');
        } else {
          print('$logTag ✓ No hangs detected');
        }
      }

      // Fail the test if we detected any hangs
      expect(
        hangsDetected,
        equals(0),
        reason: 'AI thinking hang detected: ${hangDetails.join(", ")}',
      );
    });
  });
}

/// Wait for AI to make a move with timeout detection
///
/// Returns true if AI responded in time, false if timeout occurred
Future<bool> _waitForAiMoveWithTimeout(
  int timeoutSeconds,
  int gameNum,
  int moveNum,
) async {
  const String logTag = '[AIThinkingHangTest]';

  final Completer<bool> completer = Completer<bool>();
  Timer? timeoutTimer;

  // Record initial state
  final int initialMoveCount =
      GameController().gameRecorder.mainlineMoves.length;
  final String initialFen = GameController().position.fen ?? '';

  print('$logTag Waiting for AI move (timeout: ${timeoutSeconds}s)...');
  print('$logTag Initial move count: $initialMoveCount');
  print('$logTag Initial FEN: $initialFen');

  // Set up timeout
  timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
    if (!completer.isCompleted) {
      print('$logTag ⚠️ TIMEOUT: AI did not respond within $timeoutSeconds seconds');
      print('$logTag Engine running: ${GameController().isEngineRunning}');
      print('$logTag Engine in delay: ${GameController().isEngineInDelay}');
      print(
        '$logTag Current move count: ${GameController().gameRecorder.mainlineMoves.length}',
      );
      print('$logTag Current FEN: ${GameController().position.fen}');
      completer.complete(false);
    }
  });

  // Trigger AI move
  try {
    // Use engine.search directly to avoid UI dependencies
    print('$logTag Calling engine.search()...');
    final EngineRet ret = await GameController().engine.search(moveNow: false);

    if (ret.extMove != null) {
      print('$logTag Engine returned move: ${ret.extMove!.move}');

      // Execute the move
      final bool moveSuccessful =
          GameController().gameInstance.doMove(ret.extMove!);

      if (moveSuccessful) {
        final int finalMoveCount =
            GameController().gameRecorder.mainlineMoves.length;
        print('$logTag Move executed successfully');
        print('$logTag Final move count: $finalMoveCount');

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
      print('$logTag ❌ Engine returned null move');
      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  } catch (e) {
    print('$logTag ❌ Exception during AI move: $e');
    print('$logTag Exception type: ${e.runtimeType}');
    print('$logTag Stack trace: ${StackTrace.current}');
    timeoutTimer.cancel();

    if (!completer.isCompleted) {
      // If the exception is a timeout, that's the bug we're looking for
      if (e is TimeoutException || e.toString().contains('timeout')) {
        completer.complete(false);
      } else {
        // Other exceptions might be legitimate (e.g., no legal moves)
        completer.complete(true);
      }
    }
  }

  return completer.future;
}

/// Make a random legal move for the human player
///
/// Returns true if a move was made, false if no legal moves available
Future<bool> _makeRandomHumanMove() async {
  const String logTag = '[AIThinkingHangTest]';

  try {
    // Use engine's analyzePosition to get all legal moves
    final PositionAnalysisResult analysisResult =
        await GameController().engine.analyzePosition();

    if (!analysisResult.isValid || analysisResult.possibleMoves.isEmpty) {
      print('$logTag No legal moves available from analysis');
      return false;
    }

    // Extract all move strings
    final List<String> legalMoves =
        analysisResult.possibleMoves.map((MoveAnalysisResult m) => m.move).toList();

    print('$logTag Found ${legalMoves.length} legal moves: ${legalMoves.take(5).join(", ")}...');

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
      // If this move failed, try another one from the list
      for (final String move in legalMoves.skip(1).take(5)) {
        final ExtMove alternativeMove = ExtMove(
          move,
          side: GameController().position.sideToMove,
        );
        if (GameController().gameInstance.doMove(alternativeMove)) {
          print('$logTag ✓ Alternative move successful: $move');
          return true;
        }
      }
      return false;
    }
  } catch (e) {
    print('$logTag Error getting legal moves: $e');
    return false;
  }
}

