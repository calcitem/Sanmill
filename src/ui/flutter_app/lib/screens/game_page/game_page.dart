// ignore_for_file: use_build_context_synchronously

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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/position.dart';
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

  const GamePage(this.engineType, {Key? key}) : super(key: key);

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with RouteAware, SingleTickerProviderStateMixin {
  final Engine _engine = NativeEngine();

  double screenPaddingH = AppTheme.boardScreenPaddingH;
  final double _boardMargin = AppTheme.boardMargin;

  late String _tip;
  bool _isGoingToHistory = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  late bool ltr;
  late double boardWidth;

  static const String _tag = "[game_page]";

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: LocalDatabaseService.display.animationDuration.toInt(),
      ),
    );

    // sqrt(1.618) = 1.272
    _animation = Tween(begin: 1.27, end: 1.0).animate(_animationController);
  }

  void _showTip(String tip, {bool snackBar = false}) {
    if (!mounted) return;

    debugPrint("[tip] $tip");
    if (LocalDatabaseService.preferences.screenReaderSupport && snackBar) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, tip);
    }

    setState(() => _tip = tip);
  }

  void _showTips() {
    if (!mounted) return;

    final winner = gameInstance.position.winner;

    switch (winner) {
      case PieceColor.white:
        _showTip(S.of(context).whiteWin);
        break;
      case PieceColor.black:
        _showTip(S.of(context).blackWin);
        break;
      case PieceColor.draw:
        _showTip(S.of(context).isDraw);
        break;
      case PieceColor.nobody:
        switch (gameInstance.position.phase) {
          case Phase.placing:
            return _showTip(S.of(context).tipPlace);
          case Phase.moving:
            return _showTip(S.of(context).tipMove);
          default:
        }
    }

    if (!LocalDatabaseService.preferences.isAutoRestart) {
      _showGameResult(winner);
    }
  }

  Future<void> _onBoardTap(int sq) async {
    if (!mounted) return debugPrint("[tap] Not ready, ignore tapping.");

    if (widget.engineType == EngineType.aiVsAi ||
        widget.engineType == EngineType.testViaLAN) {
      return debugPrint("$_tag Engine type is no human, ignore tapping.");
    }

    final position = gameInstance.position;

    // If nobody has placed, start to go.
    if (position.phase == Phase.placing &&
        position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      gameInstance.newGame();

      if (gameInstance.isAiToMove) {
        if (gameInstance.aiIsSearching) {
          return debugPrint("$_tag AI is thinking, skip tapping.");
        } else {
          debugPrint("[tap] AI is not thinking. AI is to move.");
          return _engineToGo(isMoveNow: false);
        }
      }
    }

    if (gameInstance.isAiToMove || gameInstance.aiIsSearching) {
      return debugPrint("[tap] AI's turn, skip tapping.");
    }

    if (position.phase == Phase.ready) gameInstance.start();

    // Human to go
    bool ret = false;
    await Chain.capture(() async {
      switch (position.action) {
        case Act.place:
          if (await position.putPiece(sq)) {
            _animationController.reset();
            _animationController.animateTo(1.0);
            if (position.action == Act.remove) {
              _showTip(S.of(context).tipMill, snackBar: true);
            } else {
              if (widget.engineType == EngineType.humanVsAi) {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  _showTip(S.of(context).continueToMakeMove);
                } else {
                  _showTip(S.of(context).tipPlaced);
                }
              } else {
                if (LocalDatabaseService
                    .rules.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                  // TODO: HumanVsHuman - Change tip
                  _showTip(S.of(context).tipPlaced);
                } else {
                  final side = gameInstance.sideToMove == PieceColor.white
                      ? S.of(context).black
                      : S.of(context).white;
                  _showTip(S.of(context).tipToMove(side));
                }
              }
            }
            ret = true;
            debugPrint("[tap] putPiece: [$sq]");
            break;
          } else {
            debugPrint("[tap] putPiece: skip [$sq]");
            _showTip(S.of(context).tipBanPlace);
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.phase == Phase.placing) {
            _showTip(S.of(context).tipCannotPlace, snackBar: true);
            break;
          }
          switch (position.selectPiece(sq)) {
            case 0:
              await Audios.playTone(Sound.select);
              gameInstance.select(squareToIndex[sq]!);
              ret = true;
              debugPrint("[tap] selectPiece: [$sq]");

              final us = gameInstance.sideToMove;
              if (position.phase == Phase.moving &&
                  LocalDatabaseService.rules.mayFly &&
                  (gameInstance.position.pieceOnBoardCount[us] ==
                          LocalDatabaseService.rules.flyPieceCount ||
                      gameInstance.position.pieceOnBoardCount[us] == 3)) {
                debugPrint("[tap] May fly.");
                _showTip(S.of(context).tipCanMoveToAnyPoint, snackBar: true);
              } else {
                _showTip(S.of(context).tipPlace, snackBar: true);
              }

              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                _showTip(S.of(context).tipCannotMove, snackBar: true);
              }
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
              break;
            case -4:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipSelectWrong, snackBar: true);
          }
          break;

        case Act.remove:
          switch (await position.removePiece(sq)) {
            case 0:
              _animationController.reset();
              _animationController.animateTo(1.0);

              ret = true;
              debugPrint("[tap] removePiece: [$sq]");
              if (gameInstance.position.pieceToRemoveCount >= 1) {
                _showTip(S.of(context).tipContinueMill, snackBar: true);
              } else {
                if (widget.engineType == EngineType.humanVsAi) {
                  _showTip(S.of(context).tipRemoved);
                } else {
                  final them = gameInstance.sideToMove == PieceColor.white
                      ? S.of(context).black
                      : S.of(context).white;
                  _showTip(S.of(context).tipToMove(them));
                }
              }
              break;
            case -2:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              _showTip(S.of(context).tipSelectOpponentsPiece, snackBar: true);
              break;
            case -3:
              await Audios.playTone(Sound.illegal);
              debugPrint(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              _showTip(
                S.of(context).tipCannotRemovePieceFromMill,
                snackBar: true,
              );
              break;
            default:
              await Audios.playTone(Sound.illegal);
              debugPrint("[tap] removePiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                _showTip(S.of(context).tipBanRemove, snackBar: true);
              }
          }
          break;
        case Act.none:
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
            if (LocalDatabaseService.rules.threefoldRepetitionRule &&
                position.hasGameCycle()) {
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
          _engineToGo(isMoveNow: false);
        } else {
          _showTips();
        }
      }

      gameInstance.sideToMove = position.sideToMove;

      setState(() {});
    });
  }

  Future<void> _engineToGo({required bool isMoveNow}) async {
    bool _isMoveNow = isMoveNow;

    if (!mounted) return debugPrint("[engineToGo] !mounted, skip engineToGo.");

    // TODO
    debugPrint("[engineToGo] engine type is ${widget.engineType}");

    if (_isMoveNow) {
      if (!gameInstance.isAiToMove) {
        debugPrint("[engineToGo] Human to Move. Cannot get search result now.");
        ScaffoldMessenger.of(context).clearSnackBars();
        return showSnackBar(context, S.of(context).notAIsTurn);
      }
      if (!gameInstance.position.recorder.isClean()) {
        debugPrint(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        ScaffoldMessenger.of(context).clearSnackBars();
        return showSnackBar(context, S.of(context).aiIsNotThinking);
      }
    }

    while ((LocalDatabaseService.preferences.isAutoRestart ||
            gameInstance.position.winner == PieceColor.nobody) &&
        gameInstance.isAiToMove &&
        mounted) {
      if (widget.engineType == EngineType.aiVsAi) {
        _showTip(
          "${gameInstance.position.score[PieceColor.white]} : ${gameInstance.position.score[PieceColor.black]} : ${gameInstance.position.score[PieceColor.draw]}",
        );
      } else {
        if (mounted) {
          _showTip(S.of(context).thinking);

          final String? n = gameInstance.position.recorder.lastMove?.notation;

          if (LocalDatabaseService.preferences.screenReaderSupport &&
              gameInstance.position.action != Act.remove &&
              n != null) {
            showSnackBar(context, "${S.of(context).human}: $n");
          }
        }
      }

      final EngineResponse response;
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

          await gameInstance.doMove(move.move);
          _animationController.reset();
          _animationController.animateTo(1.0);

          _showTips();
          if (LocalDatabaseService.preferences.screenReaderSupport &&
              move.notation != null) {
            showSnackBar(context, "${S.of(context).ai}: ${move.notation!}");
          }
          break;
        case 'timeout':
          return _showTip(S.of(context).timeout, snackBar: true);
        default:
          _showTip(S.of(context).error(response.type));
      }

      if (LocalDatabaseService.preferences.isAutoRestart &&
          gameInstance.position.winner != PieceColor.nobody) {
        gameInstance.newGame();
      }
    }
  }

  Future<void> _startNew() async {
    Navigator.pop(context);

    if (gameInstance.isAiToMove) {
      // TODO: Move now
      //debugPrint("$tag New game, AI to move, move now.");
      //await engineToGo(true);
    }

    gameInstance.newGame();

    _showTip(S.of(context).gameStarted, snackBar: true);

    if (gameInstance.isAiToMove) {
      debugPrint("$_tag New game, AI to move.");
      _engineToGo(isMoveNow: false);
    }
  }

  Future<void> _importGame() async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data?.text == null) return;

    await _takeBackAll(pop: false);
    final importFailedStr = gameInstance.position.recorder.import(data!.text!);

    if (importFailedStr != null) {
      return _showTip(
        S.of(context).cannotImport(importFailedStr),
        snackBar: true,
      );
    }

    await _stepForwardAll(pop: false);

    _showTip(S.of(context).gameImported, snackBar: true);
  }

  Future<void> _exportGame() async {
    Navigator.pop(context);

    await Clipboard.setData(
      ClipboardData(text: gameInstance.position.moveHistoryText),
    );
    showSnackBar(context, S.of(context).moveHistoryCopied);
  }

  void _showGameOptions() => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => SimpleDialog(
          semanticLabel: S.of(context).game,
          backgroundColor: Colors.transparent,
          children: <Widget>[
            SimpleDialogOption(
              onPressed: _startNew,
              child: Text(
                S.of(context).newGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: _importGame,
              child: Text(
                S.of(context).importGame,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: _exportGame,
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
      );

  void _showSettings() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GameSettingsPage()),
      );

  void _showMoveOptions() => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => SimpleDialog(
          semanticLabel: S.of(context).move_number(0),
          backgroundColor: Colors.transparent,
          children: <Widget>[
            if (!LocalDatabaseService
                .display.isHistoryNavigationToolbarShown) ...[
              SimpleDialogOption(
                onPressed: _takeBack,
                child: Text(
                  S.of(context).takeBack,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              const CustomSpacer(),
              SimpleDialogOption(
                onPressed: _stepForward,
                child: Text(
                  S.of(context).stepForward,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              const CustomSpacer(),
              SimpleDialogOption(
                onPressed: _takeBackAll,
                child: Text(
                  S.of(context).takeBackAll,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              const CustomSpacer(),
              SimpleDialogOption(
                onPressed: _stepForwardAll,
                child: Text(
                  S.of(context).stepForwardAll,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              const CustomSpacer(),
            ],
            SimpleDialogOption(
              onPressed: _showMoveList,
              child: Text(
                S.of(context).showMoveList,
                style: AppTheme.simpleDialogOptionTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
            const CustomSpacer(),
            SimpleDialogOption(
              onPressed: _moveNow,
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
      );

  Future<void> _gotoHistory(
    HistoryMove move, {
    bool pop = true,
    int? number,
  }) async {
    if (pop) Navigator.pop(context);

    _showTip(S.of(context).waiting);

    if (_isGoingToHistory) {
      return debugPrint(
        "[TakeBack] Is going to history, ignore Take Back button press.",
      );
    }

    _isGoingToHistory = true;

    switch (await gameInstance.position.gotoHistory(move, number)) {
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
    }

    _isGoingToHistory = false;

    if (mounted) {
      final pos = gameInstance.position;

      late final String text;
      final lastEffectiveMove = pos.recorder.lastEffectiveMove;
      if (lastEffectiveMove?.notation != null) {
        text = S.of(context).lastMove(lastEffectiveMove!.notation!);
      } else {
        text = S.of(context).atEnd;
      }

      _showTip(text, snackBar: true);
    }
  }

  Future<void> _takeBack({bool pop = true}) async => _gotoHistory(
        HistoryMove.backOne,
        pop: pop,
      );

  Future<void> _stepForward({bool pop = true}) async => _gotoHistory(
        HistoryMove.forward,
        pop: pop,
      );

  Future<void> _takeBackAll({bool pop = true}) async => _gotoHistory(
        HistoryMove.backAll,
        pop: pop,
      );

  Future<void> _stepForwardAll({bool pop = true}) async => _gotoHistory(
        HistoryMove.forwardAll,
        pop: pop,
      );

  Future<void> _takeBackN(int n, {bool pop = true}) async => _gotoHistory(
        HistoryMove.backN,
        number: n,
        pop: pop,
      );

  void _showMoveList() {
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
                  assert(selectValue != null);
                  _takeBackN(selectValue!);
                },
              ),
            TextButton(
              child: Text(
                S.of(context).copy,
                style: AppTheme.moveHistoryTextStyle,
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: moveHistoryText));
                ScaffoldMessenger.of(context).clearSnackBars();
                showSnackBar(context, S.of(context).moveHistoryCopied);
              },
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

  Future<void> _moveNow() async {
    Navigator.pop(context);
    await _engineToGo(isMoveNow: true);
  }

  void _showInfo() => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: AppTheme.infoDialogBackgroundColor,
            content: SingleChildScrollView(
              child: Text(_infoText, style: AppTheme.moveHistoryTextStyle),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  S.of(context).ok,
                  key: const Key('infoDialogOkButton'),
                  style: AppTheme.moveHistoryTextStyle,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );

  String _getGameOverReasonString(GameOverReason? reason, String? winner) {
    final String loserStr =
        winner == PieceColor.white ? S.of(context).black : S.of(context).white;

    switch (gameInstance.position.gameOverReason) {
      case GameOverReason.loseReasonlessThanThree:
        return S.of(context).loseReasonlessThanThree(loserStr);
      case GameOverReason.loseReasonResign:
        return S.of(context).loseReasonResign(loserStr);
      case GameOverReason.loseReasonNoWay:
        return S.of(context).loseReasonNoWay(loserStr);
      case GameOverReason.loseReasonBoardIsFull:
        return S.of(context).loseReasonBoardIsFull(loserStr);
      case GameOverReason.loseReasonTimeOver:
        return S.of(context).loseReasonTimeOver(loserStr);
      case GameOverReason.drawReasonRule50:
        return S.of(context).drawReasonRule50;
      case GameOverReason.drawReasonEndgameRule50:
        return S.of(context).drawReasonEndgameRule50;
      case GameOverReason.drawReasonBoardIsFull:
        return S.of(context).drawReasonBoardIsFull;
      case GameOverReason.drawReasonThreefoldRepetition:
        return S.of(context).drawReasonThreefoldRepetition;
      case GameOverReason.noReason:
        return S.of(context).gameOverUnknownReason;
    }
  }

  GameResult _getGameResult(String winner) {
    if (widget.engineType == EngineType.aiVsAi) return GameResult.none;

    switch (winner) {
      case PieceColor.white:
        if (isAi[PieceColor.white]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.black:
        if (isAi[PieceColor.black]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.draw:
        return GameResult.draw;
      default:
        return GameResult.none;
    }
  }

  void _showGameResult(String winner) {
    final GameResult result = _getGameResult(winner);
    gameInstance.position.result = result;

    final String dialogTitle;
    switch (result) {
      case GameResult.win:
        dialogTitle = widget.engineType == EngineType.humanVsAi
            ? S.of(context).youWin
            : S.of(context).gameOver;
        break;
      case GameResult.lose:
        dialogTitle = S.of(context).gameOver;
        break;
      case GameResult.draw:
        dialogTitle = S.of(context).isDraw;
        break;
      default:
        return;
    }

    final bool isTopLevel =
        LocalDatabaseService.preferences.skillLevel == 30; // TODO: 30

    final content = StringBuffer(
      _getGameOverReasonString(
        gameInstance.position.gameOverReason,
        gameInstance.position.winner,
      ),
    );

    debugPrint("$_tag Game over reason string: $content");

    final List<Widget> actions;
    if (result == GameResult.win &&
        !isTopLevel &&
        widget.engineType == EngineType.humanVsAi) {
      content.writeln();
      content.writeln();
      content.writeln(
        S.of(context).challengeHarderLevel(
              LocalDatabaseService.preferences.skillLevel + 1,
            ),
      );

      actions = [
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
      ];
    } else {
      actions = [
        TextButton(
          child: Text(S.of(context).restart),
          onPressed: () {
            Navigator.pop(context);
            gameInstance.newGame();
            _showTip(S.of(context).gameStarted, snackBar: true);

            if (gameInstance.isAiToMove) {
              debugPrint("$_tag New game, AI to move.");
              _engineToGo(isMoveNow: false);
            }
          },
        ),
        TextButton(
          child: Text(S.of(context).cancel),
          onPressed: () => Navigator.pop(context),
        ),
      ];
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: Text(
          dialogTitle,
          style: AppTheme.dialogTitleTextStyle,
        ),
        content: Text(content.toString()),
        actions: actions,
      ),
    );
  }

  double get _screenPaddingH {
    // when screen's height/width rate is less than 16/9, limit width of board
    final windowSize = MediaQuery.of(context).size;
    final double height = windowSize.height;
    double width = windowSize.width;

    // TODO: [Leptopoda] maybe use windowSize.aspectratio
    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      return (windowSize.width - width) / 2 - AppTheme.boardMargin;
    } else {
      return AppTheme.boardScreenPaddingH;
    }
  }

  Widget get _header {
    late final IconData left;
    late final IconData right;
    switch (widget.engineType) {
      case EngineType.humanVsAi:
        if (LocalDatabaseService.preferences.aiMovesFirst) {
          left = FluentIcons.bot_24_filled;
          right = FluentIcons.person_24_filled;
        } else {
          left = FluentIcons.person_24_filled;
          right = FluentIcons.bot_24_filled;
        }
        break;
      case EngineType.humanVsHuman:
        left = FluentIcons.person_24_filled;
        right = FluentIcons.person_24_filled;
        break;
      case EngineType.aiVsAi:
        left = FluentIcons.bot_24_filled;
        right = FluentIcons.bot_24_filled;
        break;
      case EngineType.humanVsCloud:
        left = FluentIcons.person_24_filled;
        right = FluentIcons.cloud_24_filled;
        break;
      case EngineType.humanVsLAN:
        left = FluentIcons.person_24_filled;
        right = FluentIcons.wifi_1_24_filled;
        break;
      case EngineType.testViaLAN:
        left = FluentIcons.wifi_1_24_filled;
        right = FluentIcons.wifi_1_24_filled;
        break;
      default:
        assert(false);
    }

    final iconColor = LocalDatabaseService.colorSettings.messageColor;

    final iconRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(left, color: iconColor),
        Icon(_iconArrow, color: iconColor),
        Icon(right, color: iconColor),
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

  IconData get _iconArrow {
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

  Widget get _board {
    boardWidth = MediaQuery.of(context).size.width - screenPaddingH * 2;

    return Container(
      margin: EdgeInsets.symmetric(vertical: _boardMargin),
      child: Board(
        width: boardWidth,
        onBoardTap: _onBoardTap,
        animation: _animation,
      ),
    );
  }

  String get _infoText {
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
      onPressed: _showGameOptions,
      icon: const Icon(FluentIcons.table_simple_24_regular),
      label: Text(S.of(context).game),
    );

    final optionsButton = ToolbarItem.icon(
      onPressed: _showSettings,
      icon: const Icon(FluentIcons.settings_24_regular),
      label: Text(S.of(context).options),
    );

    final moveButton = ToolbarItem.icon(
      onPressed: _showMoveOptions,
      icon: const Icon(FluentIcons.calendar_agenda_24_regular),
      label: Text(S.of(context).move_number(0)),
    );

    final infoButton = ToolbarItem.icon(
      onPressed: _showInfo,
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
      onPressed: () => _takeBackAll(pop: false),
    );

    final takeBackButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.chevron_left_24_regular
            : FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () async => _takeBack(pop: false),
    );

    final stepForwardButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.chevron_right_24_regular
            : FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () async => _stepForward(pop: false),
    );

    final stepForwardAllButton = ToolbarItem(
      child: Icon(
        ltr
            ? FluentIcons.arrow_next_24_regular
            : FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).stepForwardAll,
      ),
      onPressed: () async => _stepForwardAll(pop: false),
    );

    return <Widget>[
      takeBackAllButton,
      takeBackButton,
      stepForwardButton,
      stepForwardAllButton,
    ];
  }

  Future<void> _refreshEngine() async {
    await _engine.setOptions();
    debugPrint("$_tag reloaded engine options");
  }

  Future<void> _showPrivacyDialog() async {
    if (!LocalDatabaseService.preferences.isPrivacyPolicyAccepted &&
        Localizations.localeOf(context).languageCode.startsWith("zh_")) {
      await showPrivacyDialog(context);
    }
  }

  @override
  void initState() {
    super.initState();

    debugPrint("$_tag Engine type: ${widget.engineType}");
    gameInstance.setWhoIsAi(widget.engineType);

    gameInstance.init();
    _engine.startup();

    _initAnimation();

    LocalDatabaseService.listenPreferences.addListener(_refreshEngine);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    screenPaddingH = _screenPaddingH;
    ltr = Directionality.of(context) == TextDirection.ltr;
    _tip = S.of(context).welcome;

    _showPrivacyDialog();
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
            BlockSemantics(child: _header),
            _board,
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
