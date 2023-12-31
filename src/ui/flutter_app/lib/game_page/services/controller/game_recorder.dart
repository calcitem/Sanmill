// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

class GameRecorder extends PointedList<ExtMove> {
  GameRecorder({this.lastPositionWithRemove, this.setupPosition});

  String? lastPositionWithRemove = "";
  String? setupPosition;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer("[ ");
    for (final ExtMove extMove in this) {
      buffer.write("${extMove.move}, ");
    }

    buffer.write("]");

    return buffer.toString();
  }

  int get placeCount {
    if (isEmpty || index == null) {
      return 0;
    }

    int n = 0;

    for (int i = 0; i <= index!; i++) {
      if (this[i].type == MoveType.place) {
        n++;
      }
    }

    return n;
  }

  String get moveHistoryText {
    String buildTagPairs() {
      if (GameController().gameRecorder.setupPosition != null) {
        return '[FEN "${GameController().gameRecorder.setupPosition!}"]\r\n[SetUp "1"]\r\n\r\n';
      }
      return '[FEN "${GameController().position.fen}"]\r\n[SetUp "1"]\r\n\r\n';
    }

    if (isEmpty || index == null) {
      if (GameController().isPositionSetup == true) {
        return buildTagPairs();
      } else {
        return "";
      }
    }

    final StringBuffer moveHistory = StringBuffer();
    int num = 1;
    int i = 0;

    void buildStandardNotation() {
      const String separator = "    "; // TODO: Align

      if (i <= index!) {
        moveHistory.write(separator);
        moveHistory.write(this[i++].notation);
      }

      // If next notation is removal, append it directly and don't write number.
      for (int round = 0; round < 3; round++) {
        if (i <= index! && this[i].type == MoveType.remove) {
          moveHistory.write(this[i++].notation);
        }
      }
    }

    if (GameController().isPositionSetup == true) {
      moveHistory.write(buildTagPairs());
    }

    while (i <= index!) {
      // TODO: When AI draw, print number but not move
      moveHistory.writeNumber(num++);
      buildStandardNotation();
      buildStandardNotation();

      if (i <= index!) {
        moveHistory.writeln();
      }
    }

    return moveHistory.toString();
  }
}
