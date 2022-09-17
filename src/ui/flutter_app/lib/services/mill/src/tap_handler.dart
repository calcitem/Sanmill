// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

class TapHandler {
  static const _tag = "[Tap Handler]";

  final AnimationController animationController;
  final BuildContext context;

  final controller = MillController();
  final gameMode = MillController().gameInstance.gameMode;
  final showTip = MillController().tip.showTip;

  //final position = MillController().position;

  TapHandler({
    required this.animationController,
    required this.context,
  });

  bool get _isGameRunning =>
      MillController().position.winner == PieceColor.nobody;
  bool get _isAiToMove => controller.gameInstance._isAiToMove;

  bool get _isBoardEmpty =>
      MillController().position.pieceOnBoardCount[PieceColor.white] == 0 &&
      MillController().position.pieceOnBoardCount[PieceColor.black] == 0;

  makeAiFirstMoveIfNecessary() {
    // WAR: Fix first tap response slow when piece count changed
    if (gameMode != GameMode.humanVsHuman &&
        MillController().position.phase == Phase.placing &&
        _isBoardEmpty) {
      //controller.reset();

      if (_isAiToMove) {
        logger.i("$_tag AI is not thinking. AI is to move.");
        engineToGo(isMoveNow: false);
        return;
      }
    }
  }

