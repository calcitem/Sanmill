import 'mill-base.dart';
import 'position.dart';

class MillRecorder {
  //
  // 无吃子步数、总回合数
  int halfMove, fullMove;
  String lastCapturedPosition;
  final _history = <Move>[];

  MillRecorder(
      {this.halfMove = 0, this.fullMove = 0, this.lastCapturedPosition});
  MillRecorder.fromCounterMarks(String marks) {
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
  void stepIn(Move move, Position position) {
    //
    if (move.captured != Piece.Empty) {
      halfMove = 0;
    } else {
      halfMove++;
    }

    if (fullMove == 0) {
      fullMove++;
    } else if (position.side != Side.Black) {
      fullMove++;
    }

    _history.add(move);

    if (move.captured != Piece.Empty) {
      lastCapturedPosition = position.toFen();
    }
  }

  Move removeLast() {
    if (_history.isEmpty) return null;
    return _history.removeLast();
  }

  get last => _history.isEmpty ? null : _history.last;

  List<Move> reverseMovesToPrevCapture() {
    //
    List<Move> moves = [];

    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].captured != Piece.Empty) break;
      moves.add(_history[i]);
    }

    return moves;
  }

  String buildManualText({cols = 2}) {
    //
    var manualText = '';

    for (var i = 0; i < _history.length; i++) {
      manualText += '${i < 9 ? ' ' : ''}${i + 1}. ${_history[i].stepName}　';
      if ((i + 1) % cols == 0) manualText += '\n';
    }

    if (manualText.isEmpty) {
      manualText = '<暂无招法>';
    }

    return manualText;
  }

  Move stepAt(int index) => _history[index];

  get stepsCount => _history.length;

  @override
  String toString() {
    return '$halfMove $fullMove';
  }
}
