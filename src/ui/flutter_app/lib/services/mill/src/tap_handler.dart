// ignore_for_file: use_build_context_synchronously

part of '../mill.dart';

class TapHandler {
  TapHandler({
    required this.context,
  });

  //final position = MillController().position;

  static const String _tag = "[Tap Handler]";

  final BuildContext context;

  final MillController controller = MillController();
  //final gameMode = MillController().gameInstance.gameMode;
  // ignore: always_specify_types
  final showTip = MillController().headerTipNotifier.showTip;

  bool get _isGameRunning =>
      MillController().position.winner == PieceColor.nobody;
  bool get isAiToMove => controller.gameInstance.isAiToMove;

  bool get _isBoardEmpty =>
      MillController().position.pieceOnBoardCount[PieceColor.white] == 0 &&
      MillController().position.pieceOnBoardCount[PieceColor.black] == 0;

  Future<EngineResponse> setupPosition(int sq) async {
    if (MillController().position.action == Act.place ||
        MillController().position.action == Act.select) {
      MillController().position._putPieceForSetupPosition(sq);
    } else if (MillController().position.action == Act.remove) {
      MillController().position._removePieceForSetupPosition(sq);
    } else {
      assert(false);
    }

    MillController().setupPositionNotifier.updateIcons();
    MillController().headerTipNotifier.showTip(ExtMove.sqToNotation(sq),
        snackBar: false); // TODO: snackBar is false?

    return const EngineResponseHumanOK(); // TODO: Right?
  }

