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

import 'package:sanmill/common/config.dart';
import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/mill/types.dart';

import 'mill.dart';
import 'position.dart';

enum PlayerType { human, AI }
Map<String, bool> isAi = {PieceColor.black: false, PieceColor.white: true};

class Game {
  static Game _instance;

  Position _position = Position();
  int _focusIndex = Move.invalidMove;
  int _blurIndex = Move.invalidMove;

  String sideToMove = PieceColor.black;

  bool isColorInverted = false;

  Map<String, bool> isSearching = {
    PieceColor.black: false,
    PieceColor.white: false
  };

  EngineType engineType = EngineType.none;

  bool aiIsSearching() {
    return isSearching[PieceColor.black] == true ||
        isSearching[PieceColor.white] == true;
  }

  void setWhoIsAi(EngineType type) {
    engineType = type;

    switch (type) {
      case EngineType.humanVsAi:
      case EngineType.testViaLAN:
        isAi[PieceColor.black] = Config.aiMovesFirst;
        isAi[PieceColor.white] = !Config.aiMovesFirst;
        break;
      case EngineType.humanVsHuman:
      case EngineType.humanVsLAN:
        isAi[PieceColor.black] = isAi[PieceColor.white] = false;
        break;
      case EngineType.aiVsAi:
        isAi[PieceColor.black] = isAi[PieceColor.white] = true;
        break;
      case EngineType.humanVsCloud:
        break;
      default:
        break;
    }
  }

  void start() {
    position.reset();

    setWhoIsAi(engineType);
  }

  // TODO
  bool hasAnimation = true;
  // TODO
  int animationDurationTime = 1;

  static bool hasSound = true;

  bool resignIfMostLose = false;

  bool isAutoChangeFirstMove = false;

  bool isAiFirstMove = false;

  // TODO
  int ruleIndex = 0;
  // TODO
  String tips = "";

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
    Game.shared.position.phase = Phase.ready;
    Game.shared.start();
    Game.shared.position.init();
    _focusIndex = _blurIndex = Move.invalidMove;
    moveHistory = [""];
    // TODO
    sideToMove = PieceColor.black;
  }

  select(int pos) {
    _focusIndex = pos ?? Move.invalidMove;
    _blurIndex = Move.invalidMove;
    //Audios.playTone('click.mp3');
  }

  bool move(int from, int to) {
    //
    position.move(from, to);

    return true;
  }

  bool regret({moves = 2}) {
    //
    // Can regret only our turn
    // TODO
    if (_position.side != PieceColor.white) {
      //Audios.playTone('invalid.mp3');
      return false;
    }

    var regretted = false;

    /// Regret 2 step

    for (var i = 0; i < moves; i++) {
      //
      if (!_position.regret()) break;

      final lastMove = _position.lastMove;

      if (lastMove != null) {
        //
        _blurIndex = lastMove.from ?? Move.invalidMove;
        _focusIndex = lastMove.to ?? Move.invalidMove;
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

  get position => _position;

  get focusIndex => _focusIndex;
  set focusIndex(index) => _focusIndex = index;

  get blurIndex => _blurIndex;
  set blurIndex(index) => _blurIndex = index;

  bool doMove(String move) {
    int total = 0;
    double blackWinRate = 0;
    double whiteWinRate = 0;
    double drawRate = 0;

    if (position.phase == Phase.ready) {
      start();
    }

    print("Computer: $move");

    moveHistory.add(move);

    if (!position.doMove(move)) {
      return false;
    }

    sideToMove = position.sideToMove() ?? PieceColor.nobody;

    total = position.score[PieceColor.black] +
            position.score[PieceColor.white] +
            position.score[PieceColor.draw] ??
        0;

    if (total == 0) {
      blackWinRate = 0;
      whiteWinRate = 0;
      drawRate = 0;
    } else {
      blackWinRate = position.score[PieceColor.black] * 100 / total ?? 0;
      whiteWinRate = position.score[PieceColor.white] * 100 / total ?? 0;
      drawRate = position.score[PieceColor.draw] * 100 / total ?? 0;
    }

    String stat = "Score: " +
        position.score[PieceColor.black].toString() +
        " : " +
        position.score[PieceColor.white].toString() +
        " : " +
        position.score[PieceColor.draw].toString() +
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
