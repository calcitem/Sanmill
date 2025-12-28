// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_thinking_hang_visual_test.dart

// Visual AI Thinking Hang Detection Test
//
// This test runs with the actual UI visible, allowing you to observe
// the game board and detect if AI gets stuck in "thinking..." state.
//
// Unlike the headless tests, this version:
// - Shows the actual game board
// - Displays pieces being placed and moved
// - Shows AI thinking status
// - Allows visual observation of the bug
//
// Usage:
//   flutter test integration_test/ai_thinking_hang_visual_test.dart -d windows
//   flutter test integration_test/ai_thinking_hang_visual_test.dart -d linux

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

  const String logTag = '[AIThinkingHangVisualTest]';

  // Visual test configuration - slower to allow observation
  const int maxGamesToTest = 10; // Fewer games since we're watching
  const int aiResponseTimeoutSeconds = 30; // AI timeout threshold
  const int maxMovesPerGame = 40; // More moves to test various scenarios
  const int delayBetweenMoves = 1000; // 1 second delay to watch moves

  group('AI Thinking Hang Visual Detection Tests', () {
    testWidgets('Visual test - Observe AI thinking behavior with UI', (
      WidgetTester tester,
    ) async {
      // Launch the full app with UI
      print('$logTag Launching Sanmill app with UI...');
      app.main();
      
      // Pump and settle to let UI render
      await tester.pumpAndSettle(const Duration(seconds: 5));

      print('$logTag App UI is now visible!');
      print('$logTag You should see the game board on screen.');

      // Wait for app initialization
      await Future<void>.delayed(const Duration(seconds: 3));

      // Backup database
      final Map<String, dynamic> dbBackup = await backupDatabase();
      addTearDown(() async => restoreDatabase(dbBackup));

      print('$logTag Configuring visual test environment...');

      // Configure settings for slower, observable gameplay
      final GeneralSettings currentSettings = DB().generalSettings;
      final GeneralSettings updatedSettings = currentSettings.copyWith(
        skillLevel: 1, // Lower skill level for faster response
        moveTime: 1, // 1 second move time
        aiIsLazy: false,
        usePerfectDatabase: false,
      );
      DB().generalSettings = updatedSettings;

      print('$logTag ========================================');
      print('$logTag VISUAL AI HANG DETECTION TEST');
      print('$logTag ========================================');
      print('$logTag Games to test: $maxGamesToTest');
      print('$logTag AI timeout: $aiResponseTimeoutSeconds seconds');
      print('$logTag Delay between moves: ${delayBetweenMoves}ms');
      print('$logTag ========================================');
      print('$logTag WATCH THE GAME BOARD ON SCREEN!');
      print('$logTag ========================================');

      int gamesPlayed = 0;
      int totalMoves = 0;
      int hangsDetected = 0;
      final List<String> hangDetails = <String>[];

      try {
        for (int gameNum = 1; gameNum <= maxGamesToTest; gameNum++) {
          print('');
          print('$logTag =====================================');
          print('$logTag 🎮 Starting game $gameNum/$maxGamesToTest');
          print('$logTag =====================================');

          // Reset game controller
          GameController.instance.reset(force: true);
          await tester.pumpAndSettle();

          // Small delay to observe the reset
          await Future<void>.delayed(const Duration(milliseconds: 500));

          // Configure Human vs AI mode
          GameController().gameInstance.gameMode = GameMode.humanVsAi;
          GameController()
              .gameInstance
              .getPlayerByColor(PieceColor.white)
              .isAi = false;
          GameController()
              .gameInstance
              .getPlayerByColor(PieceColor.black)
              .isAi = true;

          print('$logTag ♟️  Human (White) vs 🤖 AI (Black)');

          // Start the engine
          await GameController().engine.startup();

          int moveNum = 0;
          bool gameOver = false;

          while (!gameOver && moveNum < maxMovesPerGame) {
            moveNum++;
            totalMoves++;

            final PieceColor currentSide =
                GameController().position.sideToMove;
            final bool isAiTurn =
                GameController().gameInstance.isAiSideToMove;

            print('');
            print(
              '$logTag 📍 Move $moveNum: ${currentSide == PieceColor.white ? "⚪ White" : "⚫ Black"}${isAiTurn ? " (🤖 AI)" : " (♟️  Human)"}',
            );

            if (isAiTurn) {
              // AI's turn - trigger AI move and monitor for hang
              print('$logTag 🤔 AI is thinking...');
              
              final bool aiResponded = await _waitForAiMoveWithTimeout(
                tester,
                aiResponseTimeoutSeconds,
                gameNum,
                moveNum,
              );

              if (!aiResponded) {
                hangsDetected++;
                final String hangDetail =
                    'Game $gameNum, Move $moveNum: AI timeout';
                hangDetails.add(hangDetail);
                
                print('');
                print('$logTag ❌❌❌ HANG DETECTED ❌❌❌');
                print('$logTag $hangDetail');
                print('$logTag Position FEN: ${GameController().position.fen}');
                print(
                  '$logTag Move history: ${GameController().gameRecorder.moveHistoryText}',
                );
                print('$logTag ❌❌❌ STOPPING TEST ❌❌❌');
                print('');
                
                // Let user observe the frozen state
                await Future<void>.delayed(const Duration(seconds: 5));
                break;
              }

              print('$logTag ✅ AI responded successfully');
              
              // Update UI
              await tester.pumpAndSettle();
            } else {
              // Human's turn - make a random legal move
              print('$logTag 🎯 Making human move...');
              
              final bool humanMoved = await _makeRandomHumanMove();

              if (!humanMoved) {
                print('$logTag ⚠️  No legal moves available for human');
                gameOver = true;
                break;
              }

              print('$logTag ✅ Human move completed');
              
              // Update UI
              await tester.pumpAndSettle();
            }

            // Check if game is over
            if (GameController().position.winner != PieceColor.nobody) {
              gameOver = true;
              final String winner = GameController().position.winner == PieceColor.white
                  ? '⚪ White'
                  : GameController().position.winner == PieceColor.black
                      ? '⚫ Black'
                      : '🤝 Draw';
              print('$logTag 🏁 Game over: $winner wins!');
            }

            // Delay between moves to allow observation
            await Future<void>.delayed(
              Duration(milliseconds: delayBetweenMoves),
            );
            await tester.pump();
          }

          gamesPlayed++;

          // If we detected a hang, stop testing
          if (hangsDetected > 0) {
            break;
          }

          print('$logTag ✓ Game $gameNum completed: $moveNum moves');
          
          // Delay between games
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      } finally {
        // Print summary
        print('');
        print('$logTag ========================================');
        print('$logTag VISUAL TEST SUMMARY');
        print('$logTag ========================================');
        print('$logTag Games played: $gamesPlayed');
        print('$logTag Total moves: $totalMoves');
        print('$logTag Hangs detected: $hangsDetected');

        if (hangsDetected > 0) {
          print('$logTag ========================================');
          print('$logTag ❌ HANG DETAILS:');
          for (final String detail in hangDetails) {
            print('$logTag - $detail');
          }
          print('$logTag ========================================');
        } else {
          print('$logTag ✅ No hangs detected');
        }
        print('$logTag ========================================');
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

/// Wait for AI to make a move with timeout detection and UI updates
Future<bool> _waitForAiMoveWithTimeout(
  WidgetTester tester,
  int timeoutSeconds,
  int gameNum,
  int moveNum,
) async {
  const String logTag = '[AIThinkingHangVisualTest]';

  final Completer<bool> completer = Completer<bool>();
  Timer? timeoutTimer;

  // Set up timeout
  timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
    if (!completer.isCompleted) {
      print('$logTag ⚠️  TIMEOUT: AI did not respond within $timeoutSeconds seconds');
      print('$logTag Engine running: ${GameController().isEngineRunning}');
      print('$logTag Engine in delay: ${GameController().isEngineInDelay}');
      completer.complete(false);
    }
  });

  try {
    final EngineRet ret = await GameController().engine.search(moveNow: false);

    if (ret.extMove != null) {
      final bool moveSuccessful =
          GameController().gameInstance.doMove(ret.extMove!);

      // Update UI
      await tester.pump();

      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(moveSuccessful);
      }
    } else {
      timeoutTimer.cancel();

      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  } catch (e) {
    print('$logTag ⚠️  Exception during AI move: $e');
    timeoutTimer.cancel();

    if (!completer.isCompleted) {
      if (e is TimeoutException || e.toString().contains('timeout')) {
        completer.complete(false);
      } else {
        completer.complete(true);
      }
    }
  }

  return completer.future;
}

/// Make a random legal move for human using engine analysis
Future<bool> _makeRandomHumanMove() async {
  const String logTag = '[AIThinkingHangVisualTest]';

  try {
    // Use engine's analyzePosition to get all legal moves
    final PositionAnalysisResult analysisResult =
        await GameController().engine.analyzePosition();

    if (!analysisResult.isValid || analysisResult.possibleMoves.isEmpty) {
      return false;
    }

    // Extract all move strings
    final List<String> legalMoves = analysisResult.possibleMoves
        .map((MoveAnalysisResult m) => m.move)
        .toList();

    // Shuffle and pick a random move
    legalMoves.shuffle();

    for (final String move in legalMoves.take(5)) {
      final ExtMove extMove = ExtMove(
        move,
        side: GameController().position.sideToMove,
      );
      if (GameController().gameInstance.doMove(extMove)) {
        print('$logTag   Played: $move');
        return true;
      }
    }

    return false;
  } catch (e) {
    print('$logTag ⚠️  Error getting legal moves: $e');
    return false;
  }
}

