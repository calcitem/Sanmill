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

import 'package:sanmill/mill/types.dart';

import 'mill.dart';
import 'position.dart';

class Game {
  static Game _instance;

  Position _position;
  int _focusIndex, _blurIndex;

  String sideToMove = Color.black;

  // 是否黑白反转
  bool isColorInverted;

  Map<String, bool> isAi = {Color.black: false, Color.white: true};
  Map<String, bool> isSearching = {Color.black: false, Color.white: false};

  bool aiIsSearching() {
    return isSearching[Color.black] == true || isSearching[Color.white] == true;
  }

  void start() {
    position.start();
  }

  // 是否有落子动画
  bool hasAnimation;

  // 动画持续时间
  int durationTime;

  // 是否有落子音效
  static bool hasSound = true;

  // 是否必败时认输
  bool resignIfMostLose = false;

  // 是否自动交换先后手
  bool isAutoChangeFirstMove = false;

  // AI 是否为先手
  bool isAiFirstMove = false;

  // 规则号
  int ruleIndex;

  // 提示语
  String tips;

  List<String> moveHistory = [""];

  String getTips() => tips;

  bool isAiToMove() {
    return isAi[sideToMove];
  }

  static get shared {
    _instance ??= Game();
    return _instance;
  }

  init() {
    _position = Position();
    _focusIndex = _blurIndex = Move.invalidMove;
  }

  newGame() {
    Game.shared.position.init();
    _focusIndex = _blurIndex = Move.invalidMove;
    moveHistory = [""];
    sideToMove = Color.black;
  }

  select(int pos) {
    _focusIndex = pos;
    _blurIndex = Move.invalidMove;
    //Audios.playTone('click.mp3');
  }

  bool move(int from, int to) {
    //
    position.move(from, to);

    _blurIndex = from;
    _focusIndex = to;

    return true;
  }

  bool regret({moves = 2}) {
    //
    // 轮到自己走棋的时候，才能悔棋
    // TODO
    if (_position.side != Color.white) {
      //Audios.playTone('invalid.mp3');
      return false;
    }

    var regretted = false;

    /// 悔棋一回合（两步），才能撤回自己上一次的动棋

    for (var i = 0; i < moves; i++) {
      //
      if (!_position.regret()) break;

      final lastMove = _position.lastMove;

      if (lastMove != null) {
        //
        _blurIndex = lastMove.from;
        _focusIndex = lastMove.to;
        //
      } else {
        //
        _blurIndex = _focusIndex = Move.invalidMove;
      }

      regretted = true;
    }

    if (regretted) {
      //Audios.playTone('regret.mp3');
      return true;
    }

    //Audios.playTone('invalid.mp3');
    return false;
  }

  clear() {
    _blurIndex = _focusIndex = Move.invalidMove;
  }

  GameResult scanBattleResult() {
    //
    final forPerson = (_position.side == Color.white);

    if (scanLongCatch()) {
      // born 'repeat' position by oppo
      return forPerson ? GameResult.win : GameResult.lose;
    }

    return (_position.halfMove > 120) ? GameResult.draw : GameResult.pending;
  }

  scanLongCatch() {
    // todo:
    return false;
  }

  get position => _position;

  get focusIndex => _focusIndex;

  get blurIndex => _blurIndex;

  bool command(String cmd) {
    int total;
    double blackWinRate, whiteWinRate, drawRate;

    // 如果未开局则开局
    if (position.phase == Phase.ready) {
      start();
    }

    print("Computer: $cmd");

    moveHistory.add(cmd);

    if (!position.command(cmd)) {
      return false;
    }

    sideToMove = position.sideToMove();

    total = position.score[Color.black] +
        position.score[Color.white] +
        position.score[Color.draw];

    if (total == 0) {
      blackWinRate = 0;
      whiteWinRate = 0;
      drawRate = 0;
    } else {
      blackWinRate = position.score[Color.black] * 100 / total;
      whiteWinRate = position.score[Color.white] * 100 / total;
      drawRate = position.score[Color.draw] * 100 / total;
    }

    String stat = "Score: " +
        position.score[Color.black].toString() +
        " : " +
        position.score[Color.white].toString() +
        " : " +
        position.score[Color.draw].toString() +
        "\ttotal: " +
        total.toString() +
        "\n" +
        blackWinRate.toString() +
        "% : " +
        whiteWinRate.toString() +
        "% : " +
        drawRate.toString() +
        "%" +
        "\n";

    print(stat);
    return true;
  }
}
