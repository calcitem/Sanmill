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

  String wmdNotationToMoveString(String wmd) {
    String move = "";

    if (wmd.length == 3 && wmd[0] == "x") {
      if (wmdNotationToMove[wmd.substring(1, 3)] != null) {
        move = '-' + wmdNotationToMove[wmd.substring(1, 3)]!;
      }
    } else if (wmd.length == 2) {
      if (wmdNotationToMove[wmd] != null) {
        move = wmdNotationToMove[wmd]!;
      }
    } else if (wmd.length == 5 && wmd[2] == '-') {
      if (wmdNotationToMove[(wmd.substring(0, 2))] != null &&
          wmdNotationToMove[(wmd.substring(3, 5))] != null) {
        move = wmdNotationToMove[(wmd.substring(0, 2))]! +
            '->' +
            wmdNotationToMove[(wmd.substring(3, 5))]!;
      }
    } else if ((wmd.length == 8 && wmd[2] == '-' && wmd[5] == 'x') ||
        (wmd.length == 5 && wmd[2] == 'x')) {
      print("$tag Not support parsing format oo-ooxo notation.");
    } else {
      print("$tag Parse notation $wmd failed.");
    }

    return move;
  }

  String playOkNotationToMoveString(String playOk) {
    String move = "";

    if (playOk.length == 0) {
      return "";
    }

    var iDash = playOk.indexOf('-');
    var iX = playOk.indexOf('x');

    if (iDash == -1 && iX == -1) {
      // 12
      var val = int.parse(playOk);
      if (val >= 1 && val <= 24) {
        move = playOkNotationToMove[playOk]!;
        return move;
      } else {
        print("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }

    if (iX == 0) {
      // x12
      var sub = playOk.substring(1);
      var val = int.parse(sub);
      if (val >= 1 && val <= 24) {
        move = "-" + playOkNotationToMove[sub]!;
        return move;
      } else {
        print("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }
    if (iDash != -1 && iX == -1) {
      // 12-13
      var sub1 = playOk.substring(0, iDash);
      var val1 = int.parse(sub1);
      if (val1 >= 1 && val1 <= 24) {
        move = playOkNotationToMove[sub1]!;
      } else {
        print("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }

      var sub2 = playOk.substring(iDash + 1);
      var val2 = int.parse(sub2);
      if (val2 >= 1 && val2 <= 24) {
        move = move + "->" + playOkNotationToMove[sub2]!;
        return move;
      } else {
        print("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }

    print("$tag Not support parsing format oo-ooxo PlayOK notation.");
    return "";
  }

  bool isDalmaxMoveList(String text) {
    if (text.length >= 15 && text.substring(0, 14) == "[Event \"Dalmax") {
      return true;
    }

    return false;
  }

  bool isPlayOkMoveList(String text) {
    if (text.length >= 4 &&
        text.substring(0, 3) == "1. " &&
        int.tryParse(text.substring(3, 4)) != null) {
      return true;
    }

    if (text.length > 0 && text[0] == '[') {
      return true;
    }

    return false;
  }

  bool isPlayOkNotation(String text) {
    if (int.tryParse(text.substring(3, 4)) != null) {
      return true;
    }

    return false;
  }

  String playOkToWmdMoveList(String playOk) {
    return "";
  }

  String import(String moveList) {
    if (isDalmaxMoveList(moveList)) {
      return importDalmax(moveList);
    }

    if (isPlayOkMoveList(moveList)) {
      return importPlayOk(moveList);
    }

    List<Move> newHistory = [];
    List<String> list = moveList
        .toLowerCase()
        .replaceAll('\n', ' ')
        .replaceAll(',', ' ')
        .replaceAll(';', ' ')
        .replaceAll('!', ' ')
        .replaceAll('?', ' ')
        .replaceAll('#', ' ')
        .replaceAll('()', ' ')
        .replaceAll('white', ' ')
        .replaceAll('black', ' ')
        .replaceAll('win', ' ')
        .replaceAll('lose', ' ')
        .replaceAll('draw', ' ')
        .replaceAll('resign', ' ')
        .replaceAll('-/x', 'x')
        .replaceAll('/x', 'x')
        .replaceAll('.a', '. a')
        .replaceAll('.b', '. b')
        .replaceAll('.c', '. c')
        .replaceAll('.d', '. d')
        .replaceAll('.e', '. e')
        .replaceAll('.f', '. f')
        .replaceAll('.g', '. g')
        .split(' ');

    for (var i in list) {
      i = i.trim();

      if (int.tryParse(i) != null) {
        i = i + '.';
      }

      if (i.length > 0 && !i.endsWith(".")) {
        if (i.length == 5 && i[2] == 'x') {
          // "a1xc3"
          String m1 = wmdNotationToMoveString(i.substring(0, 2));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            print("Cannot import $i");
            return i;
          }
          String m2 = wmdNotationToMoveString(i.substring(2));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            print("Cannot import $i");
            return i;
          }
        } else if (i.length == 8 && i[2] == '-' && i[5] == 'x') {
          // "a1-b2xc3"
          String m1 = wmdNotationToMoveString(i.substring(0, 5));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            print("Cannot import $i");
            return i;
          }
          String m2 = wmdNotationToMoveString(i.substring(5));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            print("Cannot import $i");
            return i;
          }
        } else {
          // no x
          String m = wmdNotationToMoveString(i);
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

  String importDalmax(String moveList) {
    return import(moveList.substring(moveList.indexOf("1. ")));
  }

  String importPlayOk(String moveList) {
    List<Move> newHistory = [];

    List<String> list = moveList
        .replaceAll('\n', ' ')
        .replaceAll(' 1/2-1/2', '')
        .replaceAll(' 1-0', '')
        .replaceAll(' 0-1', '')
        .replaceAll('TXT', '')
        .split(' ');

    for (var i in list) {
      i = i.trim();

      if (i.length > 0 &&
          !i.endsWith(".") &&
          !i.startsWith("[") &&
          !i.endsWith("]")) {
        var iX = i.indexOf('x');
        if (iX == -1) {
          String m = playOkNotationToMoveString(i);
          if (m != "") {
            newHistory.add(Move(m));
          } else {
            print("Cannot import $i");
            return i;
          }
        } else if (iX != -1) {
          String m1 = playOkNotationToMoveString(i.substring(0, iX));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            print("Cannot import $i");
            return i;
          }
          String m2 = playOkNotationToMoveString(i.substring(iX));
          if (m2 != "") {
            newHistory.add(Move(m2));
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
    if (_history.length == 0) {
      return '';
    }

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

    moveHistoryText = moveHistoryText.replaceAll('    \n', '\n');

    return moveHistoryText;
  }
}