  Future<EngineResponse> onBoardTap(int sq) async {
    if (!MillController().isReady) {
      logger.i("$_tag Not ready, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (MillController().gameInstance.gameMode == GameMode.setupPosition) {
      logger.v("$_tag Setup position.");
      await setupPosition(sq);
      return const EngineResponseSkip();
    }

    if (MillController().gameInstance.gameMode == GameMode.testViaLAN) {
      logger.v("$_tag Engine type is no human, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (MillController().position.phase == Phase.gameOver) {
      logger.v("$_tag Phase is gameOver, ignore tapping.");
      return const EngineResponseSkip();
    }

    // TODO: WAR
    if ((MillController().gameInstance.sideToMove == PieceColor.white ||
            MillController().gameInstance.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return const EngineResponseSkip();
    }

    if ((MillController().position.sideToMove == PieceColor.white ||
            MillController().position.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return const EngineResponseSkip();
    }

    // WAR: Fix first tap response slow when piece count changed
    if (MillController().gameInstance.gameMode != GameMode.humanVsHuman &&
        MillController().position.phase == Phase.placing &&
        _isBoardEmpty) {
      //controller.reset();

      if (isAiToMove) {
        logger.i("$_tag AI is not thinking. AI is to move.");

        return MillController().engineToGo(context, isMoveNow: false);
      }
    }

    if (isAiToMove) {
      logger.i("$_tag AI's turn, skip tapping.");
      return const EngineResponseSkip();
    }

    // Human to go
    bool ret = false;
    switch (MillController().position.action) {
      case Act.place:
        if (MillController().position._putPiece(sq)) {
          MillController().animationController.reset();
          MillController().animationController.animateTo(1.0);
          if (MillController().position.action == Act.remove) {
            showTip(S.of(context).tipMill);
          } else {
            if (MillController().gameInstance.gameMode == GameMode.humanVsAi) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                showTip(S.of(context).continueToMakeMove, snackBar: false);
              } else {
                if (MillController().position.phase == Phase.placing) {
                  showTip(S.of(context).tipPlaced, snackBar: false);
                } else {
                  showTip(S.of(context).tipMove, snackBar: false);
                }
              }
            } else if (MillController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                // TODO: HumanVsHuman - Change tip
                if (MillController().position.phase == Phase.placing) {
                  showTip(S.of(context).tipPlaced, snackBar: false);
                } else {
                  showTip(S.of(context).tipMove, snackBar: false);
                }
              } else {
                final String side = controller.gameInstance.sideToMove.opponent
                    .playerName(context);
                showTip(S.of(context).tipToMove(side), snackBar: false);
              }
            }
          }
          ret = true;
          logger.v("$_tag putPiece: [$sq]");
          break;
        } else {
          logger.v("$_tag putPiece: skip [$sq]");
          if (!(MillController().position.phase == Phase.moving &&
              MillController().position._board[sq] ==
                  MillController().position.sideToMove)) {
            showTip(S.of(context).tipBanPlace);
          }
        }

        // If cannot move, retry select, do not break
        //[[fallthrough]];
        continue select;
      select:
      case Act.select:
        if (MillController().position.phase == Phase.placing) {
          showTip(S.of(context).tipCannotPlace);
          break;
        }

        final MillResponse selectRet =
            MillController().position._selectPiece(sq);

        switch (selectRet) {
          case MillResponseOK():
            Audios().playTone(Sound.select);
            controller.gameInstance._select(squareToIndex[sq]!);
            ret = true;
            logger.v("$_tag selectPiece: [$sq]");

            final int? pieceOnBoardCount = MillController()
                .position
                .pieceOnBoardCount[controller.gameInstance.sideToMove];
            if (MillController().position.phase == Phase.moving &&
                DB().ruleSettings.mayFly &&
                (pieceOnBoardCount! <= DB().ruleSettings.flyPieceCount &&
                    pieceOnBoardCount >= 3)) {
              logger.v("$_tag May fly.");
              showTip(S.of(context).tipCanMoveToAnyPoint);
            } else {
              showTip(S.of(context).tipPlace, snackBar: false);
              if (DB().generalSettings.screenReaderSupport) {
                showTip(S.of(context).selected);
              }
            }
            break;
          case IllegalPhase():
            if (MillController().position.phase != Phase.gameOver) {
              showTip(S.of(context).tipCannotMove);
            }
            break;
          case CanOnlyMoveToAdjacentEmptyPoints():
            showTip(S.of(context).tipCanMoveOnePoint);
            break;
          case SelectOurPieceToMove():
            showTip(S.of(context).tipSelectPieceToMove);
            break;
          case IllegalAction():
            showTip(S.of(context).tipSelectWrong);
            break;
          default:
            Audios().playTone(Sound.illegal);
            logger.v("$_tag selectPiece: skip [$sq]");
            break;
        }

        break;

      case Act.remove:
        final MillResponse removeRet =
            MillController().position._removePiece(sq);

        MillController().animationController.reset();
        MillController().animationController.animateTo(1.0);

        switch (removeRet) {
          case MillResponseOK():
            ret = true;
            logger.v("$_tag removePiece: [$sq]");
            if (MillController().position._pieceToRemoveCount >= 1) {
              showTip(S.of(context).tipContinueMill);
            } else {
              if (MillController().gameInstance.gameMode ==
                  GameMode.humanVsAi) {
                showTip(S.of(context).tipRemoved, snackBar: false);
              } else if (MillController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String them = controller.gameInstance.sideToMove.opponent
                    .playerName(context);
                showTip(S.of(context).tipToMove(them), snackBar: false);
              }
            }
            break;
          case CanNotRemoveSelf():
            logger.i("$_tag removePiece: Cannot Remove our pieces, skip [$sq]");
            showTip(S.of(context).tipSelectOpponentsPiece);
            break;
          case CanNotRemoveMill():
            logger.i(
              "$_tag removePiece: Cannot remove piece from Mill, skip [$sq]",
            );
            showTip(S.of(context).tipCannotRemovePieceFromMill);
            break;
          default:
            logger.v("$_tag removePiece: skip [$sq]");
            if (MillController().position.phase != Phase.gameOver) {
              showTip(S.of(context).tipBanRemove);
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
        if (posKeyHistory.isEmpty ||
            posKeyHistory.last != MillController().position.st.key) {
          posKeyHistory.add(MillController().position.st.key);
          if (DB().ruleSettings.threefoldRepetitionRule &&
              MillController().position._hasGameCycle) {
            MillController().position._setGameOver(
                  PieceColor.draw,
                  GameOverReason.drawThreefoldRepetition,
                );
          }
        }
      } else {
        posKeyHistory.clear();
      }

      if (MillController().position._record != null) {
        controller.recorder
            .addAndDeduplicate(MillController().position._record!);
        if (MillController().position._record!.type == MoveType.remove) {
          controller.recorder.lastPositionWithRemove =
              MillController().position.fen;
        }

        // TODO: moveHistoryText is not lightweight.
        if (EnvironmentConfig.catcher == true) {
          final CatcherOptions options = catcher.getCurrentConfig()!;
          options.customParameters["MoveList"] =
              MillController().recorder.moveHistoryText;
        }
      }

      if (_isGameRunning && MillController().gameInstance.isAiToMove) {
        if (MillController().gameInstance.gameMode == GameMode.humanVsAi) {
          return MillController().engineToGo(context, isMoveNow: false);
        }
      } else {
        return const EngineResponseHumanOK();
      }
    } else {
      Audios().playTone(Sound.illegal);
    }

    controller.gameInstance.sideToMove = MillController().position.sideToMove;

    MillController().headerIconsNotifier.showIcons();
    MillController().boardSemanticsNotifier.updateSemantics();

    return const EngineResponseHumanOK();
  }
}
