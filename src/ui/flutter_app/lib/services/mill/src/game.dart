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

part of '../mill.dart';

class _Game {
  static const String _tag = "[game]";

  _Game() {
    focusIndex = blurIndex = null;
  }

  void start() {
    controller.position.reset();

    setWhoIsAi(engineType);
  }

  void newGame() {
    controller.position.phase = Phase.ready;
    start();

    controller.position.restart();
    focusIndex = blurIndex = null;

    moveHistory = [];
    sideToMove = PieceColor.white;
  }

  PieceColor sideToMove = PieceColor.white;

  bool get isAiToMove {
    assert(sideToMove == PieceColor.white || sideToMove == PieceColor.black);
    return isAi[sideToMove]!;
  }

  List<Move?> moveHistory = [];

  int? focusIndex;
  int? blurIndex;

  Map<PieceColor, bool> isAi = {
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
    logger.i(
      "$_tag White is searching? ${_isSearching[PieceColor.white]}\n"
      "$_tag Black is searching? ${_isSearching[PieceColor.black]}\n",
    );

    return _isSearching[PieceColor.white]! || _isSearching[PieceColor.black]!;
  }

  EngineType _engineType = EngineType.none;
  EngineType get engineType => _engineType;

  void setWhoIsAi(EngineType type) {
    _engineType = type;

    isAi = type.whoIsAI;

    logger.i(
      "$_tag White is AI? ${isAi[PieceColor.white]}\n"
      "$_tag Black is AI? ${isAi[PieceColor.black]}\n",
    );
  }

  void select(int pos) {
    focusIndex = pos;
    blurIndex = null;
  }

  Future<bool> doMove(Move move) async {
    if (controller.position.phase == Phase.ready) {
      start();
    }

    logger.i("$_tag AI do move: $move");

    if (!(await controller.position.doMove(move.move))) {
      return false;
    }

    moveHistory.add(move);

    sideToMove = controller.position.sideToMove;

    _logStat();

    return true;
  }

  void _logStat() {
    final int total = controller.position.score[PieceColor.white]! +
        controller.position.score[PieceColor.black]! +
        controller.position.score[PieceColor.draw]!;

    double whiteWinRate = 0;
    double blackWinRate = 0;
    double drawRate = 0;
    if (total != 0) {
      whiteWinRate = controller.position.score[PieceColor.white]! * 100 / total;
      blackWinRate = controller.position.score[PieceColor.black]! * 100 / total;
      drawRate = controller.position.score[PieceColor.draw]! * 100 / total;
    }

    final String scoreInfo =
        "Score: ${controller.position.score[PieceColor.white]} :"
        " ${controller.position.score[PieceColor.black]} :"
        " ${controller.position.score[PieceColor.draw]}\ttotal:"
        " $total\n$whiteWinRate% : $blackWinRate% : $drawRate%\n";

    logger.i("$_tag $scoreInfo");
  }
}
