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
  int cur = -1;
  String? lastPositionWithRemove = "";
  var _history = <Move>[];

  GameRecorder({this.cur = -1, this.lastPositionWithRemove});

  List<Move> getHistory() {
    return _history;
  }

  void setHistory(List<Move> newHistory) {
    _history = newHistory;
  }

  void jumpToHead() {
    cur = 0;
  }

  void jumpToTail() {
    cur = _history.length - 1;
  }

  void clear() {
    _history.clear();
    cur = 0;
  }

  void prune() {
    if (cur == _history.length - 1) {
      return;
    }

    _history.removeRange(cur + 1, _history.length);
  }

  void moveIn(Move move, Position position) {
    if (_history.length > 0) {
      if (_history[_history.length - 1].move == move.move) {
        //assert(false);
        // TODO: WAR
        return;
      }
    }

    _history.add(move);
    cur++;

    if (move.type == MoveType.remove) {
      lastPositionWithRemove = position.fen();
    }
  }

  Move? removeLast() {
    if (_history.isEmpty) return null;
    return _history.removeLast();
  }

  get last => _history.isEmpty ? null : _history.last;

  Move moveAt(int index) => _history[index];

  get movesCount => _history.length;

  String buildMoveHistoryText({cols = 2}) {
    var moveHistoryText = '';
    int k = 1;
    String num = "";

    for (var i = 0; i <= cur; i++) {
      if (Config.standardNotationEnabled) {
        if (k % cols == 1) {
          num = "${(k + 1) ~/ 2}.    ";
          if (k < 9 * cols) {
            num = " " + num + " ";
          }
        } else {
          num = "";
        }
        if (i + 1 <= cur && _history[i + 1].type == MoveType.remove) {
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
}
