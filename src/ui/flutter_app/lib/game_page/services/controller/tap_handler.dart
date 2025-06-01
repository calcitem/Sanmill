// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tap_handler.dart

part of '../mill.dart';

class TapHandler {
  TapHandler({
    required this.context,
  });

  //final position = GameController().position;

  static const String _logTag = "[Tap Handler]";

  final BuildContext context;

  final GameController controller = GameController();

  //final gameMode = GameController().gameInstance.gameMode;
  final void Function(String tip, {bool snackBar}) showTip =
      GameController().headerTipNotifier.showTip;

  bool get _isGameRunning =>
      GameController().position.winner == PieceColor.nobody;

  bool get isAiSideToMove => controller.gameInstance.isAiSideToMove;

  bool get _isBoardEmpty =>
      GameController().position.pieceOnBoardCount[PieceColor.white] == 0 &&
      GameController().position.pieceOnBoardCount[PieceColor.black] == 0;

  Future<EngineResponse> setupPosition(int sq) async {
    if (GameController().position.action == Act.place ||
        GameController().position.action == Act.select) {
      GameController().position.putPieceForSetupPosition(sq);
    } else if (GameController().position.action == Act.remove) {
      GameController().position._removePieceForSetupPosition(sq);
    } else {
      logger.e("$_logTag Invalid action: ${GameController().position.action}");
    }

    GameController().setupPositionNotifier.updateIcons();
    GameController().boardSemanticsNotifier.updateSemantics();
    GameController().headerTipNotifier.showTip(ExtMove.sqToNotation(sq),
        snackBar: false); // TODO: snackBar is false?

    return const EngineResponseHumanOK(); // TODO: Right?
  }

