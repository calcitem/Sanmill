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

import 'package:flutter/cupertino.dart';

import '../common/types.dart';
import '../mill/mill.dart';
import '../mill/recorder.dart';
import '../mill/rule.dart';

class StateInfo {
  /*
  // Copied when making a move
  int rule50 = 0;
  int pliesFromNull = 0;


  get rule50 => _rule50;
  set rule50(int value) => _rule50 = value;

  get pliesFromNull => _pliesFromNull;
  set pliesFromNull(int value) => _pliesFromNull = value;
  */
}

class Position {
  GameResult result = GameResult.pending;

  List<String> _board = List<String>(40);
  List<String> _grid = List<String>(49); // 7  *  7

  MillRecorder _recorder;

  int pieceCountInHandBlack = 12;
  int pieceCountInHandWhite = 12;
  int pieceCountOnBoardBlack = 0;
  int pieceCountOnBoardWhite = 0;
  int pieceCountNeedRemove = 0;

  int gamePly = 0;
  String _sideToMove = Color.black;

  int rule50 = 0;
  int pliesFromNull = 0;

  StateInfo st;

  String them;
  String winner;
  GameOverReason gameOverReason = GameOverReason.noReason;

  Phase phase = Phase.none;
  Act action = Act.none;

  int scoreBlack = 0;
  int scoreWhite = 0;
  int scoreDraw = 0;

  int currentSquare;
  int nPlayed = 0;

  String cmdline;

  //int _move;

  Position.init() {
    for (var i = 0; i < _grid.length; i++) {
      _grid[i] ??= Piece.noPiece;
    }

    for (var i = 0; i < _board.length; i++) {
      _board[i] ??= Piece.noPiece;
    }

    phase = Phase.placing;

    // Example
    //_board[sqToLoc[8]] = Piece.blackStone;

    _recorder = MillRecorder(lastCapturedPosition: fen());
  }

  init() {
    Position.init();
  }

  Position.boardToGrid() {
    _grid = List<String>();
    for (int sq = 0; sq < _board.length; sq++) {
      _grid[squareToIndex[sq]] = _board[sq];
    }
  }

  Position.gridToBoard() {
    _board = List<String>();
    for (int i = 0; i < _grid.length; i++) {
      _board[indexToSquare[i]] = _grid[i];
    }
  }

  Position.clone(Position other) {
    _grid = List<String>();
    other._grid.forEach((piece) => _grid.add(piece));

    _board = List<String>();
    other._board.forEach((piece) => _board.add(piece));

    _recorder = other._recorder;

    pieceCountInHandBlack = other.pieceCountInHandBlack;
    pieceCountInHandWhite = other.pieceCountInHandWhite;
    pieceCountOnBoardBlack = other.pieceCountOnBoardBlack;
    pieceCountOnBoardWhite = other.pieceCountOnBoardWhite;
    pieceCountNeedRemove = other.pieceCountNeedRemove;

    gamePly = other.gamePly;

    _sideToMove = other._sideToMove;

    rule50 = other.rule50;
    pliesFromNull = other.pliesFromNull;

    them = other.them;
    winner = other.winner;
    gameOverReason = other.gameOverReason;

    phase = other.phase;
    action = other.action;

    scoreBlack = other.scoreBlack;
    scoreWhite = other.scoreWhite;
    scoreDraw = other.scoreDraw;

    currentSquare = other.currentSquare;
    nPlayed = other.nPlayed;
  }

  String pieceOnGrid(int index) => _grid[index];
  String pieceOn(int sq) => _board[sq];

  bool empty(int sq) => pieceOn(sq) == Piece.noPiece;

  void updateScore() {}

  void setSideToMove(String color) {
    _sideToMove = color;
  }

  String movedPiece(int move) {
    return pieceOn(fromSq(move));
  }

  bool selectPieceFR(int file, int rank) {
    return selectPieceSQ(makeSquare(file, rank));
  }

  bool putPiece(var pt, int index) {
    var sq = indexToSquare[index];

    if (sq == null) {
      print("putPiece skip index: $index");
      return false;
    }

    _grid[index] = pt;
    _board[sq] = pt;

    print("putPiece: pt = $pt, index = $index, sq = $sq");

    return true;
  }

  bool putPieceFR(int file, int rank) {
    bool ret = putPieceSQ(makeSquare(file, rank));

    if (ret) {
      updateScore();
    }

    return ret;
  }

  bool movePieceFR(int file1, int rank1, int file2, int rank2) {
    return movePieceSQ(makeSquare(file1, rank1), makeSquare(file2, rank2));
  }

  bool removePieceFR(int file, int rank) {
    bool ret = removePieceSQ(makeSquare(file, rank));

    if (ret) {
      updateScore();
    }

    return ret;
  }

  bool selectPieceSQ(int sq) {
    // TODO
    return false;
  }

