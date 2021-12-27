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
  List<ExtMove> moves = <ExtMove>[];
  final MillController controller;

  _GameRecorder(this.controller);

  Future<void> import(BuildContext context) async =>
      _ImportService(controller).importGame(context);

  Future<void> export(BuildContext context) async =>
      _ImportService(controller).exportGame(context);

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

  void moveIn(ExtMove extMove) {
    if (moves.lastF == extMove) {
      //assert(false);
      // TODO: WAR
      return;
    }

    moves.add(extMove);
    cur++;
  }

  int get moveCount => moves.length;

  ExtMove? get lastMove => moves.lastF;

  ExtMove? get lastEffectiveMove => cur == -1 ? null : moves[cur];

  String? get moveHistoryText {
    if (moves.isEmpty) return null;

    final StringBuffer moveHistory = StringBuffer();
    int k = 1;
    int i = 0;

    void buildStandardNotation() {
      const separator = "    ";

      if (i <= cur) {
        moveHistory.write(separator);
        moveHistory.write(moves[i++].notation);
      }

      if (i <= cur && moves[i].type == _MoveType.remove) {
        moveHistory.write(moves[i++].notation);
      }
    }

    while (i <= cur) {
      moveHistory.writeNumber(k++);
      if (DB().display.standardNotationEnabled) {
        buildStandardNotation();
        buildStandardNotation();
      } else {
        const separator = " ";
        moveHistory.write(separator);
        moveHistory.write(moves[i++].move);

        if (i <= cur) {
          moveHistory.write(separator);
          moveHistory.writeNumber(k++);
          moveHistory.write(separator);
          moveHistory.write(moves[i++].move);
        }
      }
      moveHistory.writeln();
    }

    return moveHistory.toString();
  }
}
