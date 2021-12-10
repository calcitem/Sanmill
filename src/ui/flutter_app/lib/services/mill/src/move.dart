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

class Move {
  static const _invalidMove = -1;

  static const _tag = "[Move]";

  // Square
  int from = 0;
  int to = 0;

  // file & rank
  int _fromFile = 0;
  int _fromRank = 0;
  int _toFile = 0;
  int _toRank = 0;

  // 'move' is the UCI engine's move-string
  final String uciMove;

  // "notation" is Standard Notation
  late final String notation;

  late final _MoveType type;

  // TODO: [Leptopoda] attributes should probably be made getters
  Move(this.uciMove) {
    _checkLegal();

    if (uciMove[0] == "-" && uciMove.length == "-(1,2)".length) {
      // TODO: [Leptopdoa] let [_MoveType] parse the move
      type = _MoveType.remove;
      from = _fromFile = _fromRank = _invalidMove;
      _toFile = int.parse(uciMove[2]);
      _toRank = int.parse(uciMove[4]);
      to = makeSquare(_toFile, _toRank);
      notation = "x${_squareToWmdNotation[to]}";
      //captured = PieceColor.none;
    } else if (uciMove.length == "(1,2)->(3,4)".length) {
      type = _MoveType.move;
      _fromFile = int.parse(uciMove[1]);
      _fromRank = int.parse(uciMove[3]);
      from = makeSquare(_fromFile, _fromRank);
      _toFile = int.parse(uciMove[8]);
      _toRank = int.parse(uciMove[10]);
      to = makeSquare(_toFile, _toRank);
      notation = "${_squareToWmdNotation[from]}-${_squareToWmdNotation[to]}";
    } else if (uciMove.length == "(1,2)".length) {
      type = _MoveType.place;
      from = _fromFile = _fromRank = _invalidMove;
      _toFile = int.parse(uciMove[1]);
      _toRank = int.parse(uciMove[3]);
      to = makeSquare(_toFile, _toRank);
      // TODO: [Leptopoda] remove stringy thing
      notation = "${_squareToWmdNotation[to]}";
    } else if (uciMove == "draw") {
      assert(false, "not yet implemented"); // TODO
      logger.v("[TODO] Computer request draw");
    } else {
      assert(false);
    }

    assert(from != to);
  }

  void _checkLegal() {
    if (uciMove == "draw") {
      // TODO
    }

    if (uciMove.length > "(3,1)->(2,1)".length) {
      throw FormatException(
        "$_tag Invalid Move: move representation is to long",
        uciMove,
      );
    }

    const String range = "0123456789(,)->";

    if (!(uciMove[0] == "(" || uciMove[0] == "-")) {
      throw FormatException(
        "$_tag Invalid Move: invalid first char. Expected '(' or '-' but got a ${uciMove[0]}",
        uciMove,
        0,
      );
    }

    if (uciMove.characters.last != ")") {
      throw FormatException(
        "$_tag Invalid Move: invalid last char. Expected a ')' but got a ${uciMove.characters.last}",
        uciMove,
        uciMove.length - 1,
      );
    }

    for (int i = 0; i < uciMove.length; i++) {
      if (!range.contains(uciMove[i])) {
        throw FormatException(
          "$_tag Invalid Move: invalid char at pos $i. Expected one of '$range' but got ${uciMove[i]}",
          uciMove,
          i,
        );
      }
    }

    if (uciMove.length == "(3,1)->(2,1)".length) {
      if (uciMove.substring(0, 4) == uciMove.substring(7, 11)) {
        throw "Error: $_tag Invalid Move: move to the same place";
      }
    }
  }

  @override
  int get hashCode => uciMove.hashCode;

  @override
  bool operator ==(Object other) => other is Move && other.uciMove == uciMove;
}