  bool putPieceSQ(int sq) {
    // TODO
    return false;
  }

  bool movePieceSQ(int fromSq, int toSq) {
    // TODO
    return false;
  }

  bool removePieceSQ(int sq) {
    // TODO
    return false;
  }

  bool movePiece(int fromSq, int toSq) {
    if (selectPieceSQ(fromSq)) {
      return putPieceSQ(toSq);
    }

    return false;
  }

  void set(String fenStr) {
    /*
       A FEN string defines a particular position using only the ASCII character set.

       A FEN string contains six fields separated by a space. The fields are:

       1) Piece placement. Each rank is described, starting
          with rank 1 and ending with rank 8. Within each rank, the contents of each
          square are described from file A through file C. Following the Standard
          Algebraic Notation (SAN), each piece is identified by a single letter taken
          from the standard English names. White pieces are designated using "O"
          whilst Black uses "@". Blank uses "*". Banned uses "X".
          noted using digits 1 through 8 (the number of blank squares), and "/"
          separates ranks.

       2) Active color. "w" means white moves next, "b" means black.

       3) Phrase.

       4) Action.

       5) Black on board/Black in hand/White on board/White in hand/need to remove

       6) Halfmove clock. This is the number of halfmoves since the last
          capture. This is used to determine if a draw can be claimed under the
          fifty-move rule.

       7) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after Black's move.
    */

    // TODO
    return;
  }

  /// fen() returns a FEN representation of the position.

  String fen() {
    var ss = '';

    // Piece placement data
    for (var file = 1; file <= 3; file++) {
      for (var rank = 1; rank <= 8; rank++) {
        //
        final piece = pieceOnGrid(squareToIndex[makeSquare(file, rank)]);
        ss += piece;
      }

      if (file == 3)
        ss += ' ';
      else
        ss += '/';
    }

    // Active color
    ss += _sideToMove;

    ss += " ";

    // Phrase
    switch (phase) {
      case Phase.none:
        ss += "n";
        break;
      case Phase.ready:
        ss += "r";
        break;
      case Phase.placing:
        ss += "p";
        break;
      case Phase.moving:
        ss += "m";
        break;
      case Phase.gameOver:
        ss += "o";
        break;
      default:
        ss += "?";
        break;
    }

    ss += " ";

    // Action
    switch (action) {
      case Act.place:
        ss += "p";
        break;
      case Act.select:
        ss += "s";
        break;
      case Act.remove:
        ss += "r";
        break;
      default:
        ss += "?";
        break;
    }

    ss += " ";

    ss += pieceCountOnBoardBlack.toString() +
        " " +
        pieceCountInHandBlack.toString() +
        " " +
        pieceCountOnBoardWhite.toString() +
        " " +
        pieceCountInHandWhite.toString() +
        " " +
        pieceCountNeedRemove.toString() +
        " ";

    int sideIsBlack = _sideToMove == Color.black ? 1 : 0;

    ss +=
        rule50.toString() + " " + (1 + (gamePly - sideIsBlack) ~/ 2).toString();

    // step counter
    //ss += '${_recorder?.halfMove ?? 0} ${_recorder?.fullMove ?? 0}';

    print("fen = " + ss);

    return ss;
  }

  /// Position::legal() tests whether a pseudo-legal move is legal

  bool legal(int move) {
    assert(isOk(move));

    String us = _sideToMove;
    int fromSQ = fromSq(move);
    int toSQ = toSq(move);

    if (fromSQ == toSQ) {
      return false; // TODO: Same with is_ok(m)
    }

    if (phase == Phase.moving && typeOf(move) != MoveType.remove) {
      if (movedPiece(move) != us) {
        return false;
      }
    }

    // TODO: Add more

    return true;
  }

  /// Position::pseudo_legal() takes a random move and tests whether the move is
  /// pseudo legal. It is used to validate moves from TT that can be corrupted
  /// due to SMP concurrent access or hash position key aliasing.

  bool pseudoLegal(int move) {
    // TODO
    return legal(move);
  }

  /*
  /// Position::do_move() makes a move, and saves all information necessary
  /// to a StateInfo object. The move is assumed to be legal. Pseudo-legal
  /// moves should be filtered out before this function is called.

  void doMove(int move) {
    bool ret = false;

    MoveType mt = typeOf(move);

    switch (mt) {
      case MoveType.remove:
        // Reset rule 50 counter
        rule50 = 0;
        ret = removePiece(toSq(move));
        break;
      case MoveType.move:
        ret = movePiece(fromSq(move), toSq(move));
        break;
      case MoveType.place:
        ret = putPieceSQ(toSq(move));
        break;
      default:
        break;
    }

    if (!ret) {
      return;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++gamePly;
    ++rule50;
    ++pliesFromNull;

    _move = move;
  }
  */

