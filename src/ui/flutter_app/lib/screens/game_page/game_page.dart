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
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/screens/game_settings/game_settings_page.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/services/mill/src/tap_handler.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/game_toolbar/game_toolbar.dart';
import 'package:sanmill/shared/number_picker.dart';
import 'package:sanmill/shared/painters/painters.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';
import 'package:sanmill/shared/string_buffer_helper.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part './board.dart';
part './info_dialog.dart';
part './move_list_dialog.dart';
part './result_alert.dart';

// TODO: [Leptopoda] extract more widgets
// TODO: [Leptopoda] change layout (landscape mode, padding on small devices)
class GamePage extends StatefulWidget {
  final GameMode gameMode;

  const GamePage(this.gameMode, {Key? key}) : super(key: key);

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  static const String _tag = "[game_page]";

  late final TapHandler extracted;

  double screenPaddingH = AppTheme.boardScreenPaddingH;
  late AnimationController _animationController;
  late Animation<double> _animation;

  late String _tip;
  bool _isGoingToHistory = false;

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

  // TODO: [Leptopoda] move the tip into the controller as a value listenable
  void _showTip(String tip, {bool snackBar = false}) {
    if (!mounted) return;

    logger.v("[tip] $tip");
    if (LocalDatabaseService.preferences.screenReaderSupport && snackBar) {
      ScaffoldMessenger.of(context).showSnackBarClear(tip);
    }

    setState(() => _tip = tip);
  }

  void _showResult() {
    final winner = controller.position.winner;
    final message = winner.getWinString(context);
    if (message != null) {
      _showTip(message);
    }

    if (!LocalDatabaseService.preferences.isAutoRestart &&
        winner != PieceColor.nobody) {
      _GameResultAlert(
        winner: winner,
        onRestart: () {
          controller.gameInstance.newGame();
          _showTip(S.of(context).gameStarted, snackBar: true);

          if (controller.gameInstance.isAiToMove) {
            logger.i("$_tag New game, AI to move.");
            extracted.engineToGo(isMoveNow: false);
          }
        },
      );
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
      extracted.engineToGo(isMoveNow: false);
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

  Future<void> _exportGame(BuildContext context) async {
    Navigator.pop(context);

    await Clipboard.setData(
      ClipboardData(text: controller.position.moveHistoryText),
    );

    ScaffoldMessenger.of(context)
        .showSnackBarClear(S.of(context).moveHistoryCopied);
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
              onPressed: () => _exportGame(context),
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
      ScaffoldMessenger.of(context)
          .showSnackBarClear(response.getString(context));
    }

    _isGoingToHistory = false;

    if (mounted) {
      final String text;
      final lastEffectiveMove = controller.position.recorder.lastEffectiveMove;
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

  void _showMoveList() {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MoveListDialog(
        takeBackCallback: _takeBackN,
        exportGame: _exportGame,
      ),
    );
  }

  Future<void> _moveNow() async {
    Navigator.pop(context);
    await extracted.engineToGo(isMoveNow: true);
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

    // TODO: [Leptopoda] maybe use windowSize.aspectRatio
    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      return (windowSize.width - width) / 2 - AppTheme.boardMargin;
    } else {
      return AppTheme.boardScreenPaddingH;
    }
  }

  Widget get _header {
    final iconRow = IconTheme(
      data: IconThemeData(
        color: LocalDatabaseService.colorSettings.messageColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(widget.gameMode.leftHeaderIcon),
          Icon(_iconArrow),
          Icon(widget.gameMode.rightHeaderIcon),
        ],
      ),
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
    return controller.gameInstance.sideToMove.icon;
  }

  Widget get _board {
    final boardWidth = MediaQuery.of(context).size.width - screenPaddingH * 2;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppTheme.boardMargin),
      child: _Board(
        width: boardWidth,
        // TODO: [Leptopoda] consider moving this into the Board itself and find another solution for [engineToGo()]
        onBoardTap: extracted.onBoardTap,
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
        FluentIcons.arrow_previous_24_regular,
        semanticLabel: S.of(context).takeBackAll,
      ),
      onPressed: () => _takeBackAll(pop: false),
    );

    final takeBackButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_left_24_regular,
        semanticLabel: S.of(context).takeBack,
      ),
      onPressed: () async => _takeBack(pop: false),
    );

    final stepForwardButton = ToolbarItem(
      child: Icon(
        FluentIcons.chevron_right_24_regular,
        semanticLabel: S.of(context).stepForward,
      ),
      onPressed: () async => _stepForward(pop: false),
    );

    final stepForwardAllButton = ToolbarItem(
      child: Icon(
        FluentIcons.arrow_next_24_regular,
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

  @override
  void initState() {
    super.initState();
    controller.gameInstance.gameMode = widget.gameMode;

    _initAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    extracted = TapHandler(
      animationController: _animationController,
      context: context,
      showTip: _showTip,
      onWin: _showResult,
    );

    screenPaddingH = _screenPaddingH;
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
        child: FutureBuilder(
          future: !controller.initialized ? controller.start() : null,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }

            return Column(
              children: <Widget>[
                // TODO: [Leptopoda] make this the actual header
                BlockSemantics(child: _header),
                _board,
                if (LocalDatabaseService
                    .display.isHistoryNavigationToolbarShown)
                  GamePageToolBar(
                    backgroundColor: LocalDatabaseService
                        .colorSettings.navigationToolbarBackgroundColor,
                    itemColor: LocalDatabaseService
                        .colorSettings.navigationToolbarIconColor,
                    children: historyNavToolbar,
                  ),
                GamePageToolBar(
                  backgroundColor: LocalDatabaseService
                      .colorSettings.mainToolbarBackgroundColor,
                  itemColor:
                      LocalDatabaseService.colorSettings.mainToolbarIconColor,
                  children: toolbar,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    logger.i("$_tag dispose");
    controller.dispose();
    _animationController.dispose();
    super.dispose();
  }
}
