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

    if (controller.gameInstance._isAiToMove ||
        controller.gameInstance._aiIsSearching) {
      return logger.i("[tap] AI's turn, skip tapping.");
    }

    final position = controller.position;

    // Human to go
    bool ret = false;
    try {
      switch (position._action) {
        case Act.place:
          if (await position._putPiece(sq)) {
            animationController.reset();
            animationController.animateTo(1.0);
            if (position._action == Act.remove) {
              MillController()
                  .tip
                  .showTip(S.of(context).tipMill, snackBar: true);
            } else {
              if (gameMode == GameMode.humanVsAi) {
                if (DB().rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  MillController()
                      .tip
                      .showTip(S.of(context).continueToMakeMove);
                } else {
                  MillController().tip.showTip(S.of(context).tipPlaced);
                }
              } else {
                if (DB().rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
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
          switch (position._selectPiece(sq)) {
            case SelectionResponse.ok:
              await Audios().playTone(Sound.select);
              controller.gameInstance._select(squareToIndex[sq]!);
              ret = true;
              logger.v("[tap] selectPiece: [$sq]");

              final us = controller.gameInstance.sideToMove;
              if (position.phase == Phase.moving &&
                  DB().rules.mayFly &&
                  (controller.position.pieceOnBoardCount[us] ==
                          DB().rules.flyPieceCount ||
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
          switch (await position._removePiece(sq)) {
            case RemoveResponse.ok:
              animationController.reset();
              animationController.animateTo(1.0);

              ret = true;
              logger.v("[tap] removePiece: [$sq]");
              if (controller.position._pieceToRemoveCount >= 1) {
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
      }

      if (ret) {
        controller.gameInstance.sideToMove = position.sideToMove;

        // TODO: Need Others?
        // Increment ply counters. In particular,
        // rule50 will be reset to zero later on
        // in case of a remove.
        ++position._gamePly;
        ++position.st.rule50;
        ++position.st.pliesFromNull;

        if (position._record != null &&
            position._record!.move.length > "-(1,2)".length) {
          if (position._posKeyHistory.isEmpty ||
              position._posKeyHistory.last != position.st.key) {
            position._posKeyHistory.add(position.st.key);
            if (DB().rules.threefoldRepetitionRule && position._hasGameCycle) {
              position._setGameOver(
                PieceColor.draw,
                GameOverReason.drawThreefoldRepetition,
              );
            }
          }
        } else {
          position._posKeyHistory.clear();
        }

        //position.move = m;
        final ExtMove m = position._record!;
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

  // TODO: [Leptopoda] the reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<void> engineToGo({required bool isMoveNow}) async {
    bool _isMoveNow = isMoveNow;

    // TODO
    logger.v("[engineToGo] engine type is $gameMode");

    if (_isMoveNow) {
      if (!controller.gameInstance._isAiToMove) {
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
            DB().preferences.isAutoRestart) &&
        controller.gameInstance._isAiToMove) {
      if (gameMode == GameMode.aiVsAi) {
        MillController().tip.showTip(
              "${controller.position.score[PieceColor.white]} : ${controller.position.score[PieceColor.black]} : ${controller.position.score[PieceColor.draw]}",
            );
      } else {
        MillController().tip.showTip(S.of(context).thinking);

        final String? n = controller.recorder.lastMove?.notation;

        if (DB().preferences.screenReaderSupport &&
            controller.position._action != Act.remove &&
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

          await controller.gameInstance._doMove(extMove);
          animationController.reset();
          animationController.animateTo(1.0);

          if (DB().preferences.screenReaderSupport) {
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

      _showResult();
    }
  }

  void _showResult() {
    final winner = controller.position.winner;
    final message = winner.getWinString(context);
    if (message != null) {
      MillController().tip.showTip(message);
    }

    if (!DB().preferences.isAutoRestart && winner != PieceColor.nobody) {
      showDialog(
        context: context,
        builder: (_) => GameResultAlert(
          winner: winner,
        ),
      );
    }
  }
}
