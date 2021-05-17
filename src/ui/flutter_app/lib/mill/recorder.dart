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

import 'package:sanmill/common/config.dart';

import 'position.dart';
import 'types.dart';

// TODO
class GameRecorder {
  int? halfMove, fullMove;
  String? lastPositionWithRemove = "";
  final _history = <Move>[];

  GameRecorder(
      {this.halfMove = 0, this.fullMove = 0, this.lastPositionWithRemove});

  GameRecorder.fromCounterMarks(String marks) {
    //
    var segments = marks.split(' ');
    if (segments.length != 2) {
      throw 'Error: Invalid Counter Marks: $marks';
    }

    halfMove = int.parse(segments[0]);
    fullMove = int.parse(segments[1]);

    if (halfMove == null || fullMove == null) {
      throw 'Error: Invalid Counter Marks: $marks';
    }
  }

  List<Move> getHistory() {
    return _history;
  }

  void moveIn(Move move, Position position) {
    //
    if (move.type == MoveType.remove) {
      halfMove = 0;
    } else {
      if (halfMove != null) halfMove = halfMove! + 1;
    }

    if (fullMove == 0) {
      if (halfMove != null) halfMove = halfMove! + 1;
    } else if (position.side != PieceColor.white) {
      if (halfMove != null) halfMove = halfMove! + 1;
    }

    if (_history.length > 0) {
      if (_history[_history.length - 1].move == move.move) {
        //assert(false);
        // TODO: WAR
        return;
      }
    }

    _history.add(move);

    if (move.type == MoveType.remove) {
      lastPositionWithRemove = position.fen();
    }
  }

  Move? removeLast() {
    if (_history.isEmpty) return null;
    return _history.removeLast();
  }

  get last => _history.isEmpty ? null : _history.last;

  List<Move> reverseMovesToPrevRemove() {
    //
    List<Move> moves = [];

    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].type == MoveType.remove) break;
      moves.add(_history[i]);
    }

    return moves;
  }

  String buildMoveHistoryText({cols = 2}) {
    var moveHistoryText = '';
    int k = 1;
    String num = "";

    for (var i = 0; i < _history.length; i++) {
      if (Config.standardNotationEnabled) {
        if (k % cols == 1) {
          num = "${(k + 1) ~/ 2}.    ";
          if (k < 9 * cols) {
            num = " " + num + " ";
          }
        } else {
          num = "";
        }
        if (i + 1 < _history.length &&
            _history[i + 1].type == MoveType.remove) {
          moveHistoryText +=
              '$num${_history[i].notation}${_history[i + 1].notation}    ';
          i++;
        } else {
          moveHistoryText += '$num${_history[i].notation}    ';
        }
        k++;
      } else {
        moveHistoryText += '${i < 9 ? ' ' : ''}${i + 1}. ${_history[i].move}　';
      }

      if (Config.standardNotationEnabled) {
        if ((k + 1) % cols == 0) moveHistoryText += '\n';
      } else {
        if ((i + 1) % cols == 0) moveHistoryText += '\n';
      }
    }

    if (moveHistoryText.isEmpty) {
      moveHistoryText = "";
    }

    return moveHistoryText;
  }

  Move moveAt(int index) => _history[index];

  get movesCount => _history.length;

  @override
  String toString() {
    return '$halfMove $fullMove';
  }
}
