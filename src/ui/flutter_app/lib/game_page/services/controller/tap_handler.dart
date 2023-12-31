// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../mill.dart';

class TapHandler {
  TapHandler({
    required this.context,
  });

  //final position = MillController().position;

  static const String _logTag = "[Tap Handler]";

  final BuildContext context;

  final GameController controller = GameController();
  //final gameMode = MillController().gameInstance.gameMode;
  // ignore: always_specify_types
  final showTip = GameController().headerTipNotifier.showTip;

  bool get _isGameRunning =>
      GameController().position.winner == PieceColor.nobody;
  bool get isAiToMove => controller.gameInstance.isAiToMove;

  bool get _isBoardEmpty =>
      GameController().position.pieceOnBoardCount[PieceColor.white] == 0 &&
      GameController().position.pieceOnBoardCount[PieceColor.black] == 0;

  Future<EngineResponse> setupPosition(int sq) async {
    if (GameController().position.action == Act.place ||
        GameController().position.action == Act.select) {
      GameController().position._putPieceForSetupPosition(sq);
    } else if (GameController().position.action == Act.remove) {
      GameController().position._removePieceForSetupPosition(sq);
    } else {
      assert(false);
    }

    GameController().setupPositionNotifier.updateIcons();
    GameController().headerTipNotifier.showTip(ExtMove.sqToNotation(sq),
        snackBar: false); // TODO: snackBar is false?

    return const EngineResponseHumanOK(); // TODO: Right?
  }