  bool doMove(Move move) {
    //
    //if (!validateMove(m)) return null;

    //final move = Move(m);

    if (move.type == MoveType.remove) {
      final captured = _grid[move.to];
    }

    switch (move.type) {
      case MoveType.place:
        _grid[move.toIndex] = _board[move.to] = _sideToMove;
        break;
      case MoveType.remove:
        _grid[move.toIndex] = _board[move.to] = Piece.noPiece;
        break;
      case MoveType.move:
        _grid[move.toIndex] = _grid[move.fromIndex];
        _board[move.to] = _board[move.from];
        _grid[move.fromIndex] = _board[move.from] = Piece.noPiece;
        break;
      default:
        assert(false);
        break;
    }

    //StepName.translate(this, move);
    _recorder.stepIn(move, this);

    // 交换走棋方
    _sideToMove = Color.opponent(_sideToMove);

    return true;
  }

  // 验证移动棋子的着法是否合法
  bool validateMove(int from, int to) {
    // 移动的棋子的选手，应该是当前方
    //if (Color.of(_board[from]) != _sideToMove) return false;
    return true;
    //(StepValidate.validate(this, Move(from, to)));
  }

  // 在判断行棋合法性等环节，要在克隆的棋盘上进行行棋假设，然后检查效果
  // 这种情况下不验证、不记录、不翻译
  void moveTest(Move move, {turnSide = false}) {
    //
    // 修改棋盘
    _grid[move.to] = _grid[move.from];
    _grid[move.from] = Piece.noPiece;
    _board[move.to] = _board[move.from];
    _board[move.from] = Piece.noPiece;

    // 交换走棋方
    if (turnSide) _sideToMove = Color.opponent(_sideToMove);
  }

  bool regret() {
    //
    final lastMove = _recorder.removeLast();
    if (lastMove == null) return false;

    _grid[lastMove.from] = _grid[lastMove.to];
    _grid[lastMove.to] = lastMove.captured;
    _board[lastMove.from] = _board[lastMove.to];
    _board[lastMove.to] = lastMove.captured;

    _sideToMove = Color.opponent(_sideToMove);

    final counterMarks = MillRecorder.fromCounterMarks(lastMove.counterMarks);
    _recorder.halfMove = counterMarks.halfMove;
    _recorder.fullMove = counterMarks.fullMove;

    if (lastMove.captured != Piece.noPiece) {
      //
      // 查找上一个吃子局面（或开局），NativeEngine 需要
      final tempPosition = Position.clone(this);

      final moves = _recorder.reverseMovesToPrevCapture();
      moves.forEach((move) {
        //
        tempPosition._grid[move.from] = tempPosition._grid[move.to];
        tempPosition._grid[move.to] = move.captured;

        tempPosition._sideToMove = Color.opponent(tempPosition._sideToMove);
      });

      _recorder.lastCapturedPosition = tempPosition.fen();
    }

    result = GameResult.pending;

    return true;
  }

  String movesSinceLastCaptured() {
    //
    var steps = '', posAfterLastCaptured = 0;

    for (var i = _recorder.stepsCount - 1; i >= 0; i--) {
      if (_recorder.stepAt(i).captured != Piece.noPiece) break;
      posAfterLastCaptured = i;
    }

    for (var i = posAfterLastCaptured; i < _recorder.stepsCount; i++) {
      steps += ' ${_recorder.stepAt(i).move}';
    }

    return steps.length > 0 ? steps.substring(1) : '';
  }

  get manualText => _recorder.buildManualText();

  get side => _sideToMove;

  changeSideToMove() => _sideToMove = Color.opponent(_sideToMove);

  get halfMove => _recorder.halfMove;

  get fullMove => _recorder.fullMove;

  get lastMove => _recorder.last;

  get lastCapturedPosition => _recorder.lastCapturedPosition;

///////////////////////////////////////////////////////////////////////////////

  int piecesOnBoardCount() {
    pieceCountOnBoardBlack = pieceCountOnBoardWhite = 0;

    for (int f = 1; f < 3 + 2; f++) {
      for (int r = 0; r < 8; r++) {
        int s = f * 8 + r;
        if (_board[s] == Piece.blackStone) {
          pieceCountOnBoardBlack++;
        } else if (_board[s] == Piece.whiteStone) {
          pieceCountOnBoardBlack++;
        }
      }
    }

    if (pieceCountOnBoardBlack > rule.nTotalPiecesEachSide ||
        pieceCountOnBoardWhite > rule.nTotalPiecesEachSide) {
      return -1;
    }

    return pieceCountOnBoardBlack + pieceCountOnBoardWhite;
  }

