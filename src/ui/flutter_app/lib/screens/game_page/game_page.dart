// ignore_for_file: use_build_context_synchronously, avoid_positional_boolean_parameters

/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/engine/native_engine.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/dialog.dart';
import 'package:sanmill/shared/game_toolbar/game_toolbar.dart';
import 'package:sanmill/shared/number_picker.dart';
import 'package:sanmill/shared/painters/painters.dart';
import 'package:sanmill/shared/snackbar.dart';
import 'package:sanmill/shared/theme/app_theme.dart';
import 'package:stack_trace/stack_trace.dart';

part 'package:sanmill/screens/game_page/board.dart';

class GamePage extends StatefulWidget {
  final EngineType engineType;

  // TODO: [Leptopoda] use gameInstance.engineType
  const GamePage(this.engineType, {Key? key}) : super(key: key);

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with RouteAware, SingleTickerProviderStateMixin {
  final Engine _engine = NativeEngine();

  double screenPaddingH = AppTheme.boardScreenPaddingH;
  final double boardMargin = AppTheme.boardMargin;

  late String _tip;
  bool isReady = false;
  bool isGoingToHistory = false;
  late Timer timer;
  late AnimationController _animationController;
  late Animation<double> animation;
  bool disposed = false;
  late bool ltr;
  late double boardWidth;

  static const String _tag = "[game_page]";

  Future<void> _setReadyState() async {
    debugPrint("$_tag Check if need to set Ready state...");
    if (!isReady && mounted) {
      debugPrint("$_tag Set Ready State...");
      setState(() {});
      isReady = true;
      timer.cancel();

      if (Localizations.localeOf(context).languageCode == "zh" &&
          !LocalDatabaseService.preferences.isPrivacyPolicyAccepted) {
        onShowPrivacyDialog();
      }
    }
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            (LocalDatabaseService.display.animationDuration * 1000).toInt(),
      ),
    );
    _animationController.addListener(() {});

    animation = Tween(
      begin: 1.27, // sqrt(1.618) = 1.272
      end: 1.0,
    ).animate(_animationController)
      ..addListener(() => setState(() {}));

    _animationController.addStatusListener((state) {
      if (state == AnimationStatus.completed ||
          state == AnimationStatus.dismissed) {
        if (disposed) {
          return;
        }
        _animationController.forward();
      }
    });

