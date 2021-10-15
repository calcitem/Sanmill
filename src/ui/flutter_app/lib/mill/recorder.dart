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

import 'package:flutter/foundation.dart';
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/storage/storage.dart';

// TODO
class GameRecorder {
  int cur = -1;
  String? lastPositionWithRemove = "";
  List<Move> history = <Move>[];
  final tag = "[GameRecorder]";

  GameRecorder({this.cur = -1, this.lastPositionWithRemove});

  String wmdNotationToMoveString(String wmd) {
    String move = "";

    if (wmd.length == 3 && wmd[0] == "x") {
      if (wmdNotationToMove[wmd.substring(1, 3)] != null) {
        move = '-${wmdNotationToMove[wmd.substring(1, 3)]!}';
      }
    } else if (wmd.length == 2) {
      if (wmdNotationToMove[wmd] != null) {
        move = wmdNotationToMove[wmd]!;
      }
    } else if (wmd.length == 5 && wmd[2] == '-') {
      if (wmdNotationToMove[(wmd.substring(0, 2))] != null &&
          wmdNotationToMove[(wmd.substring(3, 5))] != null) {
        move =
            '${wmdNotationToMove[(wmd.substring(0, 2))]!}->${wmdNotationToMove[(wmd.substring(3, 5))]!}';
      }
    } else if ((wmd.length == 8 && wmd[2] == '-' && wmd[5] == 'x') ||
        (wmd.length == 5 && wmd[2] == 'x')) {
      debugPrint("$tag Not support parsing format oo-ooxo notation.");
    } else {
      debugPrint("$tag Parse notation $wmd failed.");
    }

    return move;
  }

