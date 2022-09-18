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

class GameRecorder extends PointedList<ExtMove> {
  String? lastPositionWithRemove = "";

  GameRecorder({this.lastPositionWithRemove});

  @override
  String toString() {
    final buffer = StringBuffer("[ ");
    for (final extMove in this) {
      buffer.write("${extMove.move}, ");
    }

    buffer.write("]");

    return buffer.toString();
  }

  String? get moveHistoryText {
    if (isEmpty || index == null) return null;
    final StringBuffer moveHistory = StringBuffer();
    int num = 1;
    int i = 0;

    void buildStandardNotation() {
      const separator = "    "; // TODO: Align

      if (i <= index!) {
        moveHistory.write(separator);
        moveHistory.write(this[i++].notation);
      }

      // If next notation is removal, append it directly and don't write number.
      if (i <= index! && this[i].type == MoveType.remove) {
        moveHistory.write(this[i++].notation);
      }
    }

    while (i <= index!) {
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
