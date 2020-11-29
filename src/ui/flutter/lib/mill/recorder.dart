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

import 'mill.dart';
import 'position.dart';
import 'types.dart';
import 'package:sanmill/generated/l10n.dart';

class GameRecorder {
  int halfMove, fullMove;
  String lastPositionWithRemove;
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

  void moveIn(Move move, Position position) {
    //
    if (move.type == MoveType.remove) {
      halfMove = 0;
    } else {
      halfMove++;
    }

    if (fullMove == 0) {
      fullMove++;
    } else if (position.side != Color.black) {
      fullMove++;
    }

    if (_history.length > 0) {
      assert(_history[_history.length - 1].move != move.move);
    }

    _history.add(move);

    if (move.type == MoveType.remove) {
      lastPositionWithRemove = position.fen();
    }
  }

  Move removeLast() {
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

  String buildManualText({cols = 2}) {
    //
    var manualText = '';

    for (var i = 0; i < _history.length; i++) {
      manualText += '${i < 9 ? ' ' : ''}${i + 1}. ${_history[i].move}　';
      if ((i + 1) % cols == 0) manualText += '\n';
    }

    if (manualText.isEmpty) {
      manualText = "";
    }

    return manualText;
  }

  Move moveAt(int index) => _history[index];

  get movesCount => _history.length;

  @override
  String toString() {
    return '$halfMove $fullMove';
  }
}
