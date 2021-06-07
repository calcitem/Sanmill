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

abs(value) => value > 0 ? value : -value;

class Move {
  static const invalidMove = -1;

  // Square
  int from = 0;
  int to = 0;

  // file & rank
  int fromFile = 0;
  int fromRank = 0;
  int toFile = 0;
  int toRank = 0;

  // Index
  int fromIndex = 0;
  int toIndex = 0;

  String removed = Piece.noPiece;

  // 'move' is the UCI engine's move-string
  String? move = "";

  // "notation" is Standard Notation
  String? notation = "";

  MoveType type = MoveType.none;

  // Used to restore fen step counter when undoing move
  String counterMarks = "";

  parse() {
    if (!legal(move)) {
      throw "Error: Invalid Move: $move";
    }

    if (move![0] == '-' && move!.length == "-(1,2)".length) {
      type = MoveType.remove;
      from = fromFile = fromRank = fromIndex = invalidMove;
      toFile = int.parse(move![2]);
      toRank = int.parse(move![4]);
      to = makeSquare(toFile, toRank);
      notation = "x${squareToNotation[to]}";
      //captured = Piece.noPiece;
    } else if (move!.length == "(1,2)->(3,4)".length) {
      type = MoveType.move;
      fromFile = int.parse(move![1]);
      fromRank = int.parse(move![3]);
      from = makeSquare(fromFile, fromRank);
      fromIndex = squareToIndex[from] ?? invalidMove;
      toFile = int.parse(move![8]);
      toRank = int.parse(move![10]);
      to = makeSquare(toFile, toRank);
      notation = "${squareToNotation[from]}-${squareToNotation[to]}";
      removed = Piece.noPiece;
    } else if (move!.length == "(1,2)".length) {
      type = MoveType.place;
      from = fromFile = fromRank = fromIndex = invalidMove;
      toFile = int.parse(move![1]);
      toRank = int.parse(move![3]);
      to = makeSquare(toFile, toRank);
      notation = "${squareToNotation[to]}";
      removed = Piece.noPiece;
    } else if (move == "draw") {
      // TODO
      print("[TODO] Computer request draw");
    } else {
      assert(false);
    }

    toIndex = squareToIndex[to] ?? invalidMove;
  }

  Move(this.move) {
    parse();
  }

  /// Format:
  /// Place: (1,2)
  /// Remove: -(1,2)
  /// Move: (3,1)->(2,1)

  Move.set(String move) {
    this.move = move;
    parse();
  }

  static bool legal(String? move) {
    if (move == "draw") {
      return true; // TODO
    }

    if (move == null || move.length > "(3,1)->(2,1)".length) return false;

    String range = "0123456789(,)->";

    if (!(move[0] == '(' || move[0] == '-')) {
      return false;
    }

    if (move[move.length - 1] != ')') {
      return false;
    }

    for (int i = 0; i < move.length; i++) {
      if (!range.contains(move[i])) return false;
    }

    if (move.length == "(3,1)->(2,1)".length) {
      if (move.substring(0, 4) == move.substring(7, 11)) {
        return false;
      }
    }

    return true;
  }
}

enum MoveType { place, move, remove, none }

class PieceColor {
  static const none = '*';
  static const white = 'O';
  static const black = '@';
  static const ban = 'X';
  static const nobody = '-';
  static const draw = '=';

  static String of(String piece) {
    if (white.contains(piece)) return white;
    if (black.contains(piece)) return black;
    if (ban.contains(piece)) return ban;
    return nobody;
  }

  static bool isSameColor(String p1, String p2) => of(p1) == of(p2);

  static String opponent(String color) {
    if (color == black) return white;
    if (color == white) return black;
    return color;
  }

  String operator -(String c) => opponent(c);
}

Map<String, int> pieceColorIndex = {
  PieceColor.none: 0,
  PieceColor.white: 1,
  PieceColor.black: 2,
  PieceColor.ban: 3
};

enum Phase { none, ready, placing, moving, gameOver }

enum Act { none, select, place, remove }

enum GameOverReason {
  noReason,
  loseReasonlessThanThree,
  loseReasonNoWay,
  loseReasonBoardIsFull,
  loseReasonResign,
  loseReasonTimeOver,
  drawReasonThreefoldRepetition,
  drawReasonRule50,
  drawReasonBoardIsFull
}

enum PieceType { none, whiteStone, blackStone, ban, count, stone }

