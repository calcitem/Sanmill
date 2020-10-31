import '../mill/mill-base.dart';
import '../common/color-consts.dart';
import '../common/toast.dart';
import '../engine/analysis.dart';
import '../engine/engine.dart';
import '../engine/native-engine.dart';
//import '../services/audios.dart';
import '../services/player.dart';
import 'package:flutter/material.dart';
import '../game/battle.dart';
import '../board/board-widget.dart';
import '../main.dart';
import 'settings-page.dart';

class BattlePage extends StatefulWidget {
  //
  static double boardMargin = 10.0, screenPaddingH = 10.0;

  final EngineType engineType;
  final AiEngine engine;

  BattlePage(this.engineType) : engine = NativeEngine();

  @override
  _BattlePageState createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  //
  String _status = '';
  bool _analysising = false;

  @override
  void initState() {
    //
    super.initState();
    Battle.shared.init();

    widget.engine.startup();
  }

  changeStatus(String status) => setState(() => _status = status);

  onBoardTap(BuildContext context, int index) {
    //
    final position = Battle.shared.position;

    // 仅 Position 中的 side 指示一方能动棋
    if (position.side != Side.White) return;

    final tapedPiece = position.pieceAt(index);

    // 之前已经有棋子被选中了
    if (Battle.shared.focusIndex != Move.InvalidIndex &&
        Side.of(position.pieceAt(Battle.shared.focusIndex)) == Side.White) {
      //
      // 当前点击的棋子和之前已经选择的是同一个位置
      if (Battle.shared.focusIndex == index) return;

      // 之前已经选择的棋子和现在点击的棋子是同一边的，说明是选择另外一个棋子
      final focusPiece = position.pieceAt(Battle.shared.focusIndex);

      if (Side.sameSide(focusPiece, tapedPiece)) {
        //
        Battle.shared.select(index);
        //
      } else if (Battle.shared.move(Battle.shared.focusIndex, index)) {
        // 现在点击的棋子和上一次选择棋子不同边，要么是吃子，要么是移动棋子到空白处
        final result = Battle.shared.scanBattleResult();

        switch (result) {
          case BattleResult.Pending:
            engineToGo();
            break;
          case BattleResult.Win:
            gotWin();
            break;
          case BattleResult.Lose:
            gotLose();
            break;
          case BattleResult.Draw:
            gotDraw();
            break;
        }
      }
      //
    } else {
      // 之前未选择棋子，现在点击就是选择棋子
      if (tapedPiece != Piece.Empty) Battle.shared.select(index);
    }

    setState(() {});
  }

  engineToGo() async {
    //
    changeStatus('对方思考中...');

    final response = await widget.engine.search(Battle.shared.position);

    if (response.type == 'move') {
      //
      final step = response.value;
      Battle.shared.move(step.from, step.to);

      final result = Battle.shared.scanBattleResult();

      switch (result) {
        case BattleResult.Pending:
          changeStatus('请走棋...');
          break;
        case BattleResult.Win:
          gotWin();
          break;
        case BattleResult.Lose:
          gotLose();
          break;
        case BattleResult.Draw:
          gotDraw();
          break;
      }
      //
    } else {
      //
      changeStatus('Error: ${response.type}');
    }
  }

