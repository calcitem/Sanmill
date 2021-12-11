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

// TODO
// TODO: [Leptopoda] the public facing methods look a lot like the ones Iterable has.
//We might wanna make GameRecorder one.
class _GameRecorder {
  // TODO: [Leptopoda] use null
  int cur = -1;
  String lastPositionWithRemove;
  List<ExtMove> moves = <ExtMove>[];
  final MillController controller;

  _GameRecorder(
    this.controller, {
    this.cur = -1,
    required this.lastPositionWithRemove,
  });

// TODO [Leptopoda] make param a List<Move> and change the return type
  String? import(String moveList) =>
      _ImportService(controller).import(moveList);

  void clear() {
    moves.clear();
    cur = 0;
  }

  bool get isClean {
    return cur == moves.length - 1;
  }

  void prune() {
    if (isClean) {
      return;
    }

    moves.removeRange(cur + 1, moves.length);
  }

  // TODO: [Leptopoda] don't pass around the position object as we can access it through [controller.position]
  void moveIn(ExtMove extMove, Position position) {
    if (moves.lastF == extMove) {
      //assert(false);
      // TODO: WAR
      return;
    }

    moves.add(extMove);
    cur++;

    if (extMove.type == _MoveType.remove) {
      lastPositionWithRemove = position._fen;
    }
  }

  int get moveCount => moves.length;

  ExtMove? get lastMove => moves.lastF;

  ExtMove? get lastEffectiveMove => cur == -1 ? null : moves[cur];

  String? _buildMoveHistoryText({int cols = 2}) {
    if (moves.isEmpty) {
      return null;
    }

    final StringBuffer moveHistory = StringBuffer();

    String num = "";
    int k = 1;
    for (var i = 0; i <= cur; i++) {
      if (LocalDatabaseService.display.standardNotationEnabled) {
        if (k % cols == 1) {
          num = "${(k + 1) ~/ 2}.    ";
          if (k < 9 * cols) {
            num = " $num ";
          }
        }
        if (i + 1 <= cur && moves[i + 1].type == _MoveType.remove) {
          moveHistory.write(
            "$num${moves[i].notation}${moves[i + 1].notation}    ",
          );
          i++;
        } else {
          moveHistory.write("$num${moves[i].notation}    ");
        }
        k++;
      } else {
        moveHistory.write("${i < 9 ? " " : ""}${i + 1}. ${moves[i].move}　");
      }

      if (LocalDatabaseService.display.standardNotationEnabled) {
        if ((k + 1) % cols == 0) moveHistory.writeln();
      } else {
        if ((i + 1) % cols == 0) moveHistory.writeln();
      }
    }

    return moveHistory.toString().replaceAll("    \n", "\n");
  }
}
