// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ai_hang_smoke_test.dart
//
// Lightweight native-session smoke test for AI response hangs.
// Migrated from master `ai_thinking_hang_test.dart` (legacy Position +
// method-channel engine).  Runs fewer games with shorter timeouts.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import 'backup_service.dart';
import 'helpers.dart';
import 'init_test_environment.dart';
import 'monkey/board_tap_helper.dart';
import 'monkey/game_state_reader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String logTag = '[AiHangSmoke]';
  const int maxGames = 5;
  const int maxMovesPerGame = 24;
  const int aiTimeoutSeconds = 20;

  Map<String, dynamic>? dbBackup;

  setUpAll(() async {
    await initTestEnvironment();
    dbBackup = await backupDatabase();
  });

  tearDownAll(() async {
    await restoreDatabase(dbBackup);
  });

  group('AI hang smoke', () {
    testWidgets(
      'Human vs AI completes moves without hanging',
      (WidgetTester tester) async {
        await initApp(tester);

        DB().generalSettings = DB().generalSettings.copyWith(
          skillLevel: 1,
          moveTime: 1,
          aiIsLazy: false,
          usePerfectDatabase: false,
          useNativeMillSession: true,
          showTutorial: false,
          firstRun: false,
        );

        await startNewGame(tester);

        int hangsDetected = 0;
        final List<String> hangDetails = <String>[];

        for (int gameNum = 1; gameNum <= maxGames; gameNum++) {
          if (gameNum > 1) {
            GameController().reset(force: true);
            await tester.pumpAndSettle();
            await startNewGame(tester);
          }

          GameController().gameInstance.gameMode = GameMode.humanVsAi;
          GameController().gameInstance
                  .getPlayerByColor(PieceColor.white)
                  .isAi =
              false;
          GameController().gameInstance
                  .getPlayerByColor(PieceColor.black)
                  .isAi =
              true;

          int moveNum = 0;
          while (moveNum < maxMovesPerGame && !GameStateReader.isGameOver) {
            moveNum++;

            if (GameController().gameInstance.isAiSideToMove) {
              final int movesBefore = GameStateReader.moveCount;
              final bool responded = await _waitForAiProgress(
                tester,
                movesBefore: movesBefore,
                timeoutSeconds: aiTimeoutSeconds,
              );
              if (!responded) {
                hangsDetected++;
                hangDetails.add(
                  'Game $gameNum move $moveNum: AI did not respond within '
                  '$aiTimeoutSeconds s',
                );
                break;
              }
            } else {
              final bool moved = await _makeHumanTapMove(tester);
              if (!moved) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 150));
            }
          }

          if (hangsDetected > 0) {
            break;
          }
        }

        print('$logTag hangs=$hangsDetected details=$hangDetails');
        expect(hangsDetected, 0, reason: hangDetails.join('; '));
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

Future<bool> _waitForAiProgress(
  WidgetTester tester, {
  required int movesBefore,
  required int timeoutSeconds,
}) async {
  final DateTime deadline = DateTime.now().add(
    Duration(seconds: timeoutSeconds),
  );

  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (GameStateReader.moveCount > movesBefore) {
      return true;
    }

    if (GameStateReader.isGameOver) {
      return true;
    }

    if (!GameController().isEngineRunning &&
        !GameController().isEngineInDelay &&
        GameStateReader.moveCount > movesBefore) {
      return true;
    }
  }

  return false;
}

Future<bool> _makeHumanTapMove(WidgetTester tester) async {
  if (GameStateReader.isRemoving) {
    final List<int> targets = GameStateReader.opponentSquares;
    if (targets.isEmpty) {
      return false;
    }
    targets.shuffle();
    return BoardTapHelper.tapSquare(tester, targets.first);
  }

  if (GameStateReader.isPlacing) {
    final List<int> empty = GameStateReader.emptySquares;
    if (empty.isEmpty) {
      return false;
    }
    empty.shuffle();
    return BoardTapHelper.tapSquare(tester, empty.first);
  }

  if (GameStateReader.isMoving) {
    final List<int> pieces = GameStateReader.canCurrentSideFly
        ? GameStateReader.currentSideSquares
        : GameStateReader.movablePieces(GameStateReader.sideToMove);
    if (pieces.isEmpty) {
      return false;
    }
    pieces.shuffle();
    final int from = pieces.first;
    if (!await BoardTapHelper.tapSquare(tester, from)) {
      return false;
    }
    await tester.pump(const Duration(milliseconds: 120));

    final List<int> destinations = GameStateReader.canCurrentSideFly
        ? GameStateReader.emptySquares
        : GameStateReader.adjacentEmptySquaresOf(from);
    if (destinations.isEmpty) {
      return false;
    }
    destinations.shuffle();
    return BoardTapHelper.tapSquare(tester, destinations.first);
  }

  return false;
}
