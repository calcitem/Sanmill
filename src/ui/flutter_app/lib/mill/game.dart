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

import 'position.dart';
import 'types.dart';

enum PlayerType { human, AI }
Map<String, bool> isAi = {PieceColor.white: false, PieceColor.black: true};

class Game {
  static Game? _instance;
  final String tag = "[game]";

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
    sideToMove = PieceColor.white;
  }

  String sideToMove = PieceColor.white;

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
    PieceColor.white: false,
    PieceColor.black: false
  };

  bool aiIsSearching() {
    print("$tag White is searching? ${isSearching[PieceColor.white]}\n"
        "$tag Black is searching? ${isSearching[PieceColor.black]}\n");

    return isSearching[PieceColor.white] == true ||
        isSearching[PieceColor.black] == true;
  }

  EngineType engineType = EngineType.none;

  void setWhoIsAi(EngineType type) {
    engineType = type;

    switch (type) {
      case EngineType.humanVsAi:
      case EngineType.testViaLAN:
        isAi[PieceColor.white] = Config.aiMovesFirst;
        isAi[PieceColor.black] = !Config.aiMovesFirst;
        break;
      case EngineType.humanVsHuman:
      case EngineType.humanVsLAN:
      case EngineType.humanVsCloud:
        isAi[PieceColor.white] = isAi[PieceColor.black] = false;
        break;
      case EngineType.aiVsAi:
        isAi[PieceColor.white] = isAi[PieceColor.black] = true;
        break;
      default:
        break;
    }

    print("$tag White is AI? ${isAi[PieceColor.white]}\n"
        "$tag Black is AI? ${isAi[PieceColor.black]}\n");
  }

  select(int pos) {
    _focusIndex = pos;
    _blurIndex = invalidIndex;
  }

  bool doMove(String move) {
    if (position.phase == Phase.ready) {
      start();
    }

    print("$tag AI do move: $move");

    if (!position.doMove(move)) {
      return false;
    }

    moveHistory.add(move);

    sideToMove = position.sideToMove() ?? PieceColor.nobody;

    printStat();

    return true;
  }

  printStat() {
    double whiteWinRate = 0;
    double blackWinRate = 0;
    double drawRate = 0;

    int total = position.score[PieceColor.white] +
            position.score[PieceColor.black] +
            position.score[PieceColor.draw] ??
        0;

    if (total == 0) {
      whiteWinRate = 0;
      blackWinRate = 0;
      drawRate = 0;
    } else {
      whiteWinRate = position.score[PieceColor.white] * 100 / total ?? 0;
      blackWinRate = position.score[PieceColor.black] * 100 / total ?? 0;
      drawRate = position.score[PieceColor.draw] * 100 / total ?? 0;
    }

    String scoreInfo = "Score: " +
        position.score[PieceColor.white].toString() +
        " : " +
        position.score[PieceColor.black].toString() +
        " : " +
        position.score[PieceColor.draw].toString() +
        "\ttotal: " +
        total.toString() +
        "\n" +
        whiteWinRate.toString() +
        "% : " +
        blackWinRate.toString() +
        "% : " +
        drawRate.toString() +
        "%" +
        "\n";

    print("$tag $scoreInfo");
  }
}