  Future<EngineResponse> onBoardTap(int sq) async {
    // Prevent interaction when analysis is in progress
    if (AnalysisMode.isAnalyzing) {
      logger.i("$_logTag Analysis in progress, ignoring tap.");
      return const EngineResponseSkip();
    }

    // Clear any existing analysis markers when player makes a move
    AnalysisMode.disable();

    if (!GameController().isControllerReady) {
      logger.i("$_logTag Not ready, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
      if (GameController().isLanOpponentTurn) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).notYourTurn);
        return const EngineResponseSkip();
      }
      if (GameController().networkService == null ||
          !GameController().networkService!.isConnected) {
        logger.w("$_logTag No active LAN connection");
        showTip(S.of(context).noLanConnection, snackBar: true);
        return const EngineResponseSkip();
      }
    }

    GameController().loadedGameFilenamePrefix = null;

    if (GameController().gameInstance.gameMode == GameMode.setupPosition) {
      logger.t("$_logTag Setup position.");
      await setupPosition(sq);
      return const EngineResponseSkip();
    }

    if (GameController().gameInstance.gameMode == GameMode.testViaLAN) {
      logger.t("$_logTag Engine type is no human, ignore tapping.");
      return const EngineResponseSkip();
    }

    if (GameController().position.phase == Phase.gameOver) {
      logger.t("$_logTag Phase is gameOver, ignore tapping.");
      return const EngineResponseSkip();
    }

    // Handle LAN-specific logic
    if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
      if (GameController().isLanOpponentTurn) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).notYourTurn);
        return const EngineResponseSkip();
      }
      if (GameController().networkService == null ||
          !GameController().networkService!.isConnected) {
        logger.w("$_logTag No active LAN connection");
        showTip(S.of(context).noLanConnection, snackBar: true);
        return const EngineResponseSkip();
      }
    }

    // TODO: WAR
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

      if (isAiSideToMove) {
        logger.i("$_logTag AI is not thinking. AI is to move.");

        return GameController().engineToGo(context, isMoveNow: false);
      }
    }

    if (isAiSideToMove &&
        GameController().gameInstance.gameMode != GameMode.humanVsLAN) {
      logger.i("$_logTag AI's turn, skip tapping.");
      return const EngineResponseSkip();
    }

    // Human to go
    bool ret = false;
    switch (GameController().position.action) {
      case Act.place:
        if (GameController().position._putPiece(sq)) {
          // Stop timer when player makes a valid move
          PlayerTimer().stop();

          if (GameController().position.action == Act.remove) {
            if (GameController()
                .position
                .isStalemateRemoval(GameController().position.sideToMove)) {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(
                    "${S.of(context).tipToMove(side)} ${S.of(context).tipRemove}");
              } else {
                showTip(S.of(context).tipRemove);
              }
            } else {
              if ((DB().ruleSettings.boardFullAction ==
                          BoardFullAction.firstAndSecondPlayerRemovePiece ||
                      DB().ruleSettings.boardFullAction ==
                          BoardFullAction.secondAndFirstPlayerRemovePiece ||
                      DB().ruleSettings.boardFullAction ==
                          BoardFullAction.sideToMoveRemovePiece) &&
                  GameController()
                          .position
                          .pieceOnBoardCount[PieceColor.white]! >
                      10 &&
                  GameController()
                          .position
                          .pieceOnBoardCount[PieceColor.black]! >
                      10) {
                // TODO: Change conditions
                if (GameController().gameInstance.gameMode ==
                    GameMode.humanVsHuman) {
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  showTip(
                      "${S.of(context).tipToMove(side)} ${S.of(context).tipRemove}");
                } else {
                  showTip(S.of(context).tipRemove);
                }
              } else {
                if (GameController().gameInstance.gameMode ==
                    GameMode.humanVsHuman) {
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  showTip(
                      "${S.of(context).tipToMove(side)} ${S.of(context).tipMill}");
                } else {
                  showTip(S.of(context).tipMill);
                }
              }
            }
          } else {
            if (GameController().gameInstance.gameMode == GameMode.humanVsAi) {
              if (DB().ruleSettings.millFormationActionInPlacingPhase ==
                  MillFormationActionInPlacingPhase
                      .removeOpponentsPieceFromHandThenYourTurn) {
                showTip(S.of(context).continueToMakeMove, snackBar: false);
              } else {
                if (GameController().position.phase == Phase.placing) {
                  if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsHuman) {
                    final String side =
                        controller.position.sideToMove.playerName(context);
                    if (DB().ruleSettings.mayMoveInPlacingPhase) {
                      showTip(S.of(context).tipToMove(side));
                    } else {
                      showTip(
                          "${S.of(context).tipPlaced} ${S.of(context).tipToMove(side)}");
                    }
                  } else {
                    final String side =
                        controller.position.sideToMove.playerName(context);
                    if (DB().ruleSettings.mayMoveInPlacingPhase) {
                      showTip(S.of(context).tipToMove(side));
                    } else {
                      showTip(S.of(context).tipPlaced);
                    }
                  }
                } else {
                  if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsHuman) {
                    final String side =
                        controller.position.sideToMove.playerName(context);
                    showTip(
                        "${S.of(context).tipToMove(side)} ${S.of(context).tipMove}");
                  } else {
                    showTip(S.of(context).tipMove);
                  }
                }
              }
            } else if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              if (DB().ruleSettings.millFormationActionInPlacingPhase ==
                      MillFormationActionInPlacingPhase
                          .removeOpponentsPieceFromHandThenYourTurn ||
                  DB().ruleSettings.millFormationActionInPlacingPhase ==
                      MillFormationActionInPlacingPhase
                          .removeOpponentsPieceFromHandThenOpponentsTurn) {
                if (GameController().position.phase == Phase.placing) {
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  if (DB().ruleSettings.mayMoveInPlacingPhase) {
                    showTip(S.of(context).tipToMove(side));
                  } else {
                    showTip(
                        "${S.of(context).tipPlaced} ${S.of(context).tipToMove(side)}");
                  }
                } else {
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  showTip(S.of(context).tipToMove(side), snackBar: false);
                }
              } else {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(S.of(context).tipToMove(side), snackBar: false);
              }
            }
          }
          ret = true;
          logger.i("$_logTag putPiece: [$sq]");
          // Timer start logic moved to the end of the successful move block (if ret == true)
          break;
        } else {
          logger.i("$_logTag putPiece: skip [$sq]");
          if (!(GameController().position.phase == Phase.moving &&
              GameController().position._board[sq] ==
                  GameController().position.sideToMove)) {
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipBanPlace} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipBanPlace);
            }
          }
        }

        // If cannot move, retry select, do not break
        //[[fallthrough]];
        continue select;
      select:
      case Act.select:
        if (GameController().position.phase == Phase.placing) {
          if (GameController().gameInstance.gameMode == GameMode.humanVsHuman) {
            final String side =
                controller.position.sideToMove.playerName(context);
            showTip(
                "${S.of(context).tipCannotPlace} ${S.of(context).tipToMove(side)}");
          } else {
            showTip(S.of(context).tipCannotPlace);
          }
          break;
        }

        final GameResponse selectRet =
            GameController().position._selectPiece(sq);

        switch (selectRet) {
          case GameResponseOK():
            SoundManager().playTone(Sound.select);
            controller.gameInstance._select(squareToIndex[sq]!);
            ret = true;
            logger.i("$_logTag selectPiece: [$sq]");

            final int? pieceOnBoardCount = GameController()
                .position
                .pieceOnBoardCount[controller.position.sideToMove];
            if (GameController().position.phase == Phase.moving &&
                DB().ruleSettings.mayFly &&
                (pieceOnBoardCount! <= DB().ruleSettings.flyPieceCount &&
                    pieceOnBoardCount >= 3)) {
              logger.i("$_logTag May fly.");
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(
                    "${S.of(context).tipCanMoveToAnyPoint} ${S.of(context).tipToMove(side)}");
              } else {
                showTip(S.of(context).tipCanMoveToAnyPoint);
              }
            } else {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);

                if (DB().ruleSettings.mayMoveInPlacingPhase) {
                  showTip(S.of(context).tipToMove(side));
                } else {
                  showTip(
                      "${S.of(context).tipToMove(side)} ${S.of(context).tipPlace}");
                }
              } else {
                final String side =
                    controller.position.sideToMove.playerName(context);
                if (DB().ruleSettings.mayMoveInPlacingPhase) {
                  showTip(S.of(context).tipToMove(side));
                } else {
                  showTip(S.of(context).tipPlace);
                }
              }
              if (DB().generalSettings.screenReaderSupport) {
                showTip(S.of(context).selected);
              }
            }
            break;
          case IllegalPhase():
            if (GameController().position.phase != Phase.gameOver) {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(
                    "${S.of(context).tipCannotMove} ${S.of(context).tipToMove(side)}");
              } else {
                showTip(S.of(context).tipCannotMove);
              }
            }
            break;
          case NoPieceSelected():
            break;
          // TODO: no CanOnlyMoveToAdjacentEmptyPoints events
          case CanOnlyMoveToAdjacentEmptyPoints():
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipCanMoveOnePoint} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipCanMoveOnePoint);
            }
            break;
          case SelectOurPieceToMove():
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipSelectPieceToMove} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipSelectPieceToMove);
            }
            break;
          case IllegalAction():
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipSelectWrong} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipSelectWrong);
            }
            break;
          default:
            SoundManager().playTone(Sound.illegal);
            logger.i("$_logTag selectPiece: skip [$sq]");
            break;
        }

        break;

      case Act.remove:
        final GameResponse removeRet =
            GameController().position._removePiece(sq);

        switch (removeRet) {
          case GameResponseOK():
            // Stop timer when player successfully removes a piece
            PlayerTimer().stop();

            ret = true;
            logger.i("$_logTag removePiece: [$sq]");

            //SoundManager().playTone(Sound.remove);

            if (GameController().position.pieceToRemoveCount[
                    GameController().position.sideToMove]! >=
                1) {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(
                    "${S.of(context).tipToMove(side)} ${S.of(context).tipContinueMill}");
              } else {
                showTip(S.of(context).tipContinueMill);
              }
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
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  showTip(S.of(context).tipToMove(side), snackBar: false);
                } else {
                  final String side =
                      controller.position.sideToMove.playerName(context);
                  showTip(S.of(context).tipToMove(side), snackBar: false);
                }
              }
            }
            break;
          case CanNotRemoveSelf():
            logger.i(
                "$_logTag removePiece: Cannot Remove our pieces, skip [$sq]");
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipSelectOpponentsPiece} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipSelectOpponentsPiece);
            }
            break;
          case ShouldRemoveSelf():
            logger
                .i("$_logTag removePiece: Should Remove our piece, skip [$sq]");
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipSelectOwnPiece} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipSelectOwnPiece);
            }
            break;
          case CanNotRemoveMill():
            logger.i(
              "$_logTag removePiece: Cannot remove piece from Mill, skip [$sq]",
            );
            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipCannotRemovePieceFromMill} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipCannotRemovePieceFromMill);
            }
            break;
          case CanNotRemoveNonadjacent():
            logger.i(
              "$_logTag removePiece: Cannot remove piece nonadjacent, skip [$sq]",
            );

            if (GameController().gameInstance.gameMode ==
                GameMode.humanVsHuman) {
              final String side =
                  controller.position.sideToMove.playerName(context);
              showTip(
                  "${S.of(context).tipCanNotRemoveNonadjacent} ${S.of(context).tipToMove(side)}");
            } else {
              showTip(S.of(context).tipCanNotRemoveNonadjacent);
            }
            break;
          default:
            logger.i("$_logTag removePiece: skip [$sq]");
            if (GameController().position.phase != Phase.gameOver) {
              if (GameController().gameInstance.gameMode ==
                  GameMode.humanVsHuman) {
                final String side =
                    controller.position.sideToMove.playerName(context);
                showTip(
                    "${S.of(context).tipBanRemove} ${S.of(context).tipToMove(side)}");
              } else {
                showTip(S.of(context).tipBanRemove);
              }
            }
            break;
        }
    }

    if (ret) {
      // TODO: Need Others?
      // Increment ply counters. In particular,
      // rule50 will be reset to zero later on
      // in case of a remove.
      ++GameController().position._gamePly;
      ++GameController().position.st.rule50;
      ++GameController().position.st.pliesFromNull;

      // Update position history
      // Check move type instead of string length for position key history
      if (GameController().position._record != null &&
          GameController().position._record!.type == MoveType.move) {
        if (posKeyHistory.isEmpty ||
            posKeyHistory.last != GameController().position.st.key) {
          posKeyHistory.add(GameController().position.st.key);
          if (DB().ruleSettings.threefoldRepetitionRule &&
              GameController().position._hasGameCycle) {
            GameController().position.setGameOver(
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
            .appendMoveIfDifferent(GameController().position._record!);
        if (GameController().position._record!.type == MoveType.remove) {
          controller.gameRecorder.lastPositionWithRemove =
              GameController().position.fen;
        }

        // Send move to LAN opponent if applicable
        if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
          final String moveNotation = GameController().position._record!.move;
          GameController().sendLanMove(moveNotation);
        }

        // TODO: moveHistoryText is not lightweight.
        if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
          final Catcher2Options options = catcher.getCurrentConfig()!;
          options.customParameters["MoveList"] =
              GameController().gameRecorder.moveHistoryText;
        }
      }

      // Start timer for the next player if the game is running and it's a human's turn.
      // The `sideToMove` has already been updated by the move functions (_putPiece, _removePiece, _movePiece).
      if (_isGameRunning && !GameController().gameInstance.isAiSideToMove) {
        logger.d(
            "$_logTag Starting timer for human opponent after successful move.");
        PlayerTimer().start();
      }

      // Check if the next player is AI and needs to start thinking
      if (_isGameRunning && GameController().gameInstance.isAiSideToMove) {
        return GameController().engineToGo(context, isMoveNow: false);
      } else {
        return const EngineResponseHumanOK();
      }
    } else {
      SoundManager().playTone(Sound.illegal);
    }

    GameController().headerIconsNotifier.showIcons();
    GameController().boardSemanticsNotifier.updateSemantics();

    return const EngineResponseHumanOK();
  }
}
