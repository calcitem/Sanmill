// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

class TapHandler {
  static const _tag = "[Tap Handler]";

  final AnimationController animationController;
  final BuildContext context;

  final controller = MillController();
  final gameMode = MillController().gameInstance.gameMode;
  final showTip = MillController().tip.showTip;

  TapHandler({
    required this.animationController,
    required this.context,
  });

  Future<void> onBoardTap(int sq) async {
    if (gameMode == GameMode.aiVsAi || gameMode == GameMode.testViaLAN) {
      return logger.v("$_tag Engine type is no human, ignore tapping.");
    }

    if (controller.gameInstance._isAiToMove) {
      return logger.i("$_tag AI's turn, skip tapping.");
    }

    final position = controller.position;

    // Human to go
    bool ret = false;
    switch (position._action) {
      case Act.place:
        if (await position._putPiece(sq)) {
          animationController.reset();
          animationController.animateTo(1.0);
          if (position._action == Act.remove) {
            showTip(S.of(context).tipMill, snackBar: true);
          } else {
            if (gameMode == GameMode.humanVsAi) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                showTip(S.of(context).continueToMakeMove);
              } else {
                showTip(S.of(context).tipPlaced);
              }
            } else {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
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
          logger.v("$_tag putPiece: [$sq]");
          break;
        } else {
          logger.v("$_tag putPiece: skip [$sq]");
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

        try {
          position._selectPiece(sq);

          await Audios().playTone(Sound.select);
          controller.gameInstance._select(squareToIndex[sq]!);
          ret = true;
          logger.v("$_tag selectPiece: [$sq]");

          final pieceOnBoardCount =
              position.pieceOnBoardCount[controller.gameInstance.sideToMove];
          if (position.phase == Phase.moving &&
              DB().ruleSettings.mayFly &&
              (pieceOnBoardCount == DB().ruleSettings.flyPieceCount ||
                  pieceOnBoardCount == 3)) {
            // TODO: [Calcitem, Leptopoda] Why is the [DB().ruleSettings.flyPieceCount] not respected?
            logger.v("$_tag May fly.");
            showTip(S.of(context).tipCanMoveToAnyPoint, snackBar: true);
          } else {
            showTip(S.of(context).tipPlace, snackBar: true);
          }
        } on IllegalPhase {
          if (position.phase != Phase.gameOver) {
            showTip(S.of(context).tipCannotMove, snackBar: true);
          }
        } on CanOnlyMoveToAdjacentEmptyPoints {
          showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
        } on SelectOurPieceToMove {
          showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
        } on IllegalAction {
          showTip(S.of(context).tipSelectWrong, snackBar: true);
        } finally {
          await Audios().playTone(Sound.illegal);
          logger.v("$_tag selectPiece: skip [$sq]");
        }
        break;

      case Act.remove:
        try {
          await position._removePiece(sq);

          animationController.reset();
          animationController.animateTo(1.0);

          ret = true;
          logger.v("$_tag removePiece: [$sq]");
          if (position._pieceToRemoveCount >= 1) {
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
        } on CanNotRemoveSelf {
          logger.i("$_tag removePiece: Cannot Remove our pieces, skip [$sq]");
          showTip(S.of(context).tipSelectOpponentsPiece, snackBar: true);
        } on CanNotRemoveMill {
          logger.i(
            "$_tag removePiece: Cannot remove piece from Mill, skip [$sq]",
          );
          showTip(S.of(context).tipCannotRemovePieceFromMill, snackBar: true);
        } on MillResponse {
          logger.v("$_tag removePiece: skip [$sq]");
          if (position.phase != Phase.gameOver) {
            showTip(S.of(context).tipBanRemove, snackBar: true);
          }
        } finally {
          await Audios().playTone(Sound.illegal);
        }
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
          if (DB().ruleSettings.threefoldRepetitionRule &&
              position._hasGameCycle) {
            position._setGameOver(
              PieceColor.draw,
              GameOverReason.drawThreefoldRepetition,
            );
          }
        }
      } else {
        position._posKeyHistory.clear();
      }

      controller.recorder.add(position._record!);

      if (position.winner == PieceColor.nobody) {
        engineToGo(isMoveNow: false);
      } else {
        _showResult();
      }
    }

    controller.gameInstance.sideToMove = position.sideToMove;
  }

  // TODO: [Leptopoda] The reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<void> engineToGo({required bool isMoveNow}) async {
    const _tag = "[engineToGo]";

    final position = controller.position;

    // TODO
    logger.v("$_tag engine type is $gameMode");

    if (isMoveNow) {
      if (!controller.gameInstance._isAiToMove) {
        logger.i("$_tag Human to Move. Cannot get search result now.");
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).notAIsTurn);
      }
      if (controller.recorder.isNotEmpty) {
        logger.i("$_tag History is not clean. Cannot get search result now.");
        return ScaffoldMessenger.of(context)
            .showSnackBarClear(S.of(context).aiIsNotThinking);
      }
    }

    while ((position.winner == PieceColor.nobody ||
            DB().generalSettings.isAutoRestart) &&
        controller.gameInstance._isAiToMove) {
      if (gameMode == GameMode.aiVsAi) {
        showTip(position.scoreString);
      } else {
        showTip(S.of(context).thinking);

        final String? n = controller.recorder.lastF?.notation;

        if (DB().generalSettings.screenReaderSupport &&
            position._action != Act.remove &&
            n != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(CustomSnackBar("${S.of(context).human}: $n"));
        }
      }

      try {
        logger.v("$_tag Searching..., isMoveNow: $isMoveNow");
        final extMove = await controller.engine.search(moveNow: isMoveNow);

        await controller.gameInstance.doMove(extMove);
        animationController.reset();
        animationController.animateTo(1.0);

        if (DB().generalSettings.screenReaderSupport) {
          ScaffoldMessenger.of(context).showSnackBar(
            CustomSnackBar("${S.of(context).ai}: ${extMove.notation}"),
          );
        }
      } on EngineTimeOut {
        logger.i("$_tag Engine response type: timeout");
        showTip(S.of(context).timeout, snackBar: true);
      } on EngineNoBestMove {
        logger.i("$_tag Engine response type: nobestmove");
        showTip(S.of(context).error("No best move"));
      }

      _showResult();
    }
  }

  void _showResult() {
    final winner = controller.position.winner;
    final message = winner.getWinString(context);
    if (message != null) {
      showTip(message);
    }

    if (!DB().generalSettings.isAutoRestart && winner != PieceColor.nobody) {
      showDialog(
        context: context,
        builder: (_) => GameResultAlert(winner: winner),
      );
    }
  }
}