  Future<void> onBoardTap(int sq) async {
    if (gameMode == GameMode.testViaLAN) {
      return logger.v("$_tag Engine type is no human, ignore tapping.");
    }

    makeAiFirstMoveIfNecessary();

    if (_isAiToMove) {
      return logger.i("$_tag AI's turn, skip tapping.");
    }

    // Human to go
    bool ret = false;
    switch (MillController().position._action) {
      case Act.place:
        if (MillController().position._putPiece(sq)) {
          animationController.reset();
          animationController.animateTo(1.0);
          if (MillController().position._action == Act.remove) {
            showTip(S.of(context).tipMill, snackBar: true);
          } else {
            if (gameMode == GameMode.humanVsAi) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                showTip(S.of(context).continueToMakeMove);
              } else {
                showTip(S.of(context).tipPlaced);
              }
            } else if (gameMode == GameMode.humanVsHuman) {
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
        if (MillController().position.phase == Phase.placing) {
          showTip(S.of(context).tipCannotPlace, snackBar: true);
          break;
        }

        var selectRet = MillController().position._selectPiece(sq);

        switch (selectRet) {
          case MillResponseOK():
            await Audios().playTone(Sound.select);
            controller.gameInstance._select(squareToIndex[sq]!);
            ret = true;
            logger.v("$_tag selectPiece: [$sq]");

            final pieceOnBoardCount = MillController()
                .position
                .pieceOnBoardCount[controller.gameInstance.sideToMove];
            if (MillController().position.phase == Phase.moving &&
                DB().ruleSettings.mayFly &&
                (pieceOnBoardCount == DB().ruleSettings.flyPieceCount ||
                    pieceOnBoardCount == 3)) {
              // TODO: [Calcitem, Leptopoda] Why is the [DB().ruleSettings.flyPieceCount] not respected?
              logger.v("$_tag May fly.");
              showTip(S.of(context).tipCanMoveToAnyPoint, snackBar: true);
            } else {
              showTip(S.of(context).tipPlace, snackBar: true);
            }
            break;
          case IllegalPhase():
            if (MillController().position.phase != Phase.gameOver) {
              showTip(S.of(context).tipCannotMove, snackBar: true);
            }
            break;
          case CanOnlyMoveToAdjacentEmptyPoints():
            showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
            break;
          case SelectOurPieceToMove():
            showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
            break;
          case IllegalAction():
            showTip(S.of(context).tipSelectWrong, snackBar: true);
            break;
          default:
            await Audios().playTone(Sound.illegal);
            logger.v("$_tag selectPiece: skip [$sq]");
            break;
        }

        break;

      case Act.remove:
        var removeRet = await MillController().position._removePiece(sq);

        animationController.reset();
        animationController.animateTo(1.0);

        switch (removeRet) {
          case MillResponseOK():
            ret = true;
            logger.v("$_tag removePiece: [$sq]");
            if (MillController().position._pieceToRemoveCount >= 1) {
              showTip(S.of(context).tipContinueMill, snackBar: true);
            } else {
              if (gameMode == GameMode.humanVsAi) {
                showTip(S.of(context).tipRemoved);
              } else if (gameMode == GameMode.humanVsHuman) {
                final them = controller.gameInstance.sideToMove.opponent
                    .playerName(context);
                showTip(S.of(context).tipToMove(them));
              }
            }
            break;
          case CanNotRemoveSelf():
            logger.i("$_tag removePiece: Cannot Remove our pieces, skip [$sq]");
            showTip(S.of(context).tipSelectOpponentsPiece, snackBar: true);
            break;
          case CanNotRemoveMill():
            logger.i(
              "$_tag removePiece: Cannot remove piece from Mill, skip [$sq]",
            );
            showTip(S.of(context).tipCannotRemovePieceFromMill, snackBar: true);
            break;
          default:
            logger.v("$_tag removePiece: skip [$sq]");
            if (MillController().position.phase != Phase.gameOver) {
              showTip(S.of(context).tipBanRemove, snackBar: true);
            }
            break;
        }
    }

    if (ret) {
      controller.gameInstance.sideToMove = MillController().position.sideToMove;

      // TODO: Need Others?
      // Increment ply counters. In particular,
      // rule50 will be reset to zero later on
      // in case of a remove.
      ++MillController().position._gamePly;
      ++MillController().position.st.rule50;
      ++MillController().position.st.pliesFromNull;

      if (MillController().position._record != null &&
          MillController().position._record!.move.length > "-(1,2)".length) {
        if (MillController().position._posKeyHistory.isEmpty ||
            MillController().position._posKeyHistory.last !=
                MillController().position.st.key) {
          MillController()
              .position
              ._posKeyHistory
              .add(MillController().position.st.key);
          if (DB().ruleSettings.threefoldRepetitionRule &&
              MillController().position._hasGameCycle) {
            MillController().position._setGameOver(
                  PieceColor.draw,
                  GameOverReason.drawThreefoldRepetition,
                );
          }
        }
      } else {
        MillController().position._posKeyHistory.clear();
      }

      if (MillController().position._record != null) {
        controller.recorder.add(MillController().position._record!);
        if (MillController().position._record!.type == MoveType.remove) {
          controller.recorder.lastPositionWithRemove =
              MillController().position._fen;
        }
      }

      if (_isGameRunning) {
        if (gameMode == GameMode.humanVsAi) {
          engineToGo(isMoveNow: false);
        }
      } else {
        _showResult();
      }
    } else {
      await Audios().playTone(Sound.illegal);
    }

    controller.gameInstance.sideToMove = MillController().position.sideToMove;

    MillController().headIcons.showIcons();
  }

  showSnakeBarAiNotation(ExtMove extMove) {
    if (DB().generalSettings.screenReaderSupport) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        CustomSnackBar("${S.of(context).ai}: ${extMove.notation}"),
      );
    }
  }

  showSnakeBarHumanNotation() {
    final String? n = controller.recorder.lastF?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        MillController().position._action != Act.remove &&
        n != null) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("${S.of(context).human}: $n"));
    }
  }

  // TODO: [Leptopoda] The reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<void> engineToGo({required bool isMoveNow}) async {
    const tag = "[engineToGo]";

    // TODO
    logger.v("$tag engine type is $gameMode");

    if (isMoveNow) {
      if (controller.gameInstance._isHumanToMove) {
        logger.i("$tag Human to Move. Cannot get search result now.");
        return rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).notAIsTurn);
      }
      if (controller.recorder.isNotEmpty) {
        logger.i("$tag History is not clean. Cannot get search result now.");
        return rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).aiIsNotThinking);
      }
    }

    while (
        _isAiToMove && (_isGameRunning || DB().generalSettings.isAutoRestart)) {
      if (gameMode == GameMode.aiVsAi) {
        showTip(MillController().position.scoreString);
      } else {
        showTip(S.of(context).thinking);

        // TODO: Show snake bar immediately when tapping
        showSnakeBarHumanNotation();
      }

      try {
        logger.v("$tag Searching..., isMoveNow: $isMoveNow");
        final extMove = await controller.engine.search(moveNow: isMoveNow);

        controller.gameInstance.doMove(extMove);

        animationController.reset();
        animationController.animateTo(1.0);

        showSnakeBarAiNotation(extMove);

        // TODO: Do not throw exception
      } on EngineTimeOut {
        logger.i("$tag Engine response type: timeout");
        showTip(S.of(context).timeout, snackBar: true);
      } on EngineNoBestMove {
        logger.i("$tag Engine response type: nobestmove");
        showTip(S.of(context).error("No best move"));
      }

      if (DB().generalSettings.isAutoRestart == true &&
          MillController().position.winner != PieceColor.nobody) {
        MillController().reset();
      } else {
        _showResult();
      }
    }
  }

  void _showResult() {
    final winner = controller.position.winner;
    final message = winner.getWinString(context);
    if (message != null) {
      showTip(message);
      MillController().headIcons.showIcons();
    }

    if (!DB().generalSettings.isAutoRestart &&
        winner != PieceColor.nobody &&
        gameMode != GameMode.aiVsAi) {
      showDialog(
        context: context,
        builder: (_) => GameResultAlert(winner: winner),
      );
    }
  }
}
