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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/engine/analyze.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/engine/native_engine.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/style/toast.dart';
import 'package:stack_trace/stack_trace.dart';

import 'board.dart';

class GamePage extends StatefulWidget {
  //
  static double boardMargin = 10.0, screenPaddingH = 10.0;

  final EngineType engineType;
  final AiEngine engine;

  GamePage(this.engineType) : engine = NativeEngine();

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with RouteAware {
  //
  String _status = '';
  bool _searching = false;

  @override
  void initState() {
    print("Engine type: ${widget.engineType}");

    Game.shared.setWhoIsAi(widget.engineType);

    super.initState();
    Game.shared.init();
    widget.engine.startup();
  }

  changeStatus(String status) {
    if (context == null) {
      //print("[changeStatus] context == null, return");
      return;
    }

    setState(() => _status = status);
  }

  void showTips() {
    if (!mounted || context == null) {
      //print("[showTips] context == null, return");
      return;
    }

    final winner = Game.shared.position.winner;

    Map<String, String> colorWinStrings = {
      PieceColor.black: S.of(context).blackWin,
      PieceColor.white: S.of(context).whiteWin,
      PieceColor.draw: S.of(context).draw
    };

    if (winner == PieceColor.nobody) {
      if (Game.shared.position.phase == Phase.placing) {
        changeStatus(S.of(context).tipPlace);
      } else if (Game.shared.position.phase == Phase.moving) {
        changeStatus(S.of(context).tipMove);
      }
    } else {
      changeStatus(colorWinStrings[winner]);
    }

    showGameResult(winner);
  }

  onBoardTap(BuildContext context, int index) {
    if (Game.shared.engineType == EngineType.testViaLAN) {
      return false;
    }

    final position = Game.shared.position;

    int sq = indexToSquare[index];

    if (sq == null) {
      //print("putPiece skip index: $index");
      return;
    }

    if (Game.shared.isAiToMove() || Game.shared.aiIsSearching()) {
      return false;
    }

    if (position.phase == Phase.ready) {
      Game.shared.start();
    }

    bool ret = false;
    Chain.capture(() {
      switch (position.action) {
        case Act.place:
          if (position.putPiece(sq)) {
            if (position.action == Act.remove) {
              //Audios.playTone('mill.mp3');
              changeStatus(S.of(context).tipRemove);
            } else {
              //Audios.playTone('place.mp3');
              changeStatus(S.of(context).tipPlaced);
            }
            ret = true;
            print("putPiece: [$sq]");
            break;
          } else {
            print("putPiece: skip [$sq]");
            changeStatus(S.of(context).tipBanPlace);
          }

          // If cannot move, retry select, do not break
          //[[fallthrough]];
          continue select;
        select:
        case Act.select:
          if (position.selectPiece(sq)) {
            Audios.playTone('select.mp3');
            Game.shared.select(index);
            ret = true;
            print("selectPiece: [$sq]");
            changeStatus(S.of(context).tipPlace);
          } else {
            Audios.playTone('illegal.mp3');
            print("selectPiece: skip [$sq]");
            changeStatus(S.of(context).tipSelectWrong);
          }
          break;

        case Act.remove:
          if (position.removePiece(sq)) {
            //Audios.playTone('remove.mp3');
            ret = true;
            print("removePiece: [$sq]");
            changeStatus(S.of(context).tipRemoved);
          } else {
            Audios.playTone('illegal.mp3');
            print("removePiece: skip [$sq]");
            changeStatus(S.of(context).tipBanRemove);
          }
          break;

        default:
          break;
      }

      if (ret) {
        Game.shared.sideToMove = position.sideToMove();
        Game.shared.moveHistory.add(position.cmdline);

        // TODO: Need Others?
        // Increment ply counters. In particular, rule50 will be reset to zero later on
        // in case of a capture.
        ++position.gamePly;
        ++position.rule50;
        ++position.pliesFromNull;

        //position.move = m;

        Move m = Move(position.cmdline);
        position.recorder.moveIn(m, position);

        setState(() {});

        if (position.winner == PieceColor.nobody) {
          engineToGo();
        } else {
          showTips();
        }
      }

      Game.shared.sideToMove = position.sideToMove();

      setState(() {});
    });

    return ret;
  }

  engineToGo() async {
    // TODO

    while ((Config.isAutoRestart == true ||
            Game.shared.position.winner == PieceColor.nobody) &&
        Game.shared.isAiToMove() &&
        mounted &&
        context != null) {
      if (widget.engineType == EngineType.aiVsAi) {
        String score = Game.shared.position.score[PieceColor.black].toString() +
            " : " +
            Game.shared.position.score[PieceColor.white].toString() +
            " : " +
            Game.shared.position.score[PieceColor.draw].toString();

        changeStatus(score);
      } else {
        if (context != null) {
          changeStatus(S.of(context).thinking);
        }
      }

      final response = await widget.engine.search(Game.shared.position);
      Chain.capture(() {
        if (response.type == 'move') {
          Move mv = response.value;
          final Move move = new Move(mv.move);

          //Battle.shared.move = move;
          Game.shared.doMove(move.move);
          showTips();
        } else {
          changeStatus('Error: ${response.type}');
        }

        if (Config.isAutoRestart == true &&
            Game.shared.position.winner != PieceColor.nobody) {
          Game.shared.newGame();
        }
      });
    }
  }

  newGame() {
    confirm() {
      Navigator.of(context).pop();
      Game.shared.newGame();
      changeStatus(S.of(context).gameStarted);

      if (Game.shared.isAiToMove()) {
        print("New game, AI to move.");
        engineToGo();
      }
    }

    cancel() => Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).newGame,
              style: TextStyle(color: UIColors.primaryColor)),
          content:
              SingleChildScrollView(child: Text(S.of(context).restartGame)),
          actions: <Widget>[
            TextButton(child: Text(S.of(context).ok), onPressed: confirm),
            TextButton(child: Text(S.of(context).cancel), onPressed: cancel),
          ],
        );
      },
    );
  }

  analyzePosition() async {
    //
    Toast.toast(context,
        msg: S.of(context).analyzing, position: ToastPostion.bottom);

    setState(() => _searching = true);
  }

  showAnalyzeItems(
    BuildContext context, {
    String title,
    List<AnalyzeItem> items,
    Function(AnalyzeItem item) callback,
  }) {
    final List<Widget> children = [];

    for (var item in items) {
      children.add(
        ListTile(
          title: Text(item.moveName, style: TextStyle(fontSize: 18)),
          subtitle: Text(S.of(context).winRate + ": ${item.winRate}%"),
          trailing: Text(S.of(context).score + ": ${item.score}'"),
          onTap: () => callback(item),
        ),
      );
      children.add(Divider());
    }

    children.insert(0, SizedBox(height: 10));
    children.add(SizedBox(height: 56));

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  String getGameOverReasonString(GameOverReason reason, String winner) {
    String loseReasonStr;
    //String winnerStr =
    //    winner == Color.black ? S.of(context).black : S.of(context).white;
    String loserStr =
        winner == PieceColor.black ? S.of(context).white : S.of(context).black;

    switch (Game.shared.position.gameOverReason) {
      case GameOverReason.loseReasonlessThanThree:
        loseReasonStr = loserStr + S.of(context).loseReasonlessThanThree;
        break;
      case GameOverReason.loseReasonResign:
        loseReasonStr = loserStr + S.of(context).loseReasonResign;
        break;
      case GameOverReason.loseReasonNoWay:
        loseReasonStr = loserStr + S.of(context).loseReasonNoWay;
        break;
      case GameOverReason.loseReasonBoardIsFull:
        loseReasonStr = loserStr + S.of(context).loseReasonBoardIsFull;
        break;
      case GameOverReason.loseReasonTimeOver:
        loseReasonStr = loserStr + S.of(context).loseReasonTimeOver;
        break;
      case GameOverReason.drawReasonRule50:
        loseReasonStr = S.of(context).drawReasonRule50;
        break;
      case GameOverReason.drawReasonBoardIsFull:
        loseReasonStr = S.of(context).drawReasonBoardIsFull;
        break;
      case GameOverReason.drawReasonThreefoldRepetition:
        loseReasonStr = S.of(context).drawReasonThreefoldRepetition;
        break;
      default:
        loseReasonStr = S.of(context).gameOverUnknownReason;
        break;
    }

    return loseReasonStr;
  }

  GameResult getGameResult(var winner) {
    if (isAi[PieceColor.black] && isAi[PieceColor.white]) {
      return GameResult.none;
    }

    if (winner == PieceColor.black) {
      if (isAi[PieceColor.black]) {
        return GameResult.lose;
      } else {
        return GameResult.win;
      }
    }

    if (winner == PieceColor.white) {
      if (isAi[PieceColor.white]) {
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

  void showGameResult(var winner) {
    GameResult result = getGameResult(winner);
    Game.shared.position.result = result;

    switch (result) {
      case GameResult.win:
        //Audios.playTone('win.mp3');
        break;
      case GameResult.lose:
        //Audios.playTone('lose.mp3');
        break;
      case GameResult.draw:
        break;
      default:
        break;
    }

    Map<GameResult, String> retMap = {
      GameResult.win: S.of(context).youWin,
      GameResult.lose: S.of(context).youLose,
      GameResult.draw: S.of(context).draw
    };

    var dialogTitle = retMap[result];

    if (dialogTitle == null) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text(dialogTitle, style: TextStyle(color: UIColors.primaryColor)),
          content: Text(getGameOverReasonString(
              Game.shared.position.gameOverReason,
              Game.shared.position.winner)),
          actions: <Widget>[
            TextButton(
                child: Text(S.of(context).ok),
                onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );
  }

  void calcScreenPaddingH() {
    //
    // when screen's height/width rate is less than 16/9, limit witdh of board
    final windowSize = MediaQuery.of(context).size;
    double height = windowSize.height, width = windowSize.width;

    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      GamePage.screenPaddingH =
          (windowSize.width - width) / 2 - GamePage.boardMargin;
    }
  }

  Widget createPageHeader() {
    Map<EngineType, String> engineTypeToString = {
      EngineType.humanVsAi: S.of(context).humanVsAi,
      EngineType.humanVsHuman: S.of(context).humanVsHuman,
      EngineType.aiVsAi: S.of(context).aiVsAi,
      EngineType.humanVsCloud: S.of(context).humanVsCloud,
      EngineType.humanVsLAN: S.of(context).humanVsLAN,
      EngineType.testViaLAN: S.of(context).testViaLAN,
    };

    final titleStyle =
        TextStyle(fontSize: 28, color: UIColors.darkTextPrimaryColor);
    final subTitleStyle =
        TextStyle(fontSize: 16, color: UIColors.darkTextSecondaryColor);

    return Container(
      margin: EdgeInsets.only(top: SanmillApp.StatusBarHeight),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              /*
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: UIColors.darkTextSecondaryColor),
                onPressed: () => Navigator.of(context).pop(),
              ),
               */
              Expanded(child: SizedBox()),
              Text(engineTypeToString[widget.engineType], style: titleStyle),
              Expanded(child: SizedBox()),
              /*
              IconButton(
                icon: Icon(Icons.menu /* more_vert */,
                    color: UIColors.darkTextSecondaryColor),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => SettingsPage()),
                ),
              ),
               */
            ],
          ),
          Container(
            height: 4,
            width: 180,
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Color(Config.boardBackgroundColor),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(_status, maxLines: 1, style: subTitleStyle),
          ),
        ],
      ),
    );
  }

  Widget createBoard() {
    //
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: GamePage.screenPaddingH,
        vertical: GamePage.boardMargin,
      ),
      child: Board(
        width: MediaQuery.of(context).size.width - GamePage.screenPaddingH * 2,
        onBoardTap: onBoardTap,
      ),
    );
  }

  void showSnackbar(String message) {
    var currentScaffold = globalScaffoldKey.currentState;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget createOperatorBar() {
    //
    final buttonStyle = TextStyle(color: UIColors.primaryColor, fontSize: 20);
    final text = Game.shared.position.manualText;

    final manualStyle =
        TextStyle(fontSize: 18, height: 1.5, color: Colors.yellow);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: Color(Config.boardBackgroundColor),
      ),
      margin: EdgeInsets.symmetric(horizontal: GamePage.screenPaddingH),
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(children: <Widget>[
        Expanded(child: SizedBox()),
        IconButton(
            icon: Icon(Icons.motion_photos_on, color: UIColors.secondaryColor),
            onPressed: newGame),
        Expanded(child: SizedBox()),
        IconButton(
          icon: Icon(Icons.restore, color: UIColors.secondaryColor),
          onPressed: () {
            Game.shared.regret(steps: 2);
            setState(() {});
          },
        ),
        Expanded(child: SizedBox()),
        IconButton(
          icon: Icon(Icons.list_alt, color: UIColors.secondaryColor),
          onPressed: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: Colors.transparent,
                title: Text(S.of(context).gameRecord,
                    style: TextStyle(color: Colors.yellow)),
                content: SingleChildScrollView(
                    child: Text(text, style: manualStyle)),
                actions: <Widget>[
                  TextButton(
                    child: Text(S.of(context).copy, style: manualStyle),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: text)).then((_) {
                      showSnackbar(S.of(context).moveHistoryCopied);
                    }),
                  ),
                  TextButton(
                    child: Text(S.of(context).cancel, style: manualStyle),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(child: SizedBox()),
        IconButton(
          icon: Icon(Icons.dashboard_outlined, color: UIColors.secondaryColor),
          onPressed: _searching ? null : analyzePosition,
        ),
        Expanded(child: SizedBox()),
      ]),
    );
  }

  Widget buildManualPanel(String text) {
    //
    final manualStyle = TextStyle(
      fontSize: 18,
      color: UIColors.darkTextSecondaryColor,
      height: 1.5,
    );

    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 16),
        child: SingleChildScrollView(child: Text(text, style: manualStyle)),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context));
  }

  @override
  Widget build(BuildContext context) {
    //
    calcScreenPaddingH();

    final header = createPageHeader();
    final board = createBoard();
    final operatorBar = createOperatorBar();

    return Scaffold(
      backgroundColor: Color(Config.darkBackgroundColor),
      body: Column(children: <Widget>[header, board, operatorBar]),
    );
  }

  @override
  void dispose() {
    widget.engine.shutdown();
    super.dispose();
    routeObserver.unsubscribe(this);
  }

  @override
  void didPush() {
    final route = ModalRoute.of(context).settings.name;
    print('Game Page didPush route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPopNext() {
    final route = ModalRoute.of(context).settings.name;
    print('Game Page didPopNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPushNext() {
    final route = ModalRoute.of(context).settings.name;
    print('Game Page didPushNext route: $route');
    widget.engine.setOptions();
  }

  @override
  void didPop() {
    final route = ModalRoute.of(context).settings.name;
    print('Game Page didPop route: $route');
  }
}
