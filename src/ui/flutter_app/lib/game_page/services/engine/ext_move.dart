// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

enum MoveType { place, move, remove, draw, none }

class MoveParser {
  MoveType parseMoveType(String move) {
    if (move.startsWith("-") && move.length == "-(1,2)".length) {
      return MoveType.remove;
    } else if (move.length == "(1,2)->(3,4)".length) {
      return MoveType.move;
    } else if (move.length == "(1,2)".length) {
      return MoveType.place;
    } else if (move == "draw") {
      logger.i("[TODO] Computer request draw");
      return MoveType.draw;
    } else if (move == "(none)") {
      logger.i("MoveType is (none).");
      return MoveType.none;
    } else {
      // TODO: If Setup Position is illegal
      throw const FormatException();
    }
  }
}

// TODO: We should know who do this move
@immutable
class ExtMove {
  ExtMove(this.move) {
    _checkLegal();

    final MoveParser moveParser = MoveParser();
    type = moveParser.parseMoveType(move);

    late int toFile;
    late int toRank;

    switch (type) {
      case MoveType.place:
        toFile = int.parse(move[1]);
        toRank = int.parse(move[3]);
        break;
      case MoveType.move:
        toFile = int.parse(move[8]);
        toRank = int.parse(move[10]);
        break;
      case MoveType.remove:
        toFile = int.parse(move[2]);
        toRank = int.parse(move[4]);
        break;
      case MoveType.draw:
        toFile = 0;
        toRank = 0;
        break;
      case MoveType.none:
        toFile = -1;
        toRank = -1;
        break;
      case null:
        assert(false);
        toFile = -2;
        toRank = -2;
        break;
    }

    to = makeSquare(toFile, toRank);
  }

  static const String _logTag = "[Move]";

  // Square
  int get from => type == MoveType.move
      ? makeSquare(int.parse(move[1]), int.parse(move[3]))
      : -1;
  late final int to;

  static final Map<int, String> _squareToWmdNotation = <int, String>{
    -1: "(none)", // TODO: Can parse it?
    0: "draw", // TODO: Can parse it?
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

  static String sqToNotation(int sq) {
    final String? ret = _squareToWmdNotation[sq];
    return ret ?? "";
  }

  // "notation" is Standard Notation
  // Sample: xa1, a1-b2, a1
  String get notation {
    switch (type) {
      case MoveType.remove:
        return "x${_squareToWmdNotation[to]}";
      case MoveType.move:
        return "${_squareToWmdNotation[from]}-${_squareToWmdNotation[to]}";
      case MoveType.place:
        return _squareToWmdNotation[to]!;
      case MoveType.draw:
        return _squareToWmdNotation[to]!; // TODO: Can parse?
      case MoveType.none:
        return _squareToWmdNotation[to]!; // TODO: Can parse?
      case null:
        assert(false);
        return "";
    }
  }

  late final MoveType? type;

  void _checkLegal() {
    // TODO: Which one?
    if (move == "draw" || move == "(none)" || move == "none") {
      return;
    }

    if (move.length > "(3,1)->(2,1)".length) {
      throw FormatException(
        "$_logTag Invalid Move: move representation is too long",
        move,
      );
    }

    if (!(move.startsWith("(") || move.startsWith("-"))) {
      throw FormatException(
        "$_logTag Invalid Move: invalid first char. Expected '(' or '-' but got a ${move.characters.first}",
        move,
        0,
      );
    }

    if (!move.endsWith(")")) {
      throw FormatException(
        "$_logTag Invalid Move: invalid last char. Expected a ')' but got a ${move.characters.last}",
        move,
        move.length - 1,
      );
    }

    const String range = "0123456789(,)->";

    for (int i = 0; i < move.length; i++) {
      if (!range.contains(move[i])) {
        throw FormatException(
          "$_logTag Invalid Move: invalid char at pos $i. Expected one of '$range' but got ${move[i]}",
          move,
          i,
        );
      }
    }

    if (move.length == "(3,1)->(2,1)".length) {
      if (move.substring(0, 4) == move.substring(7, 11)) {
        // ignore: only_throw_errors
        throw "Error: $_logTag Invalid Move: move to the same place";
      }
    }
  }

  @override
  int get hashCode => move.hashCode;

  @override
  bool operator ==(Object other) => other is ExtMove && other.move == move;
}

class EngineRet {
  EngineRet(this.value, this.extMove);
  String? value;
  ExtMove? extMove;
}