class Piece {
  static const noPiece = PieceColor.none;
  static const whiteStone = PieceColor.white;
  static const blackStone = PieceColor.black;
  static const ban = PieceColor.ban;

  static bool isEmpty(String c) => noPiece.contains(c);
  static bool isWhite(String c) => whiteStone.contains(c);
  static bool isBlack(String c) => blackStone.contains(c);
  static bool isBan(String c) => ban.contains(c);
}

enum Square {
  SQ_0,
  SQ_1,
  SQ_2,
  SQ_3,
  SQ_4,
  SQ_5,
  SQ_6,
  SQ_7,
  SQ_8,
  SQ_9,
  SQ_10,
  SQ_11,
  SQ_12,
  SQ_13,
  SQ_14,
  SQ_15,
  SQ_16,
  SQ_17,
  SQ_18,
  SQ_19,
  SQ_20,
  SQ_21,
  SQ_22,
  SQ_23,
  SQ_24,
  SQ_25,
  SQ_26,
  SQ_27,
  SQ_28,
  SQ_29,
  SQ_30,
  SQ_31,
}

const sqBegin = 8;
const sqEnd = 32;
const sqNumber = 40;
const effectiveSqNumber = 24;

enum MoveDirection { clockwise, anticlockwise, inward, outward }

const moveDirectionBegin = 0;
const moveDirectionNumber = 4;

enum LineDirection { horizontal, vertical, slash }

const lineDirectionNumber = 3;

enum File { none, A, B, C }

const fileNumber = 3;
const fileExNumber = fileNumber + 2;

enum Rank { rank_1, rank_2, rank_3, rank_4, rank_5, rank_6, rank_7, rank_8 }

const rankNumber = 8;

int makeSquare(int file, int rank) {
  return (file << 3) + rank - 1;
}

bool isOk(int sq) {
  bool ret = (sq == 0 || (sq >= sqBegin && sq < sqEnd));

  if (ret == false) {
    print("[types] $sq is not OK");
  }

  return ret; // TODO: SQ_NONE?
}

int fileOf(int sq) {
  return (sq >> 3);
}

int rankOf(int sq) {
  return (sq & 0x07) + 1;
}

int fromSq(int move) {
  move = abs(move);
  return (move >> 8);
}

int toSq(int move) {
  move = abs(move);
  return (move & 0x00FF);
}

int makeMove(int from, int to) {
  return (from << 8) + to;
}

const invalidIndex = -1;

Map<int, int> squareToIndex = {
  8: 17,
  9: 18,
  10: 25,
  11: 32,
  12: 31,
  13: 30,
  14: 23,
  15: 16,
  16: 10,
  17: 12,
  18: 26,
  19: 40,
  20: 38,
  21: 36,
  22: 22,
  23: 8,
  24: 3,
  25: 6,
  26: 27,
  27: 48,
  28: 45,
  29: 42,
  30: 21,
  31: 0
};

Map<int, int> indexToSquare = squareToIndex.map((k, v) => MapEntry(v, k));

/*
          a b c d e f g
        7 X --- X --- X 7
          |\    |    /|
        6 | X - X - X | 6
          | |\  |  /| |
        5 | | X-X-X | | 5
        4 X-X-X   X-X-X 4
        3 | | X-X-X | | 3
          | |/  |  \| |
        2 | X - X - X | 2
          |/    |    \|
        1 X --- X --- X 1
          a b c d e f g
 */
Map<int, String> squareToNotation = {
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

Map<String, String> notationToMove = {
  "d5": "(1,1)",
  "e5": "(1,2)",
  "e4": "(1,3)",
  "e3": "(1,4)",
  "d3": "(1,5)",
  "c3": "(1,6)",
  "c4": "(1,7)",
  "c5": "(1,8)",
  "d6": "(2,1)",
  "f6": "(2,2)",
  "f4": "(2,3)",
  "f2": "(2,4)",
  "d2": "(2,5)",
  "b2": "(2,6)",
  "b4": "(2,7)",
  "b6": "(2,8)",
  "d7": "(3,1)",
  "g7": "(3,2)",
  "g4": "(3,3)",
  "g1": "(3,4)",
  "d1": "(3,5)",
  "a1": "(3,6)",
  "a4": "(3,7)",
  "a7": "(3,8)",
};

enum GameResult { pending, win, lose, draw, none }