  int piecesInHandCount() {
    pieceCountInHandBlack = rule.nTotalPiecesEachSide - pieceCountOnBoardBlack;
    pieceCountInHandWhite = rule.nTotalPiecesEachSide - pieceCountOnBoardWhite;

    return pieceCountOnBoardBlack + pieceCountOnBoardWhite;
  }

  int setPosition(Rule newRule) {
    rule = newRule;

    gamePly = 0;
    rule50 = 0;

    phase = Phase.ready;
    setSideToMove(Color.black);
    action = Act.place;

    for (int i = 0; i < _grid.length; i++) _grid[i] = Piece.noPiece;

    for (int i = 0; i < _board.length; i++) _board[i] = Piece.noPiece;

    if (piecesOnBoardCount() == -1) {
      return -1;
    }

    piecesInHandCount();
    pieceCountNeedRemove = 0;

    winner = Color.unknown;

    currentSquare = 0;
    return -1;
  }

  bool reset() {
    gamePly = 0;
    rule50 = 0;

    phase = Phase.ready;
    setSideToMove(Color.black);
    action = Act.place;

    winner = Color.unknown;
    gameOverReason = GameOverReason.noReason;

    for (int i = 0; i < _grid.length; i++) _grid[i] = Piece.noPiece;

    for (int i = 0; i < _board.length; i++) _board[i] = Piece.noPiece;

    pieceCountOnBoardBlack = pieceCountOnBoardWhite = 0;
    pieceCountInHandBlack = pieceCountInHandWhite = rule.nTotalPiecesEachSide;
    pieceCountNeedRemove = 0;

    currentSquare = 0;
    int i = 0; // TODO: rule

    cmdline = "r" +
        (i + 1).toString() +
        " " +
        "s" +
        rule.maxStepsLedToDraw.toString() +
        " t" +
        0.toString();

    return false;
  }

  bool start() {
    gameOverReason = GameOverReason.noReason;

    switch (phase) {
      case Phase.placing:
      case Phase.moving:
        return false;
      case Phase.gameOver:
        reset();
        continue ready;
      ready:
      case Phase.ready:
        phase = Phase.placing;
        return true;
      default:
        return false;
    }
  }

  /*
  bool putPiece(int sq)
  {
    String piece = Piece.noPiece;
    String us = _sideToMove;

    if (phase == Phase.gameOver ||
        action != Act.place ||
        sq < 0 || sq >= 31 || _board[sq] != Piece.noPiece) {
      return false;
    }

    if (phase == Phase.ready) {
      start();
    }

    if (phase == Phase.placing) {
      piece = _sideToMove;
      if (_sideToMove == Color.black) {
        pieceCountInHandBlack--;
        pieceCountOnBoardBlack++;
      }
      else if (_sideToMove == Color.white) {
        pieceCountInHandWhite--;
        pieceCountOnBoardWhite++;
      }

      _board[sq]= piece;
      _grid[squareToIndex[sq]] = piece;

      cmdline = "(" + fileOf(sq).toString() + "," + rankOf(sq).toString() + ")";

      currentSquare = sq;

      int n = addMills(currentSquare);

      if (n == 0) {
        assert(pieceCountInHandBlack >= 0 && pieceCountInHandWhite >= 0);

        if (pieceCountInHandBlack == 0 && pieceCountInHandWhite == 0) {
          if (checkGameOverCondition()) {
            return true;
          }

          phase = Phase.moving;
          action = Act.select;

          if (rule.hasBannedLocations) {
            removeBanStones();
          }

          if (!rule.isDefenderMoveFirst) {
            changeSideToMove();
          }

          if (checkGameOverCondition()) {
            return true;
          }
        } else {
          changeSideToMove();
        }
      } else {
        pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
        action = Act.remove;
  }

  } else if (phase == Phase.moving) {

  if (checkGameOverCondition()) {
  return true;
  }

  // if illegal
  if (pieceCountOnBoard[sideToMove] > rule->nPiecesAtLeast ||
  !rule->allowFlyWhenRemainThreePieces) {
  int md;

  for (md = 0; md < MD_NB; md++) {
  if (s == MoveList<LEGAL>::moveTable[currentSquare][md])
  break;
  }

  // not in moveTable
  if (md == MD_NB) {
  return false;
  }
  }

  if (updateCmdlist) {
  sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)",
  file_of(currentSquare), rank_of(currentSquare),
  file_of(s), rank_of(s));
  st.rule50++;
  }

  board[s] = board[currentSquare];

  board[currentSquare] = NO_PIECE;

  currentSquare = s;
  int n = add_mills(currentSquare);

  // midgame
  if (n == 0) {
  action = ACTION_SELECT;
  change_side_to_move();

  if (check_gameover_condition()) {
  return true;
  }
  } else {
  pieceCountNeedRemove = rule->allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
  update_key_misc();
  action = ACTION_REMOVE;
  }
  } else {
  assert(0);
  }

    return true;
  }
   */
}