  Future<EngineResponse> onBoardTap(int sq) async {
    if (!GameController().isControllerReady) {
      logger.i("$_logTag Not ready, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (GameController().gameInstance.gameMode == GameMode.setupPosition) {
      logger.v("$_logTag Setup position.");
      await setupPosition(sq);
      return const EngineResponseSkip();
    }

    if (GameController().gameInstance.gameMode == GameMode.testViaLAN) {
      logger.v("$_logTag Engine type is no human, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (GameController().position.phase == Phase.gameOver) {
      logger.v("$_logTag Phase is gameOver, ignore tapping.");
      return const EngineResponseSkip();
    }

    // TODO: WAR
    if ((GameController().gameInstance.sideToMove == PieceColor.white ||
            GameController().gameInstance.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return const EngineResponseSkip();
    }

    if ((GameController().position.sideToMove == PieceColor.white ||
            GameController().position.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return const EngineResponseSkip();
    }

    // WAR: Fix first tap response slow when piece count changed
    if (GameController().gameInstance.gameMode != GameMode.humanVsHuman &&
        GameController().position.phase == Phase.placing &&
        _isBoardEmpty) {
      //controller.reset();

      if (isAiToMove) {
        logger.i("$_logTag AI is not thinking. AI is to move.");

        return GameController().engineToGo(context, isMoveNow: false);
      }
    }

    if (isAiToMove) {
      logger.i("$_logTag AI's turn, skip tapping.");
      return const EngineResponseSkip();
    }

    // Human to go
    bool ret = false;
    switch (GameController().position.action) {
      case Act.place:
        if (GameController().position._putPiece(sq)) {
          GameController().animationController.reset();
          GameController().animationController.animateTo(1.0);
          if (GameController().position.action == Act.remove) {
            if (GameController()
                .position
                .isStalemateRemoval(GameController().position.sideToMove)) {
              showTip(S.of(context).tipRemove);
            } else {
              showTip(S.of(context).tipMill);
            }
          } else {
            if (GameController().gameInstance.gameMode == GameMode.humanVsAi) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                showTip(S.of(context).continueToMakeMove, snackBar: false);
              } else {
                if (GameController().position.phase == Phase.placing) {
                  showTip(S.of(context).tipPlaced, snackBar: false);
                } else {
                  showTip(S.of(context).tipMove, snackBar: false);
                }
              }
            } else if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              if (DB().ruleSettings.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                // TODO: HumanVsHuman - Change tip
                if (GameController().position.phase == Phase.placing) {
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
          logger.v("$_logTag putPiece: [$sq]");
          break;
        } else {
          logger.v("$_logTag putPiece: skip [$sq]");
          if (!(GameController().position.phase == Phase.moving &&
              GameController().position._board[sq] ==
                  GameController().position.sideToMove)) {
            showTip(S.of(context).tipBanPlace);
          }
        }

        // If cannot move, retry select, do not break
        //[[fallthrough]];
        continue select;
      select:
      case Act.select:
        if (GameController().position.phase == Phase.placing) {
          showTip(S.of(context).tipCannotPlace);
          break;
        }

        final GameResponse selectRet =
            GameController().position._selectPiece(sq);

        switch (selectRet) {
          case GameResponseOK():
            SoundManager().playTone(Sound.select);
            controller.gameInstance._select(squareToIndex[sq]!);
            ret = true;
            logger.v("$_logTag selectPiece: [$sq]");

            final int? pieceOnBoardCount = GameController()
                .position
                .pieceOnBoardCount[controller.gameInstance.sideToMove];
            if (GameController().position.phase == Phase.moving &&
                DB().ruleSettings.mayFly &&
                (pieceOnBoardCount! <= DB().ruleSettings.flyPieceCount &&
                    pieceOnBoardCount >= 3)) {
              logger.v("$_logTag May fly.");
              showTip(S.of(context).tipCanMoveToAnyPoint);
            } else {
              showTip(S.of(context).tipPlace, snackBar: false);
              if (DB().generalSettings.screenReaderSupport) {
                showTip(S.of(context).selected);
              }
            }
            break;
          case IllegalPhase():
            if (GameController().position.phase != Phase.gameOver) {
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
            SoundManager().playTone(Sound.illegal);
            logger.v("$_logTag selectPiece: skip [$sq]");
            break;
        }

        break;

      case Act.remove:
        final GameResponse removeRet =
            GameController().position._removePiece(sq);

        GameController().animationController.reset();
        GameController().animationController.animateTo(1.0);

        switch (removeRet) {
          case GameResponseOK():
            ret = true;
            logger.v("$_logTag removePiece: [$sq]");
            if (GameController().position.pieceToRemoveCount[
                    GameController().position.sideToMove]! >=
                1) {
              showTip(S.of(context).tipContinueMill);
            } else {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsAi) {
                showTip(S.of(context).tipRemoved, snackBar: false);
              } else if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                if ((DB().ruleSettings.piecesCount == 12 &&
                        DB().ruleSettings.boardFullAction !=
                            BoardFullAction.firstPlayerLose &&
                        DB().ruleSettings.boardFullAction !=
                            BoardFullAction.agreeToDraw &&
                        GameController().position.phase == Phase.moving &&
                        GameController()
                                .position
                                .pieceOnBoardCount[PieceColor.white] ==
                            11 &&
                        GameController()
                                .position
                                .pieceOnBoardCount[PieceColor.white] ==
                            11) ||
                    GameController().position.isNeedStalemateRemoval == true) {
                  // TODO: boardFullAction & StalemateAction: Judging condition is not perfect.
                  //  Causes under this condition and can not prompt exactly
                  //  which player's turn to move.
                  showTip(S.of(context).tipMove, snackBar: false);
                } else {
                  final String them = controller
                      .gameInstance.sideToMove.opponent
                      .playerName(context);
                  showTip(S.of(context).tipToMove(them), snackBar: false);
                }
              }
            }
            break;
          case CanNotRemoveSelf():
            logger.i(
                "$_logTag removePiece: Cannot Remove our pieces, skip [$sq]");
            showTip(S.of(context).tipSelectOpponentsPiece);
            break;
          case CanNotRemoveMill():
            logger.i(
              "$_logTag removePiece: Cannot remove piece from Mill, skip [$sq]",
            );
            showTip(S.of(context).tipCannotRemovePieceFromMill);
            break;
          case CanNotRemoveNonadjacent():
            logger.i(
              "$_logTag removePiece: Cannot remove piece nonadjacent, skip [$sq]",
            );
            showTip(S.of(context).tipCanNotRemoveNonadjacent);
            break;
          default:
            logger.v("$_logTag removePiece: skip [$sq]");
            if (GameController().position.phase != Phase.gameOver) {
              showTip(S.of(context).tipBanRemove);
            }
            break;
        }
    }

    if (ret) {
      controller.gameInstance.sideToMove = GameController().position.sideToMove;

      // TODO: Need Others?
      // Increment ply counters. In particular,
      // rule50 will be reset to zero later on
      // in case of a remove.
      ++GameController().position._gamePly;
      ++GameController().position.st.rule50;
      ++GameController().position.st.pliesFromNull;

      if (GameController().position._record != null &&
          GameController().position._record!.move.length > "-(1,2)".length) {
        if (posKeyHistory.isEmpty ||
            posKeyHistory.last != GameController().position.st.key) {
          posKeyHistory.add(GameController().position.st.key);
          if (DB().ruleSettings.threefoldRepetitionRule &&
              GameController().position._hasGameCycle) {
            GameController().position._setGameOver(
                  PieceColor.draw,
                  GameOverReason.drawThreefoldRepetition,
                );
          }
        }
      } else {
        posKeyHistory.clear();
      }

      if (GameController().position._record != null) {
        controller.gameRecorder
            .addAndDeduplicate(GameController().position._record!);
        if (GameController().position._record!.type == MoveType.remove) {
          controller.gameRecorder.lastPositionWithRemove =
              GameController().position.fen;
        }

        // TODO: moveHistoryText is not lightweight.
        if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
          final CatcherOptions options = catcher.getCurrentConfig()!;
          options.customParameters["MoveList"] =
              GameController().gameRecorder.moveHistoryText;
        }
      }

      if (_isGameRunning && GameController().gameInstance.isAiToMove) {
        if (GameController().gameInstance.gameMode == GameMode.humanVsAi) {
          return GameController().engineToGo(context, isMoveNow: false);
        }
      } else {
        return const EngineResponseHumanOK();
      }
    } else {
      SoundManager().playTone(Sound.illegal);
    }

    controller.gameInstance.sideToMove = GameController().position.sideToMove;

    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();

    return const EngineResponseHumanOK();
  }
}
