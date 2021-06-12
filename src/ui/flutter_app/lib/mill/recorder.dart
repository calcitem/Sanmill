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
  final tag = "[GameRecorder]";

  GameRecorder({this.cur = -1, this.lastPositionWithRemove});

  List<Move> getHistory() {
    return _history;
  }

  void setHistory(List<Move> newHistory) {
    _history = newHistory;
  }

  String parseNotation(String ntt) {
    String move = "";

    if (ntt.length == 3 && ntt[0] == "x") {
      if (notationToMove[ntt.substring(1, 3)] != null) {
        move = '-' + notationToMove[ntt.substring(1, 3)]!;
      }
    } else if (ntt.length == 2) {
      if (notationToMove[ntt] != null) {
        move = notationToMove[ntt]!;
      }
    } else if (ntt.length == 5 && ntt[2] == '-') {
      if (notationToMove[(ntt.substring(0, 2))] != null &&
          notationToMove[(ntt.substring(3, 5))] != null) {
        move = notationToMove[(ntt.substring(0, 2))]! +
            '->' +
            notationToMove[(ntt.substring(3, 5))]!;
      }
    } else if ((ntt.length == 8 && ntt[2] == '-' && ntt[5] == 'x') ||
        (ntt.length == 5 && ntt[2] == 'x')) {
      print("$tag Not support parsing format oo-ooxo notation.");
    } else {
      print("$tag Parse notation $ntt failed.");
    }

    return move;
  }

  String import(String moveList) {
    List<Move> newHistory = [];
    List<String> list = moveList
        .toLowerCase()
        .replaceAll('\n', ' ')
        .replaceAll(',', ' ')
        .replaceAll(';', ' ')
        .replaceAll('!', ' ')
        .replaceAll('?', ' ')
        .replaceAll('white', ' ')
        .replaceAll('black', ' ')
        .replaceAll('win', ' ')
        .replaceAll('lose', ' ')
        .replaceAll('draw', ' ')
        .replaceAll('resign', ' ')
        .split(' ');

    for (var i in list) {
      i = i.trim();
      if (i.length > 0 && !i.endsWith(".")) {
        if (i.length == 5 && i[2] == 'x') {
          // "a1xc3"
          String m1 = parseNotation(i.substring(0, 2));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            print("Cannot import $i");
            return i;
          }
          String m2 = parseNotation(i.substring(2));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            print("Cannot import $i");
            return i;
          }
        } else if (i.length == 8 && i[2] == '-' && i[5] == 'x') {
          // "a1-b2xc3"
          String m1 = parseNotation(i.substring(0, 5));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            print("Cannot import $i");
            return i;
          }
          String m2 = parseNotation(i.substring(5));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            print("Cannot import $i");
            return i;
          }
        } else {
          // no x
          String m = parseNotation(i);
          if (m != "") {
            newHistory.add(Move(m));
          } else {
            print("Cannot import $i");
            return i;
          }
        }
      }
    }

    if (newHistory.length > 0) {
      setHistory(newHistory);
    }

    return "";
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

  bool isClean() {
    return cur == _history.length - 1;
  }

  void prune() {
    if (isClean()) {
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
