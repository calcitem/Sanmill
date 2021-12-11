// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';

class TapHandler {
  final AnimationController animationController;
  final BuildContext context;
  final Function(String, {bool snackBar}) showTip;
  final VoidCallback onWin;

  TapHandler({
    required this.animationController,
    required this.context,
    required this.showTip,
    required this.onWin,
  });

  final GameMode gameMode = controller.gameInstance.gameMode;
  static const _tag = "[Tap Handler]";

  // TODO: [Leptopoda]
  final bool mounted = true;

  Future<void> onBoardTap(int sq) async {
    if (!mounted) return logger.v("[tap] Not ready, ignore tapping.");

    if (gameMode == GameMode.aiVsAi || gameMode == GameMode.testViaLAN) {
      return logger.v("$_tag Engine type is no human, ignore tapping.");
    }

    final position = controller.position;

    // If nobody has placed, start to go.
    if (position.phase == Phase.placing &&
        position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      controller.gameInstance.newGame();

      if (controller.gameInstance.isAiToMove) {
        if (controller.gameInstance.aiIsSearching) {
          return logger.i("$_tag AI is thinking, skip tapping.");
        } else {
          logger.i("[tap] AI is not thinking. AI is to move.");
          return engineToGo(isMoveNow: false);
        }
      }
    }

    if (controller.gameInstance.isAiToMove ||
        controller.gameInstance.aiIsSearching) {
      return logger.i("[tap] AI's turn, skip tapping.");
    }

    if (position.phase == Phase.ready) controller.gameInstance.start();

    // Human to go
    bool ret = false;
    try {
      switch (position.action) {
        case Act.place:
          if (await position.putPiece(sq)) {
            animationController.reset();
            animationController.animateTo(1.0);
            if (position.action == Act.remove) {
              showTip(S.of(context).tipMill, snackBar: true);
            } else {
              if (gameMode == GameMode.humanVsAi) {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  showTip(S.of(context).continueToMakeMove);
                } else {
                  showTip(S.of(context).tipPlaced);
                }
              } else {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  // TODO: HumanVsHuman - Change tip
                  showTip(S.of(context).tipPlaced);
                } else {
                  final side = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  showTip(
                    S.of(context).tipToMove(side),
                  );
                }
              }
            }
            ret = true;
            logger.v("[tap] putPiece: [$sq]");
            break;
          } else {
            logger.v("[tap] putPiece: skip [$sq]");
            showTip(S.of(context).tipBanPlace);
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.phase == Phase.placing) {
            showTip(S.of(context).tipCannotPlace, snackBar: true);
            break;
          }
          switch (position.selectPiece(sq)) {
            case SelectionResponse.r0:
              await Audios.playTone(Sound.select);
              controller.gameInstance.select(squareToIndex[sq]!);
              ret = true;
              logger.v("[tap] selectPiece: [$sq]");

              final us = controller.gameInstance.sideToMove;
              if (position.phase == Phase.moving &&
                  LocalDatabaseService.rules.mayFly &&
                  (controller.position.pieceOnBoardCount[us] ==
                          LocalDatabaseService.rules.flyPieceCount ||
                      controller.position.pieceOnBoardCount[us] == 3)) {
                logger.v("[tap] May fly.");
                showTip(S.of(context).tipCanMoveToAnyPoint, snackBar: true);
              } else {
                showTip(S.of(context).tipPlace, snackBar: true);
              }
              break;
            // TODO: [Leptopoda] deduplicate
            case SelectionResponse.r2:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                showTip(S.of(context).tipCannotMove, snackBar: true);
              }
              break;
            case SelectionResponse.r3:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
              break;
            case SelectionResponse.r4:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
              break;
            case SelectionResponse.r1:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              showTip(S.of(context).tipSelectWrong, snackBar: true);
              break;
          }
          break;