  String playOkNotationToMoveString(String playOk) {
    String move = "";

    if (playOk.isEmpty) {
      return "";
    }

    final iDash = playOk.indexOf('-');
    final iX = playOk.indexOf('x');

    if (iDash == -1 && iX == -1) {
      // 12
      final val = int.parse(playOk);
      if (val >= 1 && val <= 24) {
        return playOkNotationToMove[playOk]!;
      } else {
        debugPrint("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }

    if (iX == 0) {
      // x12
      final sub = playOk.substring(1);
      final val = int.parse(sub);
      if (val >= 1 && val <= 24) {
        return "-${playOkNotationToMove[sub]!}";
      } else {
        debugPrint("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }
    if (iDash != -1 && iX == -1) {
      // 12-13
      final sub1 = playOk.substring(0, iDash);
      final val1 = int.parse(sub1);
      if (val1 >= 1 && val1 <= 24) {
        move = playOkNotationToMove[sub1]!;
      } else {
        debugPrint("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }

      final sub2 = playOk.substring(iDash + 1);
      final val2 = int.parse(sub2);
      if (val2 >= 1 && val2 <= 24) {
        return "$move->${playOkNotationToMove[sub2]!}";
      } else {
        debugPrint("$tag Parse PlayOK notation $playOk failed.");
        return "";
      }
    }

    debugPrint("$tag Not support parsing format oo-ooxo PlayOK notation.");
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

    if (text.isNotEmpty && text[0] == '[') {
      return true;
    }

    return false;
  }

  bool isGoldTokenMoveList(String text) {
    if (text.length >= 10 &&
        (text.substring(0, 9) == "GoldToken" ||
            text.substring(0, 10) == "Past Moves" ||
            text.substring(0, 5) == "Go to" ||
            text.substring(0, 4) == "Turn" ||
            text.substring(0, 8) == "(Player ")) {
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

    if (isGoldTokenMoveList(moveList)) {
      return importGoldToken(moveList);
    }

    final List<Move> newHistory = [];
    final List<String> list = moveList
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
        // GoldToken
        .replaceAll('\t', ' ')
        .replaceAll('place to ', '')
        .replaceAll('  take ', 'x')
        .replaceAll(' -> ', '-')
        // Finally
        .split(' ');

    for (var i in list) {
      i = i.trim();

      if (int.tryParse(i) != null) {
        i = '$i.';
      }

      if (i.isNotEmpty && !i.endsWith(".")) {
        if (i.length == 5 && i[2] == 'x') {
          // "a1xc3"
          final String m1 = wmdNotationToMoveString(i.substring(0, 2));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
          final String m2 = wmdNotationToMoveString(i.substring(2));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
        } else if (i.length == 8 && i[2] == '-' && i[5] == 'x') {
          // "a1-b2xc3"
          final String m1 = wmdNotationToMoveString(i.substring(0, 5));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
          final String m2 = wmdNotationToMoveString(i.substring(5));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
        } else {
          // no x
          final String m = wmdNotationToMoveString(i);
          if (m != "") {
            newHistory.add(Move(m));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
        }
      }
    }

    if (newHistory.isNotEmpty) {
      history = newHistory;
    }

    return "";
  }

  String importDalmax(String moveList) {
    return import(moveList.substring(moveList.indexOf("1. ")));
  }

  String importPlayOk(String moveList) {
    final List<Move> newHistory = [];

    final List<String> list = moveList
        .replaceAll('\n', ' ')
        .replaceAll(' 1/2-1/2', '')
        .replaceAll(' 1-0', '')
        .replaceAll(' 0-1', '')
        .replaceAll('TXT', '')
        .split(' ');

    for (var i in list) {
      i = i.trim();

      if (i.isNotEmpty &&
          !i.endsWith(".") &&
          !i.startsWith("[") &&
          !i.endsWith("]")) {
        final iX = i.indexOf('x');
        if (iX == -1) {
          final String m = playOkNotationToMoveString(i);
          if (m != "") {
            newHistory.add(Move(m));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
        } else if (iX != -1) {
          final String m1 = playOkNotationToMoveString(i.substring(0, iX));
          if (m1 != "") {
            newHistory.add(Move(m1));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
          final String m2 = playOkNotationToMoveString(i.substring(iX));
          if (m2 != "") {
            newHistory.add(Move(m2));
          } else {
            debugPrint("Cannot import $i");
            return i;
          }
        }
      }
    }

    if (newHistory.isNotEmpty) {
      history = newHistory;
    }

    return "";
  }

  String importGoldToken(String moveList) {
    int start = moveList.indexOf("1\t");

    if (start == -1) {
      start = moveList.indexOf("1 ");
    }

    if (start == -1) {
      start = 0;
    }

    return import(moveList.substring(start));
  }

  void jumpToHead() {
    cur = 0;
  }

  void jumpToTail() {
    cur = history.length - 1;
  }

  void clear() {
    history.clear();
    cur = 0;
  }

  bool isClean() {
    return cur == history.length - 1;
  }

  void prune() {
    if (isClean()) {
      return;
    }

    history.removeRange(cur + 1, history.length);
  }

  void moveIn(Move move, Position position) {
    if (history.isNotEmpty) {
      if (history[history.length - 1].move == move.move) {
        //assert(false);
        // TODO: WAR
        return;
      }
    }

    history.add(move);
    cur++;

    if (move.type == MoveType.remove) {
      lastPositionWithRemove = position.fen();
    }
  }

  Move? removeLast() {
    if (history.isEmpty) return null;
    return history.removeLast();
  }

  Move? get last => history.isEmpty ? null : history.last;

  Move moveAt(int index) => history[index];

  int get movesCount => history.length;

  Move? get lastMove => movesCount == 0 ? null : moveAt(movesCount - 1);

  Move? get lastEffectiveMove => cur == -1 ? null : moveAt(cur);

  String buildMoveHistoryText({int cols = 2}) {
    if (history.isEmpty) {
      return '';
    }

    var moveHistoryText = '';
    int k = 1;
    String num = "";

    for (var i = 0; i <= cur; i++) {
      if (LocalDatabaseService.display.standardNotationEnabled) {
        if (k % cols == 1) {
          num = "${(k + 1) ~/ 2}.    ";
          if (k < 9 * cols) {
            num = " $num ";
          }
        } else {
          num = "";
        }
        if (i + 1 <= cur && history[i + 1].type == MoveType.remove) {
          moveHistoryText +=
              '$num${history[i].notation}${history[i + 1].notation}    ';
          i++;
        } else {
          moveHistoryText += '$num${history[i].notation}    ';
        }
        k++;
      } else {
        moveHistoryText += '${i < 9 ? ' ' : ''}${i + 1}. ${history[i].move}　';
      }

      if (LocalDatabaseService.display.standardNotationEnabled) {
        if ((k + 1) % cols == 0) moveHistoryText += '\n';
      } else {
        if ((i + 1) % cols == 0) moveHistoryText += '\n';
      }
    }

    if (moveHistoryText.isEmpty) {
      moveHistoryText = "";
    }

    return moveHistoryText.replaceAll('    \n', '\n');
  }
}
