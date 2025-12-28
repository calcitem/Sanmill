// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_thinking_hang_quick_test.dart

// Quick AI Thinking Hang Detection Test
//
// This is a shorter version of the full test for quick verification
// and development purposes. It runs only a few games to quickly
// check if the test framework is working correctly.
//
// Usage:
//   flutter test integration_test/ai_thinking_hang_quick_test.dart -d linux

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

  const String logTag = '[AIThinkingHangQuickTest]';

  // Quick test configuration - much faster for development
  const int maxGamesToTest = 5; // Only 5 games for quick testing
  const int aiResponseTimeoutSeconds = 15; // Shorter timeout for quick feedback
  const int maxMovesPerGame = 20; // Fewer moves per game

  group('AI Thinking Hang Detection Quick Tests', () {
    testWidgets('Quick test - Detect AI hanging in thinking state', (
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

      print('$logTag Configuring quick test environment...');

      // Configure settings for very fast testing
      final GeneralSettings currentSettings = DB().generalSettings;
      final GeneralSettings updatedSettings = currentSettings.copyWith(
        skillLevel: 1, // Lowest skill level for fastest response
        moveTime: 1, // 1 second move time
        aiIsLazy: false,
        usePerfectDatabase: false,
      );
      DB().generalSettings = updatedSettings;

      print('$logTag Starting QUICK AI hang detection test...');
      print('$logTag Will run only $maxGamesToTest games (quick mode)');
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
              '$logTag Move $moveNum: ${currentSide == PieceColor.white ? "White" : "Black"}${isAiTurn ? " (AI)" : " (Human)"}',
            );

            if (isAiTurn) {
              // AI's turn
              final bool aiResponded = await _waitForAiMoveWithTimeout(
                aiResponseTimeoutSeconds,
                gameNum,
                moveNum,
              );

              if (!aiResponded) {
                hangsDetected++;
                final String hangDetail =
                    'Game $gameNum, Move $moveNum: AI timeout';
                hangDetails.add(hangDetail);
                print('$logTag ❌ HANG DETECTED: $hangDetail');
                print('$logTag Position FEN: ${GameController().position.fen}');
                print(
                  '$logTag Move history: ${GameController().gameRecorder.moveHistoryText}',
                );
                print('$logTag STOPPING TEST - Bug reproduced!');
                break;
              }

              print('$logTag ✓ AI responded');
            } else {
              // Human's turn
              final bool humanMoved = await _makeRandomHumanMove();

              if (!humanMoved) {
                print('$logTag No legal moves for human');
                gameOver = true;
                break;
              }

              print('$logTag ✓ Human moved');
            }

            // Check game over
            if (GameController().position.winner != PieceColor.nobody) {
              gameOver = true;
              print('$logTag Game over');
            }

            await Future<void>.delayed(const Duration(milliseconds: 50));
          }

          gamesPlayed++;

          if (hangsDetected > 0) {
            break;
          }

          print('$logTag Game $gameNum completed: $moveNum moves');
        }
      } finally {
        print('$logTag =====================================');
        print('$logTag QUICK TEST SUMMARY');
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
          print('$logTag ✓ No hangs detected in quick test');
        }
      }

      expect(
        hangsDetected,
        equals(0),
        reason: 'AI thinking hang detected: ${hangDetails.join(", ")}',
      );
    });
  });
}

/// Wait for AI move with timeout
Future<bool> _waitForAiMoveWithTimeout(
  int timeoutSeconds,
  int gameNum,
  int moveNum,
) async {
  const String logTag = '[AIThinkingHangQuickTest]';

  final Completer<bool> completer = Completer<bool>();
  Timer? timeoutTimer;

  timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
    if (!completer.isCompleted) {
      print('$logTag ⚠️ TIMEOUT after $timeoutSeconds seconds');
      print('$logTag Engine running: ${GameController().isEngineRunning}');
      completer.complete(false);
    }
  });

  try {
    final EngineRet ret = await GameController().engine.search();

    if (ret.extMove != null) {
      final bool moveSuccessful =
          GameController().gameInstance.doMove(ret.extMove!);

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

/// Make a random legal move for human
Future<bool> _makeRandomHumanMove() async {
  const String logTag = '[AIThinkingHangQuickTest]';

  try {
    // Use engine's analyzePosition to get all legal moves
    final PositionAnalysisResult analysisResult =
        await GameController().engine.analyzePosition();

    if (!analysisResult.isValid || analysisResult.possibleMoves.isEmpty) {
      print('$logTag No legal moves available');
      return false;
    }

    // Extract all move strings
    final List<String> legalMoves =
        analysisResult.possibleMoves.map((MoveAnalysisResult m) => m.move).toList();

    legalMoves.shuffle();

    for (final String move in legalMoves) {
      final ExtMove extMove = ExtMove(
        move,
        side: GameController().position.sideToMove,
      );
      if (GameController().gameInstance.doMove(extMove)) {
        return true;
      }
    }

    return false;
  } catch (e) {
    print('$logTag Error getting legal moves: $e');
    return false;
  }
}
