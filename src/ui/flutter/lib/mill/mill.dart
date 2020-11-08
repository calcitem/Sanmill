/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

enum MoveType { place, move, remove }

enum Phase { none, ready, placing, moving, gameOver }

enum Action { none, select, place, remove }

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

enum PieceType { none, blackStone, whiteStone, ban, count, stone }

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

const sqBegin = Square.SQ_8;
const sqEnd = 32;
const sqNumber = 40;
const effectiveSqNumber = 24;

enum MoveDirection { clockwise, anticlockwise, inward, outward }

enum LineDirection { horizontal, vertical, slash }

enum File { A, B, C }

const fileNumber = 3;

enum Rank { rank_1, rank_2, rank_3, rank_4, rank_5, rank_6, rank_7, rank_8 }

const rankNumber = 8;

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

int makeSquare(int file, int rank) {
  return (file << 3) + rank - 1;
}

/// 对战结果：未决、赢、输、和
enum GameResult { pending, win, lose, draw }

class Color {
  //
  static const unknown = '-';
  static const black = '@';
  static const white = 'O';
  static const ban = 'X';

  static String of(String piece) {
    if (black.contains(piece)) return black;
    if (white.contains(piece)) return white;
    if (ban.contains(piece)) return ban;
    return unknown;
  }

  static bool isSameColor(String p1, String p2) {
    return of(p1) == of(p2);
  }

  static String opponent(String color) {
    if (color == white) return black;
    if (color == black) return white;
    return color;
  }

  String operator -(String c) => opponent(c);
}

class Piece {
  //
  static const noPiece = '*';
  //
  static const blackStone = '@';
  static const whiteStone = 'O';
  static const ban = 'X';

  static bool isBlack(String c) => '@'.contains(c);

  static bool isWhite(String c) => 'O'.contains(c);
}

class Move {
  // TODO
  static const invalidIndex = -1;

  // List<String>(90) 中的索引
  int from, to;

  // 左上角为坐标原点
  int fx, fy, tx, ty;

  String captured;

  // 'step' is the UCI engine's move-string
  String step;
  String stepName;

  // 这一步走完后的 FEN 记数，用于悔棋时恢复 FEN 步数 Counter
  String counterMarks;

  Move(this.from, this.to,
      {this.captured = Piece.noPiece, this.counterMarks = '0 0'}) {
    //
    fx = from % 9;
    fy = from ~/ 9;

    tx = to % 9;
    ty = to ~/ 9;

    if (fx < 0 || fx > 8 || fy < 0 || fy > 9) {
      throw "Error: Invlid Step (from:$from, to:$to)";
    }

    step = String.fromCharCode('a'.codeUnitAt(0) + fx) + (9 - fy).toString();
    step += String.fromCharCode('a'.codeUnitAt(0) + tx) + (9 - ty).toString();
  }

  /// 引擎返回的招法用是如此表示的，例如:
  /// 落子：(1,2)
  /// 吃子：-(1,2)
  /// 走子：(3,1)->(2,1)

  Move.fromEngineStep(String step) {
    //
    this.step = step;

    if (!validateEngineStep(step)) {
      throw "Error: Invlid Step: $step";
    }

    fx = step[0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    fy = 9 - (step[1].codeUnitAt(0) - '0'.codeUnitAt(0));
    tx = step[2].codeUnitAt(0) - 'a'.codeUnitAt(0);
    ty = 9 - (step[3].codeUnitAt(0) - '0'.codeUnitAt(0));

    from = fx + fy * 9;
    to = tx + ty * 9;

    captured = Piece.noPiece;
  }

  static bool validateEngineStep(String step) {
    //
    if (step == null || step.length > "(3,1)->(2,1)".length) return false;

    final fx = step[0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final fy = 9 - (step[1].codeUnitAt(0) - '0'.codeUnitAt(0));
    if (fx < 0 || fx > 8 || fy < 0 || fy > 9) return false;

    final tx = step[2].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final ty = 9 - (step[3].codeUnitAt(0) - '0'.codeUnitAt(0));
    if (tx < 0 || tx > 8 || ty < 0 || ty > 9) return false;

    return true;
  }
}
