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
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/services/engine/native_engine.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
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

part 'package:sanmill/screens/game_page/board.dart';
part 'package:sanmill/screens/game_page/result_alert.dart';
part 'package:sanmill/screens/game_page/info_dialog.dart';
part 'package:sanmill/screens/game_page/move_list_dialog.dart';

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

    logger.v("[tip] $tip");
    if (LocalDatabaseService.preferences.screenReaderSupport && snackBar) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, tip);
    }

    setState(() => _tip = tip);
  }

  void _showTips() {
    if (!mounted) return;

    final winner = controller.position.winner;
    _showTip(winner.getWinString(context));
    if (winner == PieceColor.nobody) {
      return;
    }

    if (!LocalDatabaseService.preferences.isAutoRestart) {
      _GameResultAlert(
        winner: winner,
        onRestart: () {
          controller.gameInstance.newGame();
          _showTip(S.of(context).gameStarted, snackBar: true);

          if (controller.gameInstance.isAiToMove) {
            logger.i("$_tag New game, AI to move.");
            _engineToGo(isMoveNow: false);
          }
        },
      );
    }
  }

  Future<void> _onBoardTap(int sq) async {
    if (!mounted) return logger.v("[tap] Not ready, ignore tapping.");

    if (widget.engineType == EngineType.aiVsAi ||
        widget.engineType == EngineType.testViaLAN) {
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
          return _engineToGo(isMoveNow: false);
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
                  final side = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  _showTip(
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
                _showTip(S.of(context).tipCanMoveToAnyPoint, snackBar: true);
              } else {
                _showTip(S.of(context).tipPlace, snackBar: true);
              }
              break;
            // TODO: [Leptopoda] deduplicate
            case SelectionResponse.r2:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                _showTip(S.of(context).tipCannotMove, snackBar: true);
              }
              break;
            case SelectionResponse.r3:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipCanMoveOnePoint, snackBar: true);
              break;
            case SelectionResponse.r4:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipSelectPieceToMove, snackBar: true);
              break;
            case SelectionResponse.r1:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] selectPiece: skip [$sq]");
              _showTip(S.of(context).tipSelectWrong, snackBar: true);
              break;
          }
          break;

        case Act.remove:
          switch (await position.removePiece(sq)) {
            case RemoveResponse.r0:
              _animationController.reset();
              _animationController.animateTo(1.0);

              ret = true;
              logger.v("[tap] removePiece: [$sq]");
              if (controller.position.pieceToRemoveCount >= 1) {
                _showTip(S.of(context).tipContinueMill, snackBar: true);
              } else {
                if (widget.engineType == EngineType.humanVsAi) {
                  _showTip(S.of(context).tipRemoved);
                } else {
                  final them = controller.gameInstance.sideToMove.opponent
                      .playerName(context);
                  _showTip(S.of(context).tipToMove(them));
                }
              }
              break;
            case RemoveResponse.r2:
              await Audios.playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot Remove our pieces, skip [$sq]",
              );
              _showTip(S.of(context).tipSelectOpponentsPiece, snackBar: true);
              break;
            case RemoveResponse.r3:
              await Audios.playTone(Sound.illegal);
              logger.i(
                "[tap] removePiece: Cannot remove piece from Mill, skip [$sq]",
              );
              _showTip(
                S.of(context).tipCannotRemovePieceFromMill,
                snackBar: true,
              );
              break;
            case RemoveResponse.r1:
              await Audios.playTone(Sound.illegal);
              logger.v("[tap] removePiece: skip [$sq]");
              if (position.phase != Phase.gameOver) {
                _showTip(S.of(context).tipBanRemove, snackBar: true);
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
                position.hasGameCycle()) {
              position.setGameOver(
                PieceColor.draw,
                GameOverReason.drawReasonThreefoldRepetition,
              );
            }
          }
        } else {
          position.posKeyHistory.clear();
        }

        //position.move = m;
        final Move m = position.record!;
        position.recorder.prune();
        position.recorder.moveIn(m, position);

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          _engineToGo(isMoveNow: false);
        } else {
          _showTips();
        }
      }

      controller.gameInstance.sideToMove = position.sideToMove;

      setState(() {});
    } catch (e) {
      // TODO: [Leptopoda] improve error handling
      rethrow;
    }
  }

  Future<void> _engineToGo({required bool isMoveNow}) async {
    bool _isMoveNow = isMoveNow;

    if (!mounted) return logger.i("[engineToGo] !mounted, skip engineToGo.");

    // TODO
    logger.v("[engineToGo] engine type is ${widget.engineType}");

    if (_isMoveNow) {
      if (!controller.gameInstance.isAiToMove) {
        logger.i("[engineToGo] Human to Move. Cannot get search result now.");
        ScaffoldMessenger.of(context).clearSnackBars();
        return showSnackBar(context, S.of(context).notAIsTurn);
      }
      if (!controller.position.recorder.isClean()) {
        logger.i(
          "[engineToGo] History is not clean. Cannot get search result now.",
        );
        ScaffoldMessenger.of(context).clearSnackBars();
        return showSnackBar(context, S.of(context).aiIsNotThinking);
      }
    }

    while ((controller.position.winner == PieceColor.nobody ||
            LocalDatabaseService.preferences.isAutoRestart) &&
        controller.gameInstance.isAiToMove &&
        mounted) {
      if (widget.engineType == EngineType.aiVsAi) {
        _showTip(
          "${controller.position.score[PieceColor.white]} : ${controller.position.score[PieceColor.black]} : ${controller.position.score[PieceColor.draw]}",
        );
      } else {
        if (mounted) {
          _showTip(S.of(context).thinking);

          final String? n = controller.position.recorder.lastMove?.notation;

          if (LocalDatabaseService.preferences.screenReaderSupport &&
              controller.position.action != Act.remove &&
              n != null) {
            showSnackBar(context, "${S.of(context).human}: $n");
          }
        }
      }

      final EngineResponse response;
      if (!_isMoveNow) {
        logger.v("[engineToGo] Searching...");
        response = await _engine.search(controller.position);
      } else {
        logger.v("[engineToGo] Get search result now...");
        response = await _engine.search(null);
        _isMoveNow = false;
      }

      logger.i("[engineToGo] Engine response type: ${response.type}");

      switch (response.type) {
        case EngineResponseType.move:
          final Move move = response.value!;

          await controller.gameInstance.doMove(move);
          _animationController.reset();
          _animationController.animateTo(1.0);

          _showTips();
          if (LocalDatabaseService.preferences.screenReaderSupport) {
            showSnackBar(context, "${S.of(context).ai}: ${move.notation}");
          }
          break;
        case EngineResponseType.timeout:
          return _showTip(S.of(context).timeout, snackBar: true);
        case EngineResponseType.nobestmove:
          _showTip(S.of(context).error(response.type));
      }

      if (LocalDatabaseService.preferences.isAutoRestart &&
          controller.position.winner != PieceColor.nobody) {
        controller.gameInstance.newGame();
      }
    }
  }

  Future<void> _startNew() async {
    Navigator.pop(context);

    if (controller.gameInstance.isAiToMove) {
      // TODO: Move now
      //logger.i("$tag New game, AI to move, move now.");
      //await engineToGo(true);
    }

    controller.gameInstance.newGame();

    _showTip(S.of(context).gameStarted, snackBar: true);

    if (controller.gameInstance.isAiToMove) {
      logger.v("$_tag New game, AI to move.");
      _engineToGo(isMoveNow: false);
    }
  }

  Future<void> _importGame() async {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);

    if (data?.text == null) return;

    await _takeBackAll(pop: false);
    final importFailedStr = controller.position.recorder.import(data!.text!);

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
      ClipboardData(text: controller.position.moveHistoryText),
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
            if (controller.position.moveHistoryText != null) ...[
              SimpleDialogOption(
                onPressed: _showMoveList,
                child: Text(
                  S.of(context).showMoveList,
                  style: AppTheme.simpleDialogOptionTextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              const CustomSpacer(),
            ],
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
      return logger.i(
        "[TakeBack] Is going to history, ignore Take Back button press.",
      );
    }

    _isGoingToHistory = true;

    final response = await controller.position.gotoHistory(move, number);
    if (response != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      showSnackBar(context, response.getString(context));
    }

    _isGoingToHistory = false;

    if (mounted) {
      final pos = controller.position;

      late final String text;
      final lastEffectiveMove = pos.recorder.lastEffectiveMove;
      if (lastEffectiveMove?.notation != null) {
        text = S.of(context).lastMove(lastEffectiveMove!.notation);
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

  void _showMoveList() => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _MoveListDialog(
          takeBackCallback: _takeBackN,
        ),
      );

  Future<void> _moveNow() async {
    Navigator.pop(context);
    await _engineToGo(isMoveNow: true);
  }

  void _showInfo() => showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _InfoDialog(tip: _tip),
      );

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
    final left = widget.engineType.leftHeaderIcon;
    final right = widget.engineType.rightHeaderIcon;
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
            (Constants.isLargeScreen ? 39.0 : 0.0),
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
    if (controller.position.phase == Phase.gameOver) {
      switch (controller.position.winner) {
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
      switch (controller.gameInstance.sideToMove) {
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
    logger.i("$_tag reloaded engine options");
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

    logger.i("$_tag Engine type: ${widget.engineType}");
    controller.gameInstance.setWhoIsAi(widget.engineType);

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
    logger.i("$_tag dispose");
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
