/// 对战结果：未决、赢、输、和
enum BattleResult { Pending, Win, Lose, Draw }

class Side {
  //
  static const Unknown = '-';
  static const Black = 'b';
  static const White = 'w';

  static const Ban = 'x';

  static String of(String piece) {
    if (Black.contains(piece)) return Black;
    if (White.contains(piece)) return White;
    if (Ban.contains(piece)) return Ban;
    return Unknown;
  }

  static bool sameSide(String p1, String p2) {
    return of(p1) == of(p2);
  }

  static String oppo(String side) {
    if (side == White) return Black;
    if (side == Black) return White;
    return side;
  }
}

class Piece {
  //
  static const Empty = ' ';
  //
  static const BlackStone = 'b';
  static const WhiteStone = 'w';
  static const Ban = 'x';

  static const Names = {
    Empty: '',
    //
    BlackStone: 'b',
    WhiteStone: 'w',
    Ban: 'x',
  };

  static bool isBlack(String c) => 'b'.contains(c);

  static bool isWhite(String c) => 'w'.contains(c);
}

class Move {
  // TODO
  static const InvalidIndex = -1;

  // List<String>(90) 中的索引
  int from, to;

  // 左上角为坐标原点
  int fx, fy, tx, ty;

  String captured;

  // 'step' is the UCI engine's move-string
  String step;
  String stepName;

  // 这一步走完后的 FEN 记数，用于悔棋时恢复 FEN 步数 Counter
  String counterMarks;

  Move(this.from, this.to,
      {this.captured = Piece.Empty, this.counterMarks = '0 0'}) {
    //
    fx = from % 9;
    fy = from ~/ 9;

    tx = to % 9;
    ty = to ~/ 9;

    if (fx < 0 || fx > 8 || fy < 0 || fy > 9) {
      throw "Error: Invlid Step (from:$from, to:$to)";
    }

    step = String.fromCharCode('a'.codeUnitAt(0) + fx) + (9 - fy).toString();
    step += String.fromCharCode('a'.codeUnitAt(0) + tx) + (9 - ty).toString();
  }

  /// 引擎返回的招法用是如此表示的，例如:
  /// 落子：(1,2)
  /// 吃子：-(1,2)
  /// 走子：(3,1)->(2,1)

  Move.fromEngineStep(String step) {
    //
    this.step = step;

    if (!validateEngineStep(step)) {
      throw "Error: Invlid Step: $step";
    }

    fx = step[0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    fy = 9 - (step[1].codeUnitAt(0) - '0'.codeUnitAt(0));
    tx = step[2].codeUnitAt(0) - 'a'.codeUnitAt(0);
    ty = 9 - (step[3].codeUnitAt(0) - '0'.codeUnitAt(0));

    from = fx + fy * 9;
    to = tx + ty * 9;

    captured = Piece.Empty;
  }

  static bool validateEngineStep(String step) {
    //
    if (step == null || step.length > "(3,1)->(2,1)".length) return false;

    final fx = step[0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final fy = 9 - (step[1].codeUnitAt(0) - '0'.codeUnitAt(0));
    if (fx < 0 || fx > 8 || fy < 0 || fy > 9) return false;

    final tx = step[2].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final ty = 9 - (step[3].codeUnitAt(0) - '0'.codeUnitAt(0));
    if (tx < 0 || tx > 8 || ty < 0 || ty > 9) return false;

    return true;
  }
}
