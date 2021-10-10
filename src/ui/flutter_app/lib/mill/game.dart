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

import 'package:flutter/foundation.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/engine/engine.dart';
import 'package:sanmill/shared/common/config.dart';

enum PlayerType { human, AI }
Map<String, bool> isAi = {PieceColor.white: false, PieceColor.black: true};

// TODO: add constructor
Game gameInstance = Game();

class Game {
  final String tag = "[game]";

  void init() {
    _position = Position();
    focusIndex = blurIndex = invalidIndex;
  }

  void start() {
    position.reset();

    setWhoIsAi(engineType);
  }

  void newGame() {
    position.phase = Phase.ready;
    start();
    position.init();
    focusIndex = blurIndex = invalidIndex;
    moveHistory = [""];
    sideToMove = PieceColor.white;
  }

  String sideToMove = PieceColor.white;

  bool get isAiToMove {
    assert(sideToMove == PieceColor.white || sideToMove == PieceColor.black);
    return isAi[sideToMove]!;
  }

  List<String> moveHistory = [""];

  Position _position = Position();
  Position get position => _position;

  int focusIndex = invalidIndex;
  int blurIndex = invalidIndex;

  Map<String, bool> isSearching = {
    PieceColor.white: false,
    PieceColor.black: false
  };

  bool aiIsSearching() {
    debugPrint(
      "$tag White is searching? ${isSearching[PieceColor.white]}\n"
      "$tag Black is searching? ${isSearching[PieceColor.black]}\n",
    );

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

    debugPrint(
      "$tag White is AI? ${isAi[PieceColor.white]}\n"
      "$tag Black is AI? ${isAi[PieceColor.black]}\n",
    );
  }

  void select(int pos) {
    focusIndex = pos;
    blurIndex = invalidIndex;
  }

  bool doMove(String move) {
    if (position.phase == Phase.ready) {
      start();
    }

    debugPrint("$tag AI do move: $move");

    if (!position.doMove(move)) {
      return false;
    }

    moveHistory.add(move);

    sideToMove = position.sideToMove;

    printStat();

    return true;
  }

  void printStat() {
    double whiteWinRate = 0;
    double blackWinRate = 0;
    double drawRate = 0;

    final int total = position.score[PieceColor.white]! +
        position.score[PieceColor.black]! +
        position.score[PieceColor.draw]!;

    if (total != 0) {
      whiteWinRate = position.score[PieceColor.white]! * 100 / total;
      blackWinRate = position.score[PieceColor.black]! * 100 / total;
      drawRate = position.score[PieceColor.draw]! * 100 / total;
    }

    final String scoreInfo =
        "Score: ${position.score[PieceColor.white]} : ${position.score[PieceColor.black]} : ${position.score[PieceColor.draw]}\ttotal: $total\n$whiteWinRate% : $blackWinRate% : $drawRate%\n";

    debugPrint("$tag $scoreInfo");
  }
}
