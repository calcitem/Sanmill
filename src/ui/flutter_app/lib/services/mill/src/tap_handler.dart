// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

// TODO: [Leptopoda] to fix the big piece we have to reset the selectedPiece by setting it to null :)

class TapHandler {
  final AnimationController animationController;
  final BuildContext context;
  final MillController controller = MillController();

  TapHandler({
    required this.animationController,
    required this.context,
  }) {
    gameMode = controller.gameInstance.gameMode;
  }

  late final GameMode gameMode;

  static const _tag = "[Tap Handler]";

  Future<void> onBoardTap(int sq) async {
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
              MillController()
                  .tip
                  .showTip(S.of(context).tipMill, snackBar: true);
            } else {
              if (gameMode == GameMode.humanVsAi) {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  MillController()
                      .tip
                      .showTip(S.of(context).continueToMakeMove);
                } else {
                  MillController().tip.showTip(S.of(context).tipPlaced);
                }
              } else {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  // TODO: HumanVsHuman - Change tip
                  MillController().tip.showTip(S.of(context).tipPlaced);
                } else {
                  final side = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  MillController().tip.showTip(
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
            MillController().tip.showTip(S.of(context).tipBanPlace);
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.phase == Phase.placing) {
            MillController()
                .tip
                .showTip(S.of(context).tipCannotPlace, snackBar: true);
            break;
          }
          switch (position.selectPiece(sq)) {
            case SelectionResponse.ok:
              await Audios().playTone(Sound.select);
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
                MillController().tip.showTip(
                      S.of(context).tipCanMoveToAnyPoint,
                      snackBar: true,
                    );
              } else {
                MillController()
                    .tip
                    .showTip(S.of(context).tipPlace, snackBar: true);
              }
              break;
            // TODO: [Leptopoda] deduplicate
            case SelectionResponse.illegalPhase:
              await Audios().playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                MillController()
                    .tip
                    .showTip(S.of(context).tipCannotMove, snackBar: true);
              }
              break;
            case SelectionResponse.canOnlyMoveToAdjacentEmptyPoints:
              await Audios().playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              MillController()
                  .tip
                  .showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
              break;
            case SelectionResponse.pleaseSelectOurPieceToMove:
              await Audios().playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              MillController()
                  .tip
                  .showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
              break;
            case SelectionResponse.illegalAction:
              await Audios().playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              MillController()
                  .tip
                  .showTip(S.of(context).tipSelectWrong, snackBar: true);
              break;
          }
          break;

        case Act.remove:
          switch (await position.removePiece(sq)) {
            case RemoveResponse.ok:
              animationController.reset();
              animationController.animateTo(1.0);

              ret = true;
              logger.v("[tap] removePiece: [$sq]");
              if (controller.position.pieceToRemoveCount >= 1) {
                MillController()
                    .tip
                    .showTip(S.of(context).tipContinueMill, snackBar: true);
              } else {
                if (gameMode == GameMode.humanVsAi) {
                  MillController().tip.showTip(S.of(context).tipRemoved);
                } else {
                  final them = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  MillController().tip.showTip(S.of(context).tipToMove(them));
                }
              }
              break;
            case RemoveResponse.cannotRemoveOurPiece:
              await Audios().playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              MillController().tip.showTip(
                    S.of(context).tipSelectOpponentsPiece,
                    snackBar: true,
                  );
              break;
            case RemoveResponse.cannotRemovePieceFromMill:
              await Audios().playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              MillController().tip.showTip(
                    S.of(context).tipCannotRemovePieceFromMill,
                    snackBar: true,
                  );
              break;
            case RemoveResponse.illegalPhase:
            case RemoveResponse.illegalAction:
            case RemoveResponse.noPieceToRemove:
              await Audios().playTone(Sound.illegal);
              logger.v("[tap] removePiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                MillController()
                    .tip
                    .showTip(S.of(context).tipBanRemove, snackBar: true);
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
            position.record!.move.length > "-(1,2)".length) {
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
        controller.recorder.prune();
        controller.recorder.moveIn(m);

        if (position.winner == PieceColor.nobody) {
          engineToGo(isMoveNow: false);
        } else {
          _showResult();
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

    // TODO
    logger.v("[engineToGo] engine type is $gameMode");

    if (_isMoveNow) {
      if (!controller.gameInstance.isAiToMove) {
        logger.i("[engineToGo] Human to Move. Cannot get search result now.");
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).notAIsTurn);
      }
      if (!controller.recorder.isClean) {
        logger.i(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).aiIsNotThinking);
      }
    }

    while ((controller.position.winner == PieceColor.nobody ||
            LocalDatabaseService.preferences.isAutoRestart) &&
        controller.gameInstance.isAiToMove) {
      if (gameMode == GameMode.aiVsAi) {
        MillController().tip.showTip(
              "${controller.position.score[PieceColor.white]} : ${controller.position.score[PieceColor.black]} : ${controller.position.score[PieceColor.draw]}",
            );
      } else {
        MillController().tip.showTip(S.of(context).thinking);

        final String? n = controller.recorder.lastMove?.notation;

        if (LocalDatabaseService.preferences.screenReaderSupport &&
            controller.position.action != Act.remove &&
            n != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(CustomSnackBar("${S.of(context).human}: $n"));
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

          _showResult();
          if (LocalDatabaseService.preferences.screenReaderSupport) {
            ScaffoldMessenger.of(context).showSnackBar(
              CustomSnackBar("${S.of(context).ai}: ${extMove.notation}"),
            );
          }
          break;
        case EngineResponseType.timeout:
          return MillController()
              .tip
              .showTip(S.of(context).timeout, snackBar: true);
        case EngineResponseType.nobestmove:
          MillController().tip.showTip(S.of(context).error(response.type));
      }

      if (LocalDatabaseService.preferences.isAutoRestart &&
          controller.position.winner != PieceColor.nobody) {
        controller.gameInstance.newGame();
      }
    }
  }

  void _showResult() {
    final winner = controller.position.winner;
    final message = winner.getWinString(context);
    if (message != null) {
      MillController().tip.showTip(message);
    }

    if (!LocalDatabaseService.preferences.isAutoRestart &&
        winner != PieceColor.nobody) {
      GameResultAlert(
        winner: winner,
        // TODO: [Leptopoda] the only reason not having the function in the GameAlert is engineToGo ;)
        onRestart: () {
          controller.gameInstance.newGame();
          MillController()
              .tip
              .showTip(S.of(context).gameStarted, snackBar: true);

          if (controller.gameInstance.isAiToMove) {
            logger.i("$_tag New game, AI to move.");
            engineToGo(isMoveNow: false);
          }
        },
      );
    }
  }
}
