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

import '../mill/mill.dart';
import '../mill/position.dart';

class Battle {
  //
  static Battle _instance;

  Position _position;
  int _focusIndex, _blurIndex;

  String sideToMove;

  // 是否黑白反转
  bool isInverted;

  Map<String, bool> isAiPlayer = {Color.black: false, Color.white: false};

  // 是否有落子动画
  bool hasAnimation;

  // 动画持续时间
  int durationTime;

  // 是否有落子音效
  static bool hasSound = true;

  // 是否必败时认输
  bool resignIfMostLose_ = false;

  // 是否自动交换先后手
  bool isAutoChangeFirstMove = false;

  // AI 是否为先手
  bool isAiFirstMove = false;

  // 规则号
  int ruleIndex;

  // 提示语
  String tips;

  List<String> cmdlist;

  String getTips() => tips;

  static get shared {
    _instance ??= Battle();
    return _instance;
  }

  init() {
    _position = Position.init();
    _focusIndex = _blurIndex = Move.invalidValue;
  }

  newGame() {
    Battle.shared.position.init();
    _focusIndex = _blurIndex = Move.invalidValue;
  }

  select(int pos) {
    _focusIndex = pos;
    _blurIndex = Move.invalidValue;
    //Audios.playTone('click.mp3');
  }

  bool regret({steps = 2}) {
    //
    // 轮到自己走棋的时候，才能悔棋
    if (_position.side != Color.white) {
      //Audios.playTone('invalid.mp3');
      return false;
    }

    var regreted = false;

    /// 悔棋一回合（两步），才能撤回自己上一次的动棋

    for (var i = 0; i < steps; i++) {
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
        _blurIndex = _focusIndex = Move.invalidValue;
      }

      regreted = true;
    }

    if (regreted) {
      //Audios.playTone('regret.mp3');
      return true;
    }

    //Audios.playTone('invalid.mp3');
    return false;
  }

  clear() {
    _blurIndex = _focusIndex = Move.invalidValue;
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
}
