/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/engine/analyze.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/engine/native_engine.dart';
import 'package:sanmill/main.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/player.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/style/toast.dart';

import 'board.dart';
import 'settings_page.dart';

class GamePage extends StatefulWidget {
  //
  static double boardMargin = 10.0, screenPaddingH = 10.0;

  final EngineType engineType;
  final AiEngine engine;

  GamePage(this.engineType) : engine = NativeEngine();

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  //
  String _status = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    Game.shared.init();
    widget.engine.startup();
  }

  changeStatus(String status) => setState(() => _status = status);

  void showTips() {
    final winner = Game.shared.position.winner;

    switch (winner) {
      case Color.nobody:
        if (Game.shared.position.phase == Phase.placing) {
          changeStatus('请摆子');
        } else if (Game.shared.position.phase == Phase.moving) {
          changeStatus('请走子');
        }
        break;
      case Color.black:
        changeStatus('黑方胜');
        gotWin();
        break;
      case Color.white:
        changeStatus('白方胜');
        gotLose();
        break;
      case Color.draw:
        changeStatus('和棋');
        gotDraw();
        break;
    }
  }

  onBoardTap(BuildContext context, int index) {
    final position = Game.shared.position;

    int sq = indexToSquare[index];

    // 点击非落子点，不执行
    if (sq == null) {
      print("putPiece skip index: $index");
      return;
    }

    // AI 走棋或正在搜索时，点击无效
    if (Game.shared.isAiToMove() || Game.shared.aiIsSearching()) {
      return false;
    }

    // 如果未开局则开局
    if (position.phase == Phase.ready) {
      Game.shared.start();
    }

    // 判断执行选子、落子或去子
    bool ret = false;

    switch (position.action) {
      case Act.place:
        if (position.putPiece(sq)) {
          if (position.action == Act.remove) {
            // 播放成三音效
            //Audios.playTone('mill.mp3');
            changeStatus('请吃子');
          } else {
            // 播放移动棋子音效
            //Audios.playTone('put.mp3');
            changeStatus('已落子');
          }
          ret = true;
          print("putPiece: [$sq]");
          break;
        } else {
          print("putPiece: skip [$sq]");
          changeStatus('不能落在此处');
        }

        // 如果移子不成功，尝试重新选子，这里不break
        //[[fallthrough]];
        continue select;
      select:
      case Act.select:
        if (position.selectPiece(sq)) {
          // 播放选子音效
          //Audios.playTone('select.mp3');
          Game.shared.select(index);
          ret = true;
          print("selectPiece: [$sq]");
          changeStatus('请落子');
        } else {
          // 播放禁止音效
          //Audios.playTone('banned.mp3');
          print("selectPiece: skip [$sq]");
          changeStatus('选择的子不对');
        }
        break;

      case Act.remove:
        if (position.removePiece(sq)) {
          // 播放音效
          //Audios.playTone('remove.mp3');
          ret = true;
          print("removePiece: [$sq]");
          changeStatus('已吃子');
        } else {
          // 播放禁止音效
          //Audios.playTone('banned.mp3');
          print("removePiece: skip [$sq]");
          changeStatus('不能吃这个子');
        }
        break;

      default:
        // 如果是结局状态，不做任何响应
        break;
    }

    if (ret) {
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

      // 发信号更新状态栏
      setState(() {});

      // AI设置
      // 如果还未决出胜负
      if (position.winner == Color.nobody) {
        engineToGo();
      } else {
        showTips();
      }
    }

    Game.shared.sideToMove = position.sideToMove();

    setState(() {});

    return ret;
  }

  engineToGo() async {
    // TODO
    while (Game.shared.position.sideToMove() == Color.white) {
      changeStatus('对方思考中...');

      final response = await widget.engine.search(Game.shared.position);

      if (response.type == 'move') {
        Move mv = response.value;
        final Move move = new Move(mv.move);

        //Battle.shared.move = move;
        Game.shared.doMove(move.move);
        showTips();
      } else {
        changeStatus('Error: ${response.type}');
      }
    }
  }

  newGame() {
    confirm() {
      Navigator.of(context).pop();
      Game.shared.newGame();
      changeStatus('新游戏');

      if (Game.shared.isAiToMove()) {
        print("New Game: AI's turn.");
        engineToGo();
      }
    }

    cancel() => Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('新局？', style: TextStyle(color: UIColors.primaryColor)),
          content: SingleChildScrollView(child: Text('开始新局？')),
          actions: <Widget>[
            FlatButton(child: Text('确定'), onPressed: confirm),
            FlatButton(child: Text('取消'), onPressed: cancel),
          ],
        );
      },
    );
  }

  analyzePosition() async {
    //
    Toast.toast(context, msg: '正在分析局面...', position: ToastPostion.bottom);

    setState(() => _searching = true);

    try {} catch (e) {
      Toast.toast(context, msg: '错误: $e', position: ToastPostion.bottom);
    } finally {
      setState(() => _searching = false);
    }
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
          subtitle: Text('胜率：${item.winRate}%'),
          trailing: Text('分数：${item.score}'),
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

  void gotWin() {
    //
    Game.shared.position.result = GameResult.win;
    //Audios.playTone('win.mp3');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('赢了', style: TextStyle(color: UIColors.primaryColor)),
          content: Text('恭喜您取得了伟大的胜利！'),
          actions: <Widget>[
            FlatButton(child: Text('再来一盘'), onPressed: newGame),
            FlatButton(
                child: Text('关闭'),
                onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );

    if (widget.engineType == EngineType.Cloud)
      Player.shared.increaseWinCloudEngine();
    else
      Player.shared.increaseWinAi();
  }

  void gotLose() {
    //
    Game.shared.position.result = GameResult.lose;
    //Audios.playTone('lose.mp3');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('输了', style: TextStyle(color: UIColors.primaryColor)),
          content: Text('勇士！坚定战斗，虽败犹荣！'),
          actions: <Widget>[
            FlatButton(child: Text('再来一盘'), onPressed: newGame),
            FlatButton(
                child: Text('关闭'),
                onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );
  }

  void gotDraw() {
    //
    Game.shared.position.result = GameResult.draw;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('和棋', style: TextStyle(color: UIColors.primaryColor)),
          content: Text('您用自己的力量捍卫了和平！'),
          actions: <Widget>[
            FlatButton(child: Text('再来一盘'), onPressed: newGame),
            FlatButton(
                child: Text('关闭'),
                onPressed: () => Navigator.of(context).pop()),
          ],
        );
      },
    );
  }

  void calcScreenPaddingH() {
    //
    // 当屏幕的纵横比小于16/9时，限制棋盘的宽度
    final windowSize = MediaQuery.of(context).size;
    double height = windowSize.height, width = windowSize.width;

    if (height / width < 16.0 / 9.0) {
      width = height * 9 / 16;
      GamePage.screenPaddingH =
          (windowSize.width - width) / 2 - GamePage.boardMargin;
    }
  }

  Widget createPageHeader() {
    //
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
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: UIColors.darkTextPrimaryColor),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(child: SizedBox()),
              Hero(tag: 'logo', child: Image.asset('images/logo-mini.png')),
              SizedBox(width: 10),
              Text(widget.engineType == EngineType.Cloud ? '挑战云主机' : '人机对战',
                  style: titleStyle),
              Expanded(child: SizedBox()),
              IconButton(
                icon:
                    Icon(Icons.settings, color: UIColors.darkTextPrimaryColor),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => SettingsPage()),
                ),
              ),
            ],
          ),
          Container(
            height: 4,
            width: 180,
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: UIColors.boardBackgroundColor,
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

  Widget createOperatorBar() {
    //
    final buttonStyle = TextStyle(color: UIColors.primaryColor, fontSize: 20);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: UIColors.boardBackgroundColor,
      ),
      margin: EdgeInsets.symmetric(horizontal: GamePage.screenPaddingH),
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(children: <Widget>[
        Expanded(child: SizedBox()),
        FlatButton(child: Text('新局', style: buttonStyle), onPressed: newGame),
        Expanded(child: SizedBox()),
        FlatButton(
          child: Text('悔棋', style: buttonStyle),
          onPressed: () {
            Game.shared.regret(steps: 2);
            setState(() {});
          },
        ),
        Expanded(child: SizedBox()),
        FlatButton(
          child: Text('分析', style: buttonStyle),
          onPressed: _searching ? null : analyzePosition,
        ),
        Expanded(child: SizedBox()),
      ]),
    );
  }

  Widget buildFooter() {
    //
    final size = MediaQuery.of(context).size;

    final manualText = Game.shared.position.manualText;

    if (size.height / size.width > 16 / 9) {
      return buildManualPanel(manualText);
    } else {
      return buildExpandableRecordPanel(manualText);
    }
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

  Widget buildExpandableRecordPanel(String text) {
    //
    final manualStyle = TextStyle(fontSize: 18, height: 1.5);

    return Expanded(
      child: IconButton(
        icon: Icon(Icons.expand_less, color: UIColors.darkTextPrimaryColor),
        onPressed: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('棋谱', style: TextStyle(color: UIColors.primaryColor)),
              content:
                  SingleChildScrollView(child: Text(text, style: manualStyle)),
              actions: <Widget>[
                FlatButton(
                  child: Text('好的'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    //
    calcScreenPaddingH();

    final header = createPageHeader();
    final board = createBoard();
    final operatorBar = createOperatorBar();
    final footer = buildFooter();

    return Scaffold(
      backgroundColor: UIColors.darkBackgroundColor,
      body: Column(children: <Widget>[header, board, operatorBar, footer]),
    );
  }

  @override
  void dispose() {
    widget.engine.shutdown();
    super.dispose();
  }
}