  newGame() {
    //
    confirm() {
      Navigator.of(context).pop();
      Battle.shared.newGame();
      setState(() {});
    }

    cancel() => Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('放弃对局？', style: TextStyle(color: ColorConsts.Primary)),
          content: SingleChildScrollView(child: Text('你确定要放弃当前的对局吗？')),
          actions: <Widget>[
            FlatButton(child: Text('确定'), onPressed: confirm),
            FlatButton(child: Text('取消'), onPressed: cancel),
          ],
        );
      },
    );
  }

  analysisPosition() async {
    //
    Toast.toast(context, msg: '正在分析局面...', position: ToastPostion.bottom);

    setState(() => _analysising = true);

    try {} catch (e) {
      Toast.toast(context, msg: '错误: $e', position: ToastPostion.bottom);
    } finally {
      setState(() => _analysising = false);
    }
  }

  showAnalysisItems(
    BuildContext context, {
    String title,
    List<AnalysisItem> items,
    Function(AnalysisItem item) callback,
  }) {
    //
    final List<Widget> children = [];

    for (var item in items) {
      children.add(
        ListTile(
          title: Text(item.stepName, style: TextStyle(fontSize: 18)),
          subtitle: Text('胜率：${item.winrate}%'),
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
    Battle.shared.position.result = BattleResult.Win;
    //Audios.playTone('win.mp3');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('赢了', style: TextStyle(color: ColorConsts.Primary)),
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
      Player.shared.increaseWinPhoneAi();
  }

  void gotLose() {
    //
    Battle.shared.position.result = BattleResult.Lose;
    //Audios.playTone('lose.mp3');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('输了', style: TextStyle(color: ColorConsts.Primary)),
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
    Battle.shared.position.result = BattleResult.Draw;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('和���', style: TextStyle(color: ColorConsts.Primary)),
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
      BattlePage.screenPaddingH =
          (windowSize.width - width) / 2 - BattlePage.boardMargin;
    }
  }

  Widget createPageHeader() {
    //
    final titleStyle =
        TextStyle(fontSize: 28, color: ColorConsts.DarkTextPrimary);
    final subTitleStyle =
        TextStyle(fontSize: 16, color: ColorConsts.DarkTextSecondary);

    return Container(
      margin: EdgeInsets.only(top: SanmillApp.StatusBarHeight),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                icon:
                    Icon(Icons.arrow_back, color: ColorConsts.DarkTextPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(child: SizedBox()),
              Hero(tag: 'logo', child: Image.asset('images/logo-mini.png')),
              SizedBox(width: 10),
              Text(widget.engineType == EngineType.Cloud ? '挑战云主机' : '人机对战',
                  style: titleStyle),
              Expanded(child: SizedBox()),
              IconButton(
                icon: Icon(Icons.settings, color: ColorConsts.DarkTextPrimary),
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
              color: ColorConsts.BoardBackground,
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
        horizontal: BattlePage.screenPaddingH,
        vertical: BattlePage.boardMargin,
      ),
      child: BoardWidget(
        width:
            MediaQuery.of(context).size.width - BattlePage.screenPaddingH * 2,
        onBoardTap: onBoardTap,
      ),
    );
  }

  Widget createOperatorBar() {
    //
    final buttonStyle = TextStyle(color: ColorConsts.Primary, fontSize: 20);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: ColorConsts.BoardBackground,
      ),
      margin: EdgeInsets.symmetric(horizontal: BattlePage.screenPaddingH),
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(children: <Widget>[
        Expanded(child: SizedBox()),
        FlatButton(child: Text('新对局', style: buttonStyle), onPressed: newGame),
        Expanded(child: SizedBox()),
        FlatButton(
          child: Text('悔棋', style: buttonStyle),
          onPressed: () {
            Battle.shared.regret(steps: 2);
            setState(() {});
          },
        ),
        Expanded(child: SizedBox()),
        FlatButton(
          child: Text('分析局面', style: buttonStyle),
          onPressed: _analysising ? null : analysisPosition,
        ),
        Expanded(child: SizedBox()),
      ]),
    );
  }

  Widget buildFooter() {
    //
    final size = MediaQuery.of(context).size;

    final manualText = Battle.shared.position.manualText;

    if (size.height / size.width > 16 / 9) {
      return buildManualPanel(manualText);
    } else {
      return buildExpandableManaulPanel(manualText);
    }
  }

  Widget buildManualPanel(String text) {
    //
    final manualStyle = TextStyle(
      fontSize: 18,
      color: ColorConsts.DarkTextSecondary,
      height: 1.5,
    );

    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 16),
        child: SingleChildScrollView(child: Text(text, style: manualStyle)),
      ),
    );
  }

  Widget buildExpandableManaulPanel(String text) {
    //
    final manualStyle = TextStyle(fontSize: 18, height: 1.5);

    return Expanded(
      child: IconButton(
        icon: Icon(Icons.expand_less, color: ColorConsts.DarkTextPrimary),
        onPressed: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('棋谱', style: TextStyle(color: ColorConsts.Primary)),
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
      backgroundColor: ColorConsts.DarkBackground,
      body: Column(children: <Widget>[header, board, operatorBar, footer]),
    );
  }

  @override
  void dispose() {
    widget.engine.shutdown();
    super.dispose();
  }
}
