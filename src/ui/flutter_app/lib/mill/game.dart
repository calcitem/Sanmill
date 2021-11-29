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
import 'package:sanmill/services/storage/storage.dart';

// TODO: [Leptopoda] add constructor
Game gameInstance = Game();

class Game {
  static const String _tag = "[game]";

  void init() {
    // TODO: [Leptopoda] _position is already initialized with Position(). seems like duplicate code
    _position = Position();
    focusIndex = blurIndex = null;
  }

  void start() {
    position.reset();

    setWhoIsAi(engineType);
  }

  void newGame() {
    position.phase = Phase.ready;
    start();

    position.restart();
    focusIndex = blurIndex = null;

    moveHistory = [""];
    sideToMove = PieceColor.white;
  }

  PieceColor sideToMove = PieceColor.white;

  bool get isAiToMove {
    assert(sideToMove == PieceColor.white || sideToMove == PieceColor.black);
    return isAi[sideToMove]!;
  }

  // TODO: [Leptopoda] make the move historry a seperate class
  List<String?> moveHistory = [];

  Position _position = Position();
  Position get position => _position;

  int? focusIndex;
  int? blurIndex;

  final Map<PieceColor, bool> isAi = {
    PieceColor.white: false,
    PieceColor.black: true,
  };

  final Map<PieceColor, bool> _isSearching = {
    PieceColor.white: false,
    PieceColor.black: false
  };

  // TODO: [Leptopoda] this is very suspicious.
  //[_isSearching] is private and only used by it's getter. Seems like this is somehow redundant ...
  bool get aiIsSearching {
    debugPrint(
      "$_tag White is searching? ${_isSearching[PieceColor.white]}\n"
      "$_tag Black is searching? ${_isSearching[PieceColor.black]}\n",
    );

    return _isSearching[PieceColor.white]! || _isSearching[PieceColor.black]!;
  }

  EngineType engineType = EngineType.none;

  void setWhoIsAi(EngineType type) {
    engineType = type;

    switch (type) {
      case EngineType.humanVsAi:
      case EngineType.testViaLAN:
        isAi[PieceColor.white] = LocalDatabaseService.preferences.aiMovesFirst;
        isAi[PieceColor.black] = !LocalDatabaseService.preferences.aiMovesFirst;
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
        assert(false);
    }

    debugPrint(
      "$_tag White is AI? ${isAi[PieceColor.white]}\n"
      "$_tag Black is AI? ${isAi[PieceColor.black]}\n",
    );
  }

  void select(int pos) {
    focusIndex = pos;
    blurIndex = null;
  }

  Future<bool> doMove(String move) async {
    if (position.phase == Phase.ready) {
      start();
    }

    debugPrint("$_tag AI do move: $move");

    if (!(await position.doMove(move))) {
      return false;
    }

    moveHistory.add(move);

    sideToMove = position.sideToMove;

    _printStat();

    return true;
  }

  void _printStat() {
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

    debugPrint("$_tag $scoreInfo");
  }
}
