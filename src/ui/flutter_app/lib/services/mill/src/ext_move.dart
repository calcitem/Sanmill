// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../mill.dart';

enum _MoveType { place, move, remove }

extension _MoveTypeExtension on _MoveType {
  static _MoveType parse(String move) {
    if (move.startsWith("-") && move.length == "-(1,2)".length) {
      return _MoveType.remove;
    } else if (move.length == "(1,2)->(3,4)".length) {
      return _MoveType.move;
    } else if (move.length == "(1,2)".length) {
      return _MoveType.place;
    } else if (move == "draw") {
      throw UnimplementedError("[TODO] Computer request draw");
    } else {
      throw const FormatException();
    }
  }
}

class ExtMove {
  static const _tag = "[Move]";

  // Square
  int get from => type == _MoveType.move
      ? makeSquare(int.parse(move[1]), int.parse(move[3]))
      : -1;
  late final int to;

  static final Map<int, String> _squareToWmdNotation = {
    8: "d5",
    9: "e5",
    10: "e4",
    11: "e3",
    12: "d3",
    13: "c3",
    14: "c4",
    15: "c5",
    16: "d6",
    17: "f6",
    18: "f4",
    19: "f2",
    20: "d2",
    21: "b2",
    22: "b4",
    23: "b6",
    24: "d7",
    25: "g7",
    26: "g4",
    27: "g1",
    28: "d1",
    29: "a1",
    30: "a4",
    31: "a7"
  };

  // 'move' is the UCI engine's move-string
  final String move;

  // "notation" is Standard Notation
  String get notation {
    switch (type) {
      case _MoveType.remove:
        return "x${_squareToWmdNotation[to]}";
      case _MoveType.move:
        return "${_squareToWmdNotation[from]}-${_squareToWmdNotation[to]}";
      case _MoveType.place:
        return _squareToWmdNotation[to]!;
    }
  }

  late final _MoveType type;

  ExtMove(this.move) {
    _checkLegal();

    type = _MoveTypeExtension.parse(move);

    final int _toFile;
    final int _toRank;
    switch (type) {
      case _MoveType.remove:
        _toFile = int.parse(move[2]);
        _toRank = int.parse(move[4]);
        break;
      case _MoveType.move:
        _toFile = int.parse(move[8]);
        _toRank = int.parse(move[10]);
        break;
      case _MoveType.place:
        _toFile = int.parse(move[1]);
        _toRank = int.parse(move[3]);
    }
    to = makeSquare(_toFile, _toRank);

    assert(from != to);
  }

  void _checkLegal() {
    if (move == "draw") {
      // TODO
    }

    if (move.length > "(3,1)->(2,1)".length) {
      throw FormatException(
        "$_tag Invalid Move: move representation is to long",
        move,
      );
    }

    if (!(move.startsWith("(") || move.startsWith("-"))) {
      throw FormatException(
        "$_tag Invalid Move: invalid first char. Expected '(' or '-' but got a ${move.characters.first}",
        move,
        0,
      );
    }

    if (!move.endsWith(")")) {
      throw FormatException(
        "$_tag Invalid Move: invalid last char. Expected a ')' but got a ${move.characters.last}",
        move,
        move.length - 1,
      );
    }

    const String range = "0123456789(,)->";

    for (int i = 0; i < move.length; i++) {
      if (!range.contains(move[i])) {
        throw FormatException(
          "$_tag Invalid Move: invalid char at pos $i. Expected one of '$range' but got ${move[i]}",
          move,
          i,
        );
      }
    }

    if (move.length == "(3,1)->(2,1)".length) {
      if (move.substring(0, 4) == move.substring(7, 11)) {
        throw "Error: $_tag Invalid Move: move to the same place";
      }
    }
  }

  @override
  int get hashCode => move.hashCode;

  @override
  bool operator ==(Object other) => other is ExtMove && other.move == move;
}