        case Act.remove:
          switch (await position.removePiece(sq)) {
            case RemoveResponse.r0:
              animationController.reset();
              animationController.animateTo(1.0);

              ret = true;
              logger.v("[tap] removePiece: [$sq]");
              if (controller.position.pieceToRemoveCount >= 1) {
                showTip(S.of(context).tipContinueMill, snackBar: true);
              } else {
                if (gameMode == GameMode.humanVsAi) {
                  showTip(S.of(context).tipRemoved);
                } else {
                  final them = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  showTip(S.of(context).tipToMove(them));
                }
              }
              break;
            case RemoveResponse.r2:
              await Audios.playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              showTip(S.of(context).tipSelectOpponentsPiece, snackBar: true);
              break;
            case RemoveResponse.r3:
              await Audios.playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              showTip(
                S.of(context).tipCannotRemovePieceFromMill,
                snackBar: true,
              );
              break;
            case RemoveResponse.r1:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] removePiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                showTip(S.of(context).tipBanRemove, snackBar: true);
              }
              break;
          }
          break;
        case Act.none:
      }

      if (ret) {
        controller.gameInstance.sideToMove = position.sideToMove;
        controller.gameInstance.moveHistory.add(position.record);

        // TODO: Need Others?
        // Increment ply counters. In particular,
        // rule50 will be reset to zero later on
        // in case of a remove.
        ++position.gamePly;
        ++position.st.rule50;
        ++position.st.pliesFromNull;

        if (position.record != null &&
            position.record!.uciMove.length > "-(1,2)".length) {
          if (position.posKeyHistory.isEmpty ||
              position.posKeyHistory.last != position.st.key) {
            position.posKeyHistory.add(position.st.key);
            if (LocalDatabaseService.rules.threefoldRepetitionRule &&
                position.hasGameCycle) {
              position.setGameOver(
                PieceColor.draw,
                GameOverReason.drawThreefoldRepetition,
              );
            }
          }
        } else {
          position.posKeyHistory.clear();
        }

        //position.move = m;
        final ExtMove m = position.record!;
        controller.position.recorder.prune();
        controller.position.recorder.moveIn(m, position);

        if (position.winner == PieceColor.nobody) {
          engineToGo(isMoveNow: false);
        } else {
          onWin();
        }
      }

      controller.gameInstance.sideToMove = position.sideToMove;
    } catch (e) {
      // TODO: [Leptopoda] improve error handling
      rethrow;
    }
  }

  Future<void> engineToGo({required bool isMoveNow}) async {
    bool _isMoveNow = isMoveNow;

    if (!mounted) return logger.i("[engineToGo] !mounted, skip engineToGo.");

    // TODO
    logger.v("[engineToGo] engine type is $gameMode");

    if (_isMoveNow) {
      if (!controller.gameInstance.isAiToMove) {
        logger.i("[engineToGo] Human to Move. Cannot get search result now.");
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).notAIsTurn);
      }
      if (!controller.position.recorder.isClean) {
        logger.i(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).aiIsNotThinking);
      }
    }

    while ((controller.position.winner == PieceColor.nobody ||
            LocalDatabaseService.preferences.isAutoRestart) &&
        controller.gameInstance.isAiToMove &&
        mounted) {
      if (gameMode == GameMode.aiVsAi) {
        showTip(
          "${controller.position.score[PieceColor.white]} : ${controller.position.score[PieceColor.black]} : ${controller.position.score[PieceColor.draw]}",
        );
      } else {
        if (mounted) {
          showTip(S.of(context).thinking);

          final String? n = controller.position.recorder.lastMove?.notation;

          if (LocalDatabaseService.preferences.screenReaderSupport &&
              controller.position.action != Act.remove &&
              n != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(CustomSnackBar("${S.of(context).human}: $n"));
          }
        }
      }

      final EngineResponse response;
      if (!_isMoveNow) {
        logger.v("[engineToGo] Searching...");
        response = await controller.engine.search(controller.position);
      } else {
        logger.v("[engineToGo] Get search result now...");
        response = await controller.engine.search(null);
        _isMoveNow = false;
      }

      logger.i("[engineToGo] Engine response type: ${response.type}");

      switch (response.type) {
        case EngineResponseType.move:
          final ExtMove extMove = response.value!;

          await controller.gameInstance.doMove(extMove);
          animationController.reset();
          animationController.animateTo(1.0);

          onWin();
          if (LocalDatabaseService.preferences.screenReaderSupport) {
            ScaffoldMessenger.of(context).showSnackBar(
              CustomSnackBar("${S.of(context).ai}: ${extMove.notation}"),
            );
          }
          break;
        case EngineResponseType.timeout:
          return showTip(S.of(context).timeout, snackBar: true);
        case EngineResponseType.nobestmove:
          showTip(S.of(context).error(response.type));
      }

      if (LocalDatabaseService.preferences.isAutoRestart &&
          controller.position.winner != PieceColor.nobody) {
        controller.gameInstance.newGame();
      }
    }
  }
}
