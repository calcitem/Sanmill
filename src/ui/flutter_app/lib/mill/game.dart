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

import 'mill.dart';
import 'position.dart';
import 'types.dart';

enum PlayerType { human, AI }
Map<String, bool> isAi = {PieceColor.black: false, PieceColor.white: true};

class Game {
  static Game? _instance;

  static get instance {
    _instance ??= Game();
    return _instance;
  }

  init() {
    _position = Position();
    _focusIndex = _blurIndex = invalidIndex;
  }

  start() {
    position.reset();

    setWhoIsAi(engineType);
  }

  newGame() {
    position.phase = Phase.ready;
    start();
    position.init();
    _focusIndex = _blurIndex = invalidIndex;
    moveHistory = [""];
    sideToMove = PieceColor.black;
  }

  String sideToMove = PieceColor.black;

  bool? isAiToMove() {
    return isAi[sideToMove];
  }

  List<String> moveHistory = [""];

  Position _position = Position();
  get position => _position;

  int _focusIndex = invalidIndex;
  int _blurIndex = invalidIndex;

  get focusIndex => _focusIndex;
  set focusIndex(index) => _focusIndex = index;

  get blurIndex => _blurIndex;
  set blurIndex(index) => _blurIndex = index;

  Map<String, bool> isSearching = {
    PieceColor.black: false,
    PieceColor.white: false
  };

  bool aiIsSearching() {
    return isSearching[PieceColor.black] == true ||
        isSearching[PieceColor.white] == true;
  }

  EngineType engineType = EngineType.none;

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
      case EngineType.humanVsCloud:
        isAi[PieceColor.black] = isAi[PieceColor.white] = false;
        break;
      case EngineType.aiVsAi:
        isAi[PieceColor.black] = isAi[PieceColor.white] = true;
        break;
      default:
        break;
    }
  }

  select(int pos) {
    _focusIndex = pos;
    _blurIndex = invalidIndex;
  }

  bool doMove(String move) {
    if (position.phase == Phase.ready) {
      start();
    }

    print("Computer: $move");

    if (!position.doMove(move)) {
      return false;
    }

    moveHistory.add(move);

    sideToMove = position.sideToMove() ?? PieceColor.nobody;

    printStat();

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
        _blurIndex = lastMove.from ?? invalidIndex;
        _focusIndex = lastMove.to ?? invalidIndex;
        //
      } else {
        //
        _blurIndex = _focusIndex = invalidIndex;
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

  printStat() {
    double blackWinRate = 0;
    double whiteWinRate = 0;
    double drawRate = 0;

    int total = position.score[PieceColor.black] +
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

    String scoreInfo = "Score: " +
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

    print(scoreInfo);
  }
}
