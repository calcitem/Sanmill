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

import 'package:sanmill/common/algorithm.dart';

enum MoveType { place, move, remove }

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

const sqBegin = 8;
const sqEnd = 32;
const sqNumber = 40;
const effectiveSqNumber = 24;

enum MoveDirection { clockwise, anticlockwise, inward, outward }

const moveDirectionBegin = 0;
const moveDirectionNumber = 4;

enum LineDirection { horizontal, vertical, slash }

const lineDirectionNumber = 3;

enum File { A, B, C }

const fileNumber = 3;
const fileExNumber = fileNumber + 2;

enum Rank { rank_1, rank_2, rank_3, rank_4, rank_5, rank_6, rank_7, rank_8 }

const rankNumber = 8;

bool isOk(int sq) {
  bool ret = (sq == 0 || (sq >= 8 && sq <= 31));

  if (ret == false) {
    print("$sq is not OK");
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