    if (!disposed) {
      _animationController.forward();
    }
  }

  void showTip(String tip) {
    if (!mounted) return;

    debugPrint("[tip] $tip");
    if (LocalDatabaseService.preferences.screenReaderSupport) {
      //showSnackBar(context, tip);
    }

    setState(() => _tip = tip);
  }

  void showTips() {
    if (!mounted) return;

    final winner = gameInstance.position.winner;

    switch (winner) {
      case PieceColor.white:
        return showTip(S.of(context).whiteWin);
      case PieceColor.black:
        return showTip(S.of(context).blackWin);
      case PieceColor.draw:
        return showTip(S.of(context).isDraw);
      case PieceColor.nobody:
        switch (gameInstance.position.phase) {
          case Phase.placing:
            return showTip(S.of(context).tipPlace);
          case Phase.moving:
            return showTip(S.of(context).tipMove);
          default:
        }
    }

    if (!LocalDatabaseService.preferences.isAutoRestart) {
      showGameResult(winner);
    }
  }

  Future<dynamic> onBoardTap(int index) async {
    if (!isReady) {
      debugPrint("[tap] Not ready, ignore tapping.");
      return false;
    }

    disposed = false;
    _animationController.duration = Duration(
      milliseconds:
          (LocalDatabaseService.display.animationDuration * 1000).toInt(),
    );
    _animationController.reset();

    if (gameInstance.engineType == EngineType.aiVsAi ||
        gameInstance.engineType == EngineType.testViaLAN) {
      debugPrint("$_tag Engine type is no human, ignore tapping.");
      return false;
    }

    final position = gameInstance.position;

    final int? sq = indexToSquare[index];

    if (sq == null) {
      debugPrint("$_tag sq is null, skip tapping.");
      return;
    }

    // If nobody has placed, start to go.
    if (position.phase == Phase.placing &&
        position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      gameInstance.newGame();

      if (gameInstance.isAiToMove) {
        if (gameInstance.aiIsSearching) {
          debugPrint("$_tag AI is thinking, skip tapping.");
          return false;
        } else {
          debugPrint("[tap] AI is not thinking. AI is to move.");
          await engineToGo(false);
          return false;
        }
      }
    }

    if (gameInstance.isAiToMove || gameInstance.aiIsSearching) {
      debugPrint("[tap] AI's turn, skip tapping.");
      return false;
    }

    if (position.phase == Phase.ready) {
      gameInstance.start();
    }

    // Human to go

    bool ret = false;
    await Chain.capture(() async {
      switch (position.action) {
        case Act.place:
          if (await position.putPiece(sq)) {
            if (position.action == Act.remove) {
              //Audios.playTone(Audios.mill);
              if (mounted) {
                showTip(S.of(context).tipMill);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipMill);
                }
              }
            } else {
              //Audios.playTone(Audios.place);
              if (gameInstance.engineType == EngineType.humanVsAi && mounted) {
                if (rule.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  showTip(S.of(context).continueToMakeMove);
                } else {
                  showTip(S.of(context).tipPlaced);
                }
              } else if (mounted) {
                if (rule.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  showTip(
                    S.of(context).tipPlaced,
                  ); // TODO: HumanVsHuman - Change tip
                } else {
                  final side = gameInstance.sideToMove == PieceColor.white
                      ? S.of(context).black
                      : S.of(context).white;
                  showTip(S.of(context).tipToMove(side));
                }
              }
            }
            ret = true;
            debugPrint("[tap] putPiece: [$sq]");
            break;
          } else {
            debugPrint("[tap] putPiece: skip [$sq]");
            if (mounted) {
              showTip(S.of(context).tipBanPlace);
              if (LocalDatabaseService.preferences.screenReaderSupport) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).tipBanPlace);
              }
            }
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.phase == Phase.placing) {
            if (mounted) {
              showTip(S.of(context).tipCannotPlace);
              if (LocalDatabaseService.preferences.screenReaderSupport) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).tipCannotPlace);
              }
            }
            break;
          }
          final int selectRet = position.selectPiece(sq);
          switch (selectRet) {
            case 0:
              await Audios.playTone(Sound.select);
              gameInstance.select(index);
              ret = true;
              debugPrint("[tap] selectPiece: [$sq]");

              final us = gameInstance.sideToMove;
              if (position.phase == Phase.moving &&
                  rule.mayFly &&
                  (gameInstance.position.pieceOnBoardCount[us] ==
                          LocalDatabaseService.rules.flyPieceCount ||
                      gameInstance.position.pieceOnBoardCount[us] == 3)) {
                debugPrint("[tap] May fly.");
                if (mounted) {
                  showTip(S.of(context).tipCanMoveToAnyPoint);
                  if (LocalDatabaseService.preferences.screenReaderSupport) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    showSnackBar(context, S.of(context).tipCanMoveToAnyPoint);
                  }
                }
              } else if (mounted) {
                showTip(S.of(context).tipPlace);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).selected);
                }
              }

              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipCannotMove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipCannotMove);
                }
              }
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipCanMoveOnePoint);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipCanMoveOnePoint);
                }
              }
              break;
            case -4:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectPieceToMove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipSelectPieceToMove);
                }
              }
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (mounted) {
                showTip(S.of(context).tipSelectWrong);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(context, S.of(context).tipSelectWrong);
                }
              }
              break;
          }

          break;

        case Act.remove:
          final int removeRet = await position.removePiece(sq);

          switch (removeRet) {
            case 0:
              //Audios.playTone(Audios.remove);
              ret = true;
              debugPrint("[tap] removePiece: [$sq]");
              if (gameInstance.position.pieceToRemoveCount >= 1) {
                if (mounted) {
                  showTip(S.of(context).tipContinueMill);
                  if (LocalDatabaseService.preferences.screenReaderSupport) {
                    showSnackBar(context, S.of(context).tipContinueMill);
                  }
                }
              } else {
                if (gameInstance.engineType == EngineType.humanVsAi) {
                  if (mounted) {
                    showTip(S.of(context).tipRemoved);
                  }
                } else {
                  if (mounted) {
                    final them = gameInstance.sideToMove == PieceColor.white
                        ? S.of(context).black
                        : S.of(context).white;
                    if (mounted) {
                      showTip(S.of(context).tipToMove(them));
                    }
                  }
                }
              }
              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              if (mounted) {
                showTip(S.of(context).tipSelectOpponentsPiece);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipSelectOpponentsPiece);
                }
              }
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              if (mounted) {
                showTip(S.of(context).tipCannotRemovePieceFromMill);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  showSnackBar(
                    context,
                    S.of(context).tipCannotRemovePieceFromMill,
                  );
                }
              }
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] removePiece: skip [$sq]");
              if (mounted && position.phase != Phase.gameOver) {
                showTip(S.of(context).tipBanRemove);
                if (LocalDatabaseService.preferences.screenReaderSupport) {
                  showSnackBar(context, S.of(context).tipBanRemove);
                }
              }
              break;
          }

          break;

        default:
          break;
      }

      if (ret) {
        gameInstance.sideToMove = position.sideToMove;
        gameInstance.moveHistory.add(position.record);

        // TODO: Need Others?
        // Increment ply counters. In particular,
        // rule50 will be reset to zero later on
        // in case of a remove.
        ++position.gamePly;
        ++position.st.rule50;
        ++position.st.pliesFromNull;

        if (position.record.length > "-(1,2)".length) {
          if (posKeyHistory.isEmpty ||
              (posKeyHistory.isNotEmpty &&
                  position.st.key != posKeyHistory[posKeyHistory.length - 1])) {
            posKeyHistory.add(position.st.key);
            if (rule.threefoldRepetitionRule && position.hasGameCycle()) {
              position.setGameOver(
                PieceColor.draw,
                GameOverReason.drawReasonThreefoldRepetition,
              );
            }
          }
        } else {
          posKeyHistory.clear();
        }

        //position.move = m;

        final Move m = Move(position.record);
        position.recorder.prune();
        position.recorder.moveIn(m, position);

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          engineToGo(false);
        } else {
          showTips();
        }
      }

      gameInstance.sideToMove = position.sideToMove;

      setState(() {});
    }); // Chain.capture

    return ret;
  }

  Future<void> engineToGo(bool isMoveNow) async {
    bool _isMoveNow = isMoveNow;

    if (!mounted) {
      debugPrint("[engineToGo] !mounted, skip engineToGo.");
      return;
    }

    // TODO
    debugPrint("[engineToGo] engine type is ${widget.engineType}");

    if (_isMoveNow) {
      if (!gameInstance.isAiToMove) {
        debugPrint("[engineToGo] Human to Move. Cannot get search result now.");
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).notAIsTurn);
        return;
      }
      if (!gameInstance.position.recorder.isClean()) {
        debugPrint(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).aiIsNotThinking);
        return;
      }
    }

    while ((LocalDatabaseService.preferences.isAutoRestart == true ||
            gameInstance.position.winner == PieceColor.nobody) &&
        gameInstance.isAiToMove &&
        mounted) {
      if (widget.engineType == EngineType.aiVsAi) {
        final String score =
            "${gameInstance.position.score[PieceColor.white]} : ${gameInstance.position.score[PieceColor.black]} : ${gameInstance.position.score[PieceColor.draw]}";

        showTip(score);
      } else {
        if (mounted) {
          showTip(S.of(context).thinking);

          final Move? m = gameInstance.position.recorder.lastMove;

          if (LocalDatabaseService.preferences.screenReaderSupport &&
              gameInstance.position.action != Act.remove &&
              m?.notation != null) {
            showSnackBar(context, "${S.of(context).human}: ${m!.notation!}");
          }
        }
      }

      late EngineResponse response;

      if (!_isMoveNow) {
        debugPrint("[engineToGo] Searching...");
        response = await _engine.search(gameInstance.position);
      } else {
        debugPrint("[engineToGo] Get search result now...");
        response = await _engine.search(null);
        _isMoveNow = false;
      }

      debugPrint("[engineToGo] Engine response type: ${response.type}");

      switch (response.type) {
        case 'move':
          final Move mv = response.value as Move;
          final Move move = Move(mv.move);

          _animationController.duration = Duration(
            milliseconds:
                (LocalDatabaseService.display.animationDuration * 1000).toInt(),
          );

          if (!disposed) {
            _animationController.reset();
          } else {
            debugPrint(
              "[engineToGo] Disposed, so do not reset animationController.",
            );
          }

          await gameInstance.doMove(move.move);
          showTips();
          if (LocalDatabaseService.preferences.screenReaderSupport &&
              move.notation != null) {
            showSnackBar(context, "${S.of(context).ai}: ${move.notation!}");
          }
          break;
        case 'timeout':
          if (mounted) {
            showTip(S.of(context).timeout);
            if (LocalDatabaseService.preferences.screenReaderSupport) {
              showSnackBar(context, S.of(context).timeout);
            }
          }
          return;
        default:
          showTip(S.of(context).error(response.type));
      }

      if (LocalDatabaseService.preferences.isAutoRestart == true &&
          gameInstance.position.winner != PieceColor.nobody) {
        gameInstance.newGame();
      }
    }
  }

  Future<void> onStartNewGameButtonPressed() async {
    Navigator.pop(context);

    if (gameInstance.isAiToMove) {
      // TODO: Move now
      //debugPrint("$tag New game, AI to move, move now.");
      //await engineToGo(true);
    }

    gameInstance.newGame();

    if (mounted) {
      showTip(S.of(context).gameStarted);
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).gameStarted);
      }
    }

    if (gameInstance.isAiToMove) {
      debugPrint("$_tag New game, AI to move.");
      engineToGo(false);
    }
  }

  Future<void> onImportGameButtonPressed() async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data == null || data.text == null) {
      return;
    }

    final String text = data.text!;

    debugPrint("Clipboard text:");
    debugPrint(text);

    await onTakeBackAllButtonPressed(false);
    gameInstance.position.recorder.clear();
    final invalidMoveStr = gameInstance.position.recorder.import(text);

    if (invalidMoveStr != "") {
      showTip(S.of(context).cannotImport(invalidMoveStr));
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).cannotImport(invalidMoveStr));
      }
      return;
    }

    await onStepForwardAllButtonPressed(false);

    showTip(S.of(context).gameImported);
    if (LocalDatabaseService.preferences.screenReaderSupport) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, S.of(context).gameImported);
    }
  }

  Future<void> onExportGameButtonPressed() async {
    Navigator.pop(context);

    final moveHistoryText = gameInstance.position.moveHistoryText;

    Clipboard.setData(ClipboardData(text: moveHistoryText)).then((_) {
      showSnackBar(context, S.of(context).moveHistoryCopied);
    });
  }

  Future<void> onAutoReplayButtonPressed() async {
    Navigator.pop(context);

    await onTakeBackAllButtonPressed(false);
    await onStepForwardAllButtonPressed(false);
  }

  void onGameButtonPressed() {
    showModalBottomSheet(
      //showDialog(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Semantics(
        label: S.of(context).game,
        child: SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            SimpleDialogOption(
              onPressed: onStartNewGameButtonPressed,
              child: Text(
                S.of(context).newGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: onImportGameButtonPressed,
              child: Text(
                S.of(context).importGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: onExportGameButtonPressed,
              child: Text(
                S.of(context).exportGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            if (LocalDatabaseService.preferences.screenReaderSupport)
              SimpleDialogOption(
                child: Text(
                  S.of(context).close,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }

  void onOptionButtonPressed() => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const GameSettingsPage()),
      );

  void onMoveButtonPressed() {
    final List<Widget> _historyNavigation = [
      SimpleDialogOption(
        onPressed: onTakeBackButtonPressed,
        child: Text(
          S.of(context).takeBack,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const CustomSpacer(),
      SimpleDialogOption(
        onPressed: onStepForwardButtonPressed,
        child: Text(
          S.of(context).stepForward,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const CustomSpacer(),
      SimpleDialogOption(
        onPressed: onTakeBackAllButtonPressed,
        child: Text(
          S.of(context).takeBackAll,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const CustomSpacer(),
      SimpleDialogOption(
        onPressed: onStepForwardAllButtonPressed,
        child: Text(
          S.of(context).stepForwardAll,
          style: AppTheme.simpleDialogOptionTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
      const CustomSpacer(),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Semantics(
        label: S.of(context).move_number(0),
        child: SimpleDialog(
          backgroundColor: Colors.transparent,
          children: <Widget>[
            if (!LocalDatabaseService.display.isHistoryNavigationToolbarShown)
              ..._historyNavigation,
            SimpleDialogOption(
              onPressed: onMoveListButtonPressed,
              child: Text(
                S.of(context).showMoveList,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: onMoveNowButtonPressed,
              child: Text(
                S.of(context).moveNow,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            if (LocalDatabaseService.preferences.screenReaderSupport)
              SimpleDialogOption(
                child: Text(
                  S.of(context).close,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> onGotoHistoryButtonsPressed(
    HistoryMove move, {
    bool pop = true,
    int? number,
  }) async {
    if (pop == true) {
      Navigator.pop(context);
    }

    if (mounted) {
      showTip(S.of(context).waiting);
    }

    if (isGoingToHistory) {
      debugPrint(
        "[TakeBack] Is going to history, ignore Take Back button press.",
      );
      return;
    }

    isGoingToHistory = true;

    final errMove = await gameInstance.position.gotoHistory(move, number);

    switch (errMove) {
      case "":
        break;
      case "null":
      case "out-of-range":
      case "equal":
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).atEnd);
        break;
      default:
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, S.of(context).movesAndRulesNotMatch);
        break;
    }

    isGoingToHistory = false;

    if (mounted) {
      final pos = gameInstance.position;

      late final String text;
      final lastEffectiveMove = pos.recorder.lastEffectiveMove;
      if (lastEffectiveMove?.notation != null) {
        text = S.of(context).lastMove(lastEffectiveMove!.notation!);
      } else {
        text = S.of(context).atEnd;
      }

      showTip(text);

      if (LocalDatabaseService.preferences.screenReaderSupport) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnackBar(context, text);
      }
    }
  }

  Future<void> onTakeBackButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backOne,
        pop: pop,
      );

  Future<void> onStepForwardButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.forward,
        pop: pop,
      );

  Future<void> onTakeBackAllButtonPressed([bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backAll,
        pop: pop,
      );

  Future<void> onStepForwardAllButtonPressed([bool pop = true]) async {
    onGotoHistoryButtonsPressed(
      HistoryMove.forwardAll,
      pop: pop,
    );
  }

  Future<void> onTakeBackNButtonPressed(int n, [bool pop = true]) async =>
      onGotoHistoryButtonsPressed(
        HistoryMove.backN,
        number: n,
        pop: pop,
      );

  void onMoveListButtonPressed() {
    final moveHistoryText = gameInstance.position.moveHistoryText;
    final end = gameInstance.moveHistory.length - 1;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.moveHistoryDialogBackgroundColor,
          title: Text(
            S.of(context).moveList,
            style: AppTheme.moveHistoryTextStyle,
          ),
          content: SingleChildScrollView(
            child: Text(
              moveHistoryText,
              style: AppTheme.moveHistoryTextStyle,
              textDirection: TextDirection.ltr,
            ),
          ),
          actions: <Widget>[
            if (end > 0)
              TextButton(
                child: Text(
                  S.of(context).rollback,
                  style: AppTheme.moveHistoryTextStyle,
                ),
                onPressed: () async {
                  final selectValue = await showDialog<int?>(
                    context: context,
                    builder: (context) => NumberPicker(end: end),
                  );

                  if (selectValue != null) {
                    onTakeBackNButtonPressed(selectValue);
                  }
                },
              ),
            TextButton(
              child: Text(
                S.of(context).copy,
                style: AppTheme.moveHistoryTextStyle,
              ),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: moveHistoryText))
                      .then((_) {
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).moveHistoryCopied);
              }),
            ),
            TextButton(
              child: Text(
                S.of(context).cancel,
                style: AppTheme.moveHistoryTextStyle,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> onMoveNowButtonPressed() async {
    Navigator.pop(context);
    await engineToGo(true);
  }

  void onInfoButtonPressed() {
    final analyzeText = infoText;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.infoDialogBackgroundColor,
          content: SingleChildScrollView(
            child: Text(analyzeText, style: AppTheme.moveHistoryTextStyle),
          ),
          actions: <Widget>[
            TextButton(
              child:
                  Text(S.of(context).ok, style: AppTheme.moveHistoryTextStyle),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> setPrivacyPolicyAccepted(bool value) async {
    LocalDatabaseService.preferences = LocalDatabaseService.preferences
        .copyWith(isPrivacyPolicyAccepted: value);

    debugPrint("[config] isPrivacyPolicyAccepted: $value");
  }

  Future<void> onShowPrivacyDialog() async {
    showPrivacyDialog(context, setPrivacyPolicyAccepted);
  }

  String getGameOverReasonString(GameOverReason? reason, String? winner) {
    final String loserStr =
        winner == PieceColor.white ? S.of(context).black : S.of(context).white;

    final Map<GameOverReason, String> reasonMap = {
      GameOverReason.loseReasonlessThanThree:
          S.of(context).loseReasonlessThanThree(loserStr),
      GameOverReason.loseReasonResign: S.of(context).loseReasonResign(loserStr),
      GameOverReason.loseReasonNoWay: S.of(context).loseReasonNoWay(loserStr),
      GameOverReason.loseReasonBoardIsFull:
          S.of(context).loseReasonBoardIsFull(loserStr),
      GameOverReason.loseReasonTimeOver:
          S.of(context).loseReasonTimeOver(loserStr),
      GameOverReason.drawReasonRule50: S.of(context).drawReasonRule50,
      GameOverReason.drawReasonEndgameRule50:
          S.of(context).drawReasonEndgameRule50,
      GameOverReason.drawReasonBoardIsFull: S.of(context).drawReasonBoardIsFull,
      GameOverReason.drawReasonThreefoldRepetition:
          S.of(context).drawReasonThreefoldRepetition,
    };

    debugPrint(
      "$_tag Game over reason: ${gameInstance.position.gameOverReason}",
    );

    String? loseReasonStr = reasonMap[gameInstance.position.gameOverReason];

    if (loseReasonStr == null) {
      loseReasonStr = S.of(context).gameOverUnknownReason;
      debugPrint("$_tag Game over reason string: $loseReasonStr");
      if (EnvironmentConfig.devMode) {
        assert(false);
      }
    }

    return loseReasonStr;
  }

  GameResult getGameResult(String winner) {
    if (isAi[PieceColor.white]! && isAi[PieceColor.black]!) {
      return GameResult.none;
    }

    if (winner == PieceColor.white) {
      if (isAi[PieceColor.white]!) {
        return GameResult.lose;
      } else {
        return GameResult.win;
      }
    }

    if (winner == PieceColor.black) {
      if (isAi[PieceColor.black]!) {
        return GameResult.lose;
      } else {
        return GameResult.win;
      }
    }

    if (winner == PieceColor.draw) {
      return GameResult.draw;
    }

    return GameResult.none;
  }

// TODO: [Leptopoda] deduplicate the code
  void showGameResult(String winner) {
    final GameResult result = getGameResult(winner);
    gameInstance.position.result = result;

    final Map<GameResult, String> retMap = {
      GameResult.win: gameInstance.engineType == EngineType.humanVsAi
          ? S.of(context).youWin
          : S.of(context).gameOver,
      GameResult.lose: S.of(context).gameOver,
      GameResult.draw: S.of(context).isDraw
    };

    final dialogTitle = retMap[result];

    if (dialogTitle == null) return;

    final bool isTopLevel =
        LocalDatabaseService.preferences.skillLevel == 30; // TODO: 30

    if (result == GameResult.win &&
        !isTopLevel &&
        gameInstance.engineType == EngineType.humanVsAi) {
      final contentStr = StringBuffer(
        getGameOverReasonString(
          gameInstance.position.gameOverReason,
          gameInstance.position.winner,
        ),
      );

      if (!isTopLevel) {
        contentStr.writeln();
        contentStr.writeln();
        contentStr.writeln(
          S.of(context).challengeHarderLevel(
                LocalDatabaseService.preferences.skillLevel + 1,
              ),
        );
      }

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              dialogTitle,
              style: AppTheme.dialogTitleTextStyle,
            ),
            content: Text(contentStr.toString()),
            actions: <Widget>[
              TextButton(
                child: Text(
                  S.of(context).yes,
                ),
                onPressed: () async {
                  if (!isTopLevel) {
                    final _pref = LocalDatabaseService.preferences;
                    LocalDatabaseService.preferences =
                        _pref.copyWith(skillLevel: _pref.skillLevel + 1);
                    debugPrint(
                      "[config] skillLevel: ${LocalDatabaseService.preferences.skillLevel}",
                    );
                  }
                  Navigator.pop(context);
                },
              ),
              TextButton(
                child: Text(S.of(context).no),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              dialogTitle,
              style: AppTheme.dialogTitleTextStyle,
            ),
            content: Text(
              getGameOverReasonString(
                gameInstance.position.gameOverReason,
                gameInstance.position.winner,
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(S.of(context).restart),
                onPressed: () {
                  Navigator.pop(context);
                  gameInstance.newGame();
                  if (mounted) {
                    showTip(S.of(context).gameStarted);
                    if (LocalDatabaseService.preferences.screenReaderSupport) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      showSnackBar(context, S.of(context).gameStarted);
                    }
                  }

                  if (gameInstance.isAiToMove) {
                    debugPrint("$_tag New game, AI to move.");
                    engineToGo(false);
                  }
                },
              ),
              TextButton(
                child: Text(S.of(context).cancel),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    }
  }

  double get _screenPaddingH {
    // when screen's height/width rate is less than 16/9, limit width of board
    final windowSize = MediaQuery.of(context).size;
    final double height = windowSize.height;
    double width = windowSize.width;

    // TODO: [Leptopoda] maybe use windowSize.aspectRatio
    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      return (windowSize.width - width) / 2 - AppTheme.boardMargin;
    } else {
      return AppTheme.boardScreenPaddingH;
    }
  }

  Widget get header {
    final Map<EngineType, IconData> engineTypeToIconLeft = {
      EngineType.humanVsAi: LocalDatabaseService.preferences.aiMovesFirst
          ? FluentIcons.bot_24_filled
          : FluentIcons.person_24_filled,
      EngineType.humanVsHuman: FluentIcons.person_24_filled,
      EngineType.aiVsAi: FluentIcons.bot_24_filled,
      EngineType.humanVsCloud: FluentIcons.person_24_filled,
      EngineType.humanVsLAN: FluentIcons.person_24_filled,
      EngineType.testViaLAN: FluentIcons.wifi_1_24_filled,
    };

    final Map<EngineType, IconData> engineTypeToIconRight = {
      EngineType.humanVsAi: LocalDatabaseService.preferences.aiMovesFirst
          ? FluentIcons.person_24_filled
          : FluentIcons.bot_24_filled,
      EngineType.humanVsHuman: FluentIcons.person_24_filled,
      EngineType.aiVsAi: FluentIcons.bot_24_filled,
      EngineType.humanVsCloud: FluentIcons.cloud_24_filled,
      EngineType.humanVsLAN: FluentIcons.wifi_1_24_filled,
      EngineType.testViaLAN: FluentIcons.wifi_1_24_filled,
    };

    final iconColor = LocalDatabaseService.colorSettings.messageColor;

    final iconRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(engineTypeToIconLeft[widget.engineType], color: iconColor),
        Icon(iconArrow, color: iconColor),
        Icon(engineTypeToIconRight[widget.engineType], color: iconColor),
      ],
    );

    return Container(
      margin: EdgeInsets.only(
        top: LocalDatabaseService.display.boardTop +
            (isLargeScreen ? 39.0 : 0.0),
      ),
      child: Column(
        children: <Widget>[
          iconRow,
          Container(
            height: 4,
            width: 180,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: LocalDatabaseService.colorSettings.boardBackgroundColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _tip,
              maxLines: 1,
              style: TextStyle(
                color: LocalDatabaseService.colorSettings.messageColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData get iconArrow {
    if (gameInstance.position.phase == Phase.gameOver) {
      switch (gameInstance.position.winner) {
        case PieceColor.white:
          return ltr
              ? FluentIcons.toggle_left_24_regular
              : FluentIcons.toggle_right_24_regular;
        case PieceColor.black:
          return ltr
              ? FluentIcons.toggle_right_24_regular
              : FluentIcons.toggle_left_24_regular;
        default:
          return FluentIcons.handshake_24_regular;
      }
    } else {
      switch (gameInstance.sideToMove) {
        case PieceColor.white:
          return FluentIcons.chevron_left_24_regular;

        case PieceColor.black:
          return FluentIcons.chevron_right_24_regular;
        default:
          return FluentIcons.code_24_regular;
      }
    }
  }

  Widget get board {
    boardWidth = MediaQuery.of(context).size.width - screenPaddingH * 2;

    return Container(
      margin: EdgeInsets.symmetric(vertical: boardMargin),
      child: Board(
        width: boardWidth,
        onBoardTap: onBoardTap,
        animationValue: animation.value,
      ),
    );
  }

  String get infoText {
    final buffer = StringBuffer();
    final pos = gameInstance.position;

    late final String us;
    late final String them;
    switch (pos.side) {
      case PieceColor.white:
        us = S.of(context).player1;
        them = S.of(context).player2;
        break;
      case PieceColor.black:
        us = S.of(context).player2;
        them = S.of(context).player1;
        break;
      default:
        assert(false);
    }

    switch (pos.phase) {
      case Phase.placing:
        buffer.write(S.of(context).placingPhase);
        break;
      case Phase.moving:
        buffer.write(S.of(context).movingPhase);
        break;
      default:
    }

    if (LocalDatabaseService.preferences.screenReaderSupport) {
      buffer.writeln(":");
    } else {
      buffer.writeln();
    }

    // Last Move information
    if (pos.recorder.lastMove?.notation != null) {
      final String n1 = pos.recorder.lastMove!.notation!;
      // $them is only shown with the screen reader. It is convenient for
      // the disabled to recognize whether the opponent has finished the moving.
      if (LocalDatabaseService.preferences.screenReaderSupport) {
        buffer.write(S.of(context).lastMove("$them, "));
      } else {
        buffer.write(S.of(context).lastMove(""));
      }

      if (n1.startsWith("x")) {
        buffer.writeln(
          pos.recorder.moveAt(pos.recorder.movesCount - 2).notation,
        );
      }
      buffer.writePeriod(n1);
    }

    buffer.writePeriod(S.of(context).sideToMove(us));

    // the tip
    if (LocalDatabaseService.preferences.screenReaderSupport &&
        _tip[_tip.length - 1] != '.' &&
        _tip[_tip.length - 1] != '!') {
      buffer.writePeriod(_tip);
    }

    buffer.writeln();
    buffer.writeln(S.of(context).pieceCount);
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player1,
            pos.pieceInHandCount[PieceColor.white]!,
          ),
    );
    buffer.writeComma(
      S.of(context).inHand(
            S.of(context).player2,
            pos.pieceInHandCount[PieceColor.black]!,
          ),
    );
    buffer.writeComma(
      S.of(context).onBoard(
            S.of(context).player1,
            pos.pieceOnBoardCount[PieceColor.white]!,
          ),
    );
    buffer.writePeriod(
      S.of(context).onBoard(
            S.of(context).player2,
            pos.pieceOnBoardCount[PieceColor.black]!,
          ),
    );
    buffer.writeln();
    buffer.writeln(S.of(context).score);
    buffer
        .writeComma("${S.of(context).player1}: ${pos.score[PieceColor.white]}");
    buffer
        .writeComma("${S.of(context).player2}: ${pos.score[PieceColor.black]}");
    buffer.writePeriod("${S.of(context).draw}: ${pos.score[PieceColor.draw]}");

    return buffer.toString();
  }

  List<Widget> get toolbar {
    final gameButton = ToolbarItem.icon(
      onPressed: onGameButtonPressed,
      icon: const Icon(FluentIcons.table_simple_24_regular),
      label: Text(S.of(context).game),
    );

    final optionsButton = ToolbarItem.icon(
      onPressed: onOptionButtonPressed,
      icon: const Icon(FluentIcons.settings_24_regular),
      label: Text(S.of(context).options),
    );

    final moveButton = ToolbarItem.icon(
      onPressed: onMoveButtonPressed,
      icon: const Icon(FluentIcons.calendar_agenda_24_regular),
      label: Text(S.of(context).move_number(0)),
    );

    final infoButton = ToolbarItem.icon(
      onPressed: onInfoButtonPressed,
      icon: const Icon(FluentIcons.book_information_24_regular),
      label: Text(S.of(context).info),
    );

    return <Widget>[
      gameButton,
      optionsButton,
      moveButton,
      infoButton,
    ];
  }

  List<Widget> get historyNavToolbar {
    final takeBackAllButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.arrow_previous_24_regular
            : FluentIcons.arrow_next_24_regular,
        semanticLabel: S.of(context).takeBackAll,
      ),
      onPressed: () => onTakeBackAllButtonPressed(false),
    );

    final takeBackButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.chevron_left_24_regular
            : FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () async => onTakeBackButtonPressed(false),
    );

    final stepForwardButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.chevron_right_24_regular
            : FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () async => onStepForwardButtonPressed(false),
    );

    final stepForwardAllButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.arrow_next_24_regular
            : FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).stepForwardAll,
      ),
      onPressed: () async => onStepForwardAllButtonPressed(false),
    );

    return <Widget>[
      takeBackAllButton,
      takeBackButton,
      stepForwardButton,
      stepForwardAllButton,
    ];
  }

  @override
  void initState() {
    debugPrint("$_tag Engine type: ${widget.engineType}");

    gameInstance.setWhoIsAi(widget.engineType);

    super.initState();
    gameInstance.init();
    _engine.startup();

    timer = Timer.periodic(
      const Duration(microseconds: 100),
      (_) => _setReadyState(),
    );

    _initAnimation();

    LocalDatabaseService.listenPreferences.addListener(_refreshEngine);
  }

  Future<void> _refreshEngine() async {
    await _engine.setOptions();
    debugPrint("$_tag reloaded engine options");
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screenPaddingH = _screenPaddingH;
    ltr = Directionality.of(context) == TextDirection.ltr;
    _tip = S.of(context).welcome;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: const IconThemeData(
          color: AppTheme.drawerAnimationIconColor,
        ),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: LocalDatabaseService.colorSettings.darkBackgroundColor,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenPaddingH),
        child: Column(
          children: <Widget>[
            BlockSemantics(child: header),
            board,
            if (LocalDatabaseService.display.isHistoryNavigationToolbarShown)
              GamePageToolBar(
                backgroundColor: LocalDatabaseService
                    .colorSettings.navigationToolbarBackgroundColor,
                itemColor: LocalDatabaseService
                    .colorSettings.navigationToolbarIconColor,
                children: historyNavToolbar,
              ),
            GamePageToolBar(
              backgroundColor:
                  LocalDatabaseService.colorSettings.mainToolbarBackgroundColor,
              itemColor:
                  LocalDatabaseService.colorSettings.mainToolbarIconColor,
              children: toolbar,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint("$_tag dispose");
    disposed = true;
    _engine.shutdown();
    _animationController.dispose();
    LocalDatabaseService.listenPreferences.removeListener(_refreshEngine);
    super.dispose();
  }
}

extension CustomStringBuffer on StringBuffer {
  void writeComma([Object? obj = ""]) {
    if (LocalDatabaseService.preferences.screenReaderSupport) {
      writeln("$obj,");
    } else {
      writeln(obj);
    }
  }

  void writePeriod([Object? obj = ""]) {
    if (LocalDatabaseService.preferences.screenReaderSupport) {
      writeln("$obj.");
    } else {
      writeln(obj);
    }
  }
}
