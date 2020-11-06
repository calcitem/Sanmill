import '../mill/mill-base.dart';
import '../mill/position.dart';

class Battle {
  //
  static Battle _instance;

  Position _position;
  int _focusIndex, _blurIndex;

  static get shared {
    _instance ??= Battle();
    return _instance;
  }

  init() {
    _position = Position.defaultPosition();
    _focusIndex = _blurIndex = Move.invalidIndex;
  }

  newGame() {
    Battle.shared.position.initDefaultPosition();
    _focusIndex = _blurIndex = Move.invalidIndex;
  }

  select(int pos) {
    _focusIndex = pos;
    _blurIndex = Move.invalidIndex;
    //Audios.playTone('click.mp3');
  }

  bool move(int from, int to) {
    //
    final captured = _position.move(from, to);

    if (captured == null) {
      //Audios.playTone('invalid.mp3');
      return false;
    }

    _blurIndex = from;
    _focusIndex = to;

    return true;
  }

  bool regret({steps = 2}) {
    //
    // 轮到自己走棋的时候，才能悔棋
    if (_position.side != Side.white) {
      //Audios.playTone('invalid.mp3');
      return false;
    }

    var regreted = false;

    /// 悔棋一回合（两步），才能撤回自己上一次的动棋

    for (var i = 0; i < steps; i++) {
      //
      if (!_position.regret()) break;

      final lastMove = _position.lastMove;

      if (lastMove != null) {
        //
        _blurIndex = lastMove.from;
        _focusIndex = lastMove.to;
        //
      } else {
        //
        _blurIndex = _focusIndex = Move.invalidIndex;
      }

      regreted = true;
    }

    if (regreted) {
      //Audios.playTone('regret.mp3');
      return true;
    }

    //Audios.playTone('invalid.mp3');
    return false;
  }

  clear() {
    _blurIndex = _focusIndex = Move.invalidIndex;
  }

  BattleResult scanBattleResult() {
    //
    final forPerson = (_position.side == Side.white);

    if (scanLongCatch()) {
      // born 'repeat' position by oppo
      return forPerson ? BattleResult.win : BattleResult.lose;
    }

    return (_position.halfMove > 120)
        ? BattleResult.draw
        : BattleResult.pending;
  }

  scanLongCatch() {
    // todo:
    return false;
  }

  get position => _position;

  get focusIndex => _focusIndex;

  get blurIndex => _blurIndex;
}
