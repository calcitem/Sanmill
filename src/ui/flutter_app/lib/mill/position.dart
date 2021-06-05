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

import 'package:sanmill/engine/engine.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/recorder.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/services/audios.dart';

import 'mills.dart';
import 'types.dart';
import 'zobrist.dart';

List<int> posKeyHistory = [];

class StateInfo {
  // Copied when making a move
  int rule50 = 0;
  int pliesFromNull = 0;

  // Not copied when making a move (will be recomputed anyhow)
  int key = 0;
}

class Position {
  GameResult result = GameResult.pending;

  List<String> board = List.filled(sqNumber, "");
  List<String> _grid = List.filled(7 * 7, "");

  GameRecorder? recorder;

  Map<String, int> pieceInHandCount = {
    PieceColor.white: -1,
    PieceColor.black: -1
  };
  Map<String, int> pieceOnBoardCount = {
    PieceColor.white: 0,
    PieceColor.black: 0
  };
  int pieceToRemoveCount = 0;

  int gamePly = 0;
  String _sideToMove = PieceColor.white;

  StateInfo st = StateInfo();

  String us = PieceColor.white;
  String them = PieceColor.black;
  String winner = PieceColor.nobody;

  GameOverReason gameOverReason = GameOverReason.noReason;

  Phase phase = Phase.none;
  Act action = Act.none;

  Map<String, int> score = {
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0
  };

  int currentSquare = 0;
  int nPlayed = 0;

  String? record;

  static late var millTable;
  static late var adjacentSquares;

  late Move move;

  Position.clone(Position other) {
    _grid = [];
    other._grid.forEach((piece) => _grid.add(piece));

    board = [];
    other.board.forEach((piece) => board.add(piece));

    recorder = other.recorder;

    pieceInHandCount = other.pieceInHandCount;
    pieceOnBoardCount = other.pieceOnBoardCount;
    pieceToRemoveCount = other.pieceToRemoveCount;

    gamePly = other.gamePly;

    _sideToMove = other._sideToMove;

    st.rule50 = other.st.rule50;
    st.pliesFromNull = other.st.pliesFromNull;

    them = other.them;
    winner = other.winner;
    gameOverReason = other.gameOverReason;

    phase = other.phase;
    action = other.action;

    score = other.score;

    currentSquare = other.currentSquare;
    nPlayed = other.nPlayed;
  }

  String pieceOnGrid(int index) => _grid[index];
  String pieceOn(int sq) => board[sq];

  bool empty(int sq) => pieceOn(sq) == Piece.noPiece;

  String sideToMove() => _sideToMove;

  String movedPiece(int move) {
    return pieceOn(fromSq(move));
  }

  bool movePiece(int from, int to) {
    if (selectPiece(from) == 0) {
      return putPiece(to);
    }

    return false;
  }

  init() {
    for (var i = 0; i < _grid.length; i++) {
      _grid[i] = Piece.noPiece;
    }

    for (var i = 0; i < board.length; i++) {
      board[i] = Piece.noPiece;
    }

    phase = Phase.placing;

    setPosition(rule); // TODO

    // TODO
    recorder = GameRecorder(lastPositionWithRemove: fen());
  }

  Position() {
    init();
  }

  /// fen() returns a FEN representation of the position.

  String fen() {
    var ss = '';

    // Piece placement data
    for (var file = 1; file <= fileNumber; file++) {
      for (var rank = 1; rank <= rankNumber; rank++) {
        final piece = pieceOnGrid(squareToIndex[makeSquare(file, rank)]!);
        ss += piece;
      }

      if (file == 3)
        ss += ' ';
      else
        ss += '/';
    }

    // Active color
    ss += _sideToMove == PieceColor.white ? "w" : "b";

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

    ss += pieceOnBoardCount[PieceColor.white].toString() +
        " " +
        pieceInHandCount[PieceColor.white].toString() +
        " " +
        pieceOnBoardCount[PieceColor.black].toString() +
        " " +
        pieceInHandCount[PieceColor.black].toString() +
        " " +
        pieceToRemoveCount.toString() +
        " ";

    int sideIsBlack = _sideToMove == PieceColor.black ? 1 : 0;

    ss += st.rule50.toString() +
        " " +
        (1 + (gamePly - sideIsBlack) ~/ 2).toString();

    //print("FEN is $ss");

    return ss;
  }

  /// Position::legal() tests whether a pseudo-legal move is legal

  bool legal(Move move) {
    if (!isOk(move.from) || !isOk(move.to)) return false;

    String us = _sideToMove;

    if (move.from == move.to) {
      print("[position] Move $move.move from == to");
      return false;
    }

    if (move.type == MoveType.remove) {
      if (movedPiece(move.to) != us) {
        print("[position] Move $move.to to != us");
        return false;
      }
    }

    return true;
  }

  bool doMove(String move) {
    if (move.length > "Player".length &&
        move.substring(0, "Player".length - 1) == "Player") {
      if (move["Player".length] == '1') {
        return resign(PieceColor.white);
      } else {
        return resign(PieceColor.black);
      }
    }

    // TODO
    if (move == "Threefold Repetition. Draw!") {
      return true;
    }

    if (move == "draw") {
      phase = Phase.gameOver;
      winner = PieceColor.draw;
      if (score[PieceColor.draw] != null) {
        score[PieceColor.draw] = score[PieceColor.draw]! + 1;
      }

      // TODO: WAR to judge rule50
      if (rule.maxStepsLedToDraw > 0 &&
          posKeyHistory.length > rule.maxStepsLedToDraw - 1) {
        gameOverReason = GameOverReason.drawReasonRule50;
      } else {
        gameOverReason = GameOverReason.drawReasonThreefoldRepetition;
      }
      return true;
    }

    // TODO: Above is diff from position.cpp

    bool ret = false;

    Move m = Move(move);

    switch (m.type) {
      case MoveType.remove:
        ret = (removePiece(m.to) == 0);
        if (ret) {
          // Reset rule 50 counter
          st.rule50 = 0;
        }
        break;
      case MoveType.move:
        ret = movePiece(m.from, m.to);
        if (ret) {
          ++st.rule50;
        }
        break;
      case MoveType.place:
        ret = putPiece(m.to);
        if (ret) {
          // Reset rule 50 counter
          st.rule50 = 0;
        }
        break;
      default:
        assert(false);
        break;
    }

    if (!ret) {
      return false;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++gamePly;
    ++st.pliesFromNull;

    if (record != null && record!.length > "-(1,2)".length) {
      if (posKeyHistory.length == 0 ||
          (posKeyHistory.length > 0 &&
              st.key != posKeyHistory[posKeyHistory.length - 1])) {
        posKeyHistory.add(st.key);
        if (hasGameCycle()) {
          setGameOver(
              PieceColor.draw, GameOverReason.drawReasonThreefoldRepetition);
        }
      }
    } else {
      posKeyHistory.clear();
    }

    this.move = m;

    recorder!.moveIn(m, this); // TODO: Is Right?

    return true;
  }

  bool hasRepeated(List<Position> ss) {
    for (int i = posKeyHistory.length - 2; i >= 0; i--) {
      if (st.key == posKeyHistory[i]) {
        return true;
      }
    }

    int size = ss.length;

    for (int i = size - 1; i >= 0; i--) {
      if (ss[i].move.type == MoveType.remove) {
        break;
      }
      if (st.key == ss[i].st.key) {
        return true;
      }
    }

    return false;
  }

  /// hasGameCycle() tests if the position has a move which draws by repetition.

  bool hasGameCycle() {
    int repetition = 0; // Note: Engine is global val
    for (var i in posKeyHistory) {
      if (st.key == i) {
        repetition++;
        if (repetition == 3) {
          print("[position] Has game cycle.");
          return true;
        }
      }
    }

    return false;
  }

///////////////////////////////////////////////////////////////////////////////

  /// Mill Game

  bool reset() {
    gamePly = 0;
    st.rule50 = 0;

    phase = Phase.ready;
    setSideToMove(PieceColor.white);
    action = Act.place;

    winner = PieceColor.nobody;
    gameOverReason = GameOverReason.noReason;

    clearBoard();

    st.key = 0;

    pieceOnBoardCount[PieceColor.white] =
        pieceOnBoardCount[PieceColor.black] = 0;
    pieceInHandCount[PieceColor.white] =
        pieceInHandCount[PieceColor.black] = rule.piecesCount;
    pieceToRemoveCount = 0;

    // TODO:
    // MoveList<LEGAL>::create();
    // create_mill_table();

    currentSquare = 0;

    record = "";

    return true;
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

  bool putPiece(int s) {
    var piece = Piece.noPiece;
    var us = _sideToMove;

    if (phase == Phase.gameOver ||
        action != Act.place ||
        !(sqBegin <= s && s < sqEnd) ||
        board[s] != Piece.noPiece) {
      return false;
    }

    if (phase == Phase.ready) {
      start();
    }

    if (phase == Phase.placing) {
      piece = sideToMove();
      if (pieceInHandCount[us] != null) {
        pieceInHandCount[us] = pieceInHandCount[us]! - 1;
      }

      if (pieceOnBoardCount[us] != null) {
        pieceOnBoardCount[us] = pieceOnBoardCount[us]! + 1;
      }

      _grid[squareToIndex[s]!] = piece;
      board[s] = piece;

      record = "(" + fileOf(s).toString() + "," + rankOf(s).toString() + ")";

      updateKey(s);

      currentSquare = s;

      int n = millsCount(currentSquare);

      if (n == 0) {
        assert(pieceInHandCount[PieceColor.white]! >= 0 &&
            pieceInHandCount[PieceColor.black]! >= 0);

        if (pieceInHandCount[PieceColor.white] == 0 &&
            pieceInHandCount[PieceColor.black] == 0) {
          if (checkIfGameIsOver()) {
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

          if (checkIfGameIsOver()) {
            return true;
          }
        } else {
          changeSideToMove();
        }
        Game.instance.focusIndex = squareToIndex[s] ?? invalidIndex;
        Audios.playTone(Audios.placeSoundId);
      } else {
        pieceToRemoveCount = rule.mayRemoveMultiple ? n : 1;
        updateKeyMisc();
        action = Act.remove;
        Game.instance.focusIndex = squareToIndex[s] ?? invalidIndex;
        Audios.playTone(Audios.millSoundId);
      }
    } else if (phase == Phase.moving) {
      if (checkIfGameIsOver()) {
        return true;
      }

      // if illegal
      if (pieceOnBoardCount[sideToMove()]! > rule.flyPieceCount ||
          !rule.mayFly) {
        int md;

        for (md = 0; md < moveDirectionNumber; md++) {
          if (s == adjacentSquares[currentSquare][md]) break;
        }

        // not in moveTable
        if (md == moveDirectionNumber) {
          print(
              "[position] putPiece: [$s] is not in [$currentSquare]'s move table.");
          return false;
        }
      }

      record = "(" +
          fileOf(currentSquare).toString() +
          "," +
          rankOf(currentSquare).toString() +
          ")->(" +
          fileOf(s).toString() +
          "," +
          rankOf(s).toString() +
          ")";

      st.rule50++;

      board[s] = _grid[squareToIndex[s]!] = board[currentSquare];
      updateKey(s);
      revertKey(currentSquare);

      board[currentSquare] =
          _grid[squareToIndex[currentSquare]!] = Piece.noPiece;

      currentSquare = s;
      int n = millsCount(currentSquare);

      // midgame
      if (n == 0) {
        action = Act.select;
        changeSideToMove();

        if (checkIfGameIsOver()) {
          return true;
        } else {
          Game.instance.focusIndex = squareToIndex[s] ?? invalidIndex;
          Audios.playTone(Audios.placeSoundId);
        }
      } else {
        pieceToRemoveCount = rule.mayRemoveMultiple ? n : 1;
        updateKeyMisc();
        action = Act.remove;
        Game.instance.focusIndex = squareToIndex[s] ?? invalidIndex;
        Audios.playTone(Audios.millSoundId);
      }
    } else {
      assert(false);
    }

    return true;
  }

  int removePiece(int s) {
    if (phase == Phase.ready || phase == Phase.gameOver) return -1;

    if (action != Act.remove) return -1;

    if (pieceToRemoveCount <= 0) return -1;

    // if piece is not their
    if (!(PieceColor.opponent(sideToMove()) == board[s])) return -2;

    if (!rule.mayRemoveFromMillsAlways &&
        potentialMillsCount(s, PieceColor.nobody) > 0 &&
        !isAllInMills(PieceColor.opponent(sideToMove()))) {
      return -3;
    }

    revertKey(s);

    Audios.playTone(Audios.removeSoundId);

    if (rule.hasBannedLocations && phase == Phase.placing) {
      // Remove and put ban
      board[s] = _grid[squareToIndex[s]!] = Piece.ban;
      updateKey(s);
    } else {
      // Remove only
      board[s] = _grid[squareToIndex[s]!] = Piece.noPiece;
    }

    record = "-(" + fileOf(s).toString() + "," + rankOf(s).toString() + ")";
    st.rule50 = 0; // TODO: Need to move out?

    if (pieceOnBoardCount[them] != null) {
      pieceOnBoardCount[them] = pieceOnBoardCount[them]! - 1;
    }

    if (pieceOnBoardCount[them]! + pieceInHandCount[them]! <
        rule.piecesAtLeastCount) {
      setGameOver(sideToMove(), GameOverReason.loseReasonlessThanThree);
      return 0;
    }

    currentSquare = 0;

    pieceToRemoveCount--;
    updateKeyMisc();

    if (pieceToRemoveCount > 0) {
      return 0;
    }

    if (phase == Phase.placing) {
      if (pieceInHandCount[PieceColor.white] == 0 &&
          pieceInHandCount[PieceColor.black] == 0) {
        phase = Phase.moving;
        action = Act.select;

        if (rule.hasBannedLocations) {
          removeBanStones();
        }

        if (rule.isDefenderMoveFirst) {
          checkIfGameIsOver();
          return 0;
        }
      } else {
        action = Act.place;
      }
    } else {
      action = Act.select;
    }

    changeSideToMove();
    checkIfGameIsOver();

    return 0;
  }

  int selectPiece(int sq) {
    if (phase != Phase.moving) return -2;

    if (action != Act.select && action != Act.place) return -1;

    if (board[sq] == PieceColor.none) {
      return -3;
    }

    if (!(board[sq] == sideToMove())) {
      return -4;
    }

    currentSquare = sq;
    action = Act.place;
    Game.instance.blurIndex = squareToIndex[sq];

    return 0;
  }

  bool resign(String loser) {
    if (phase == Phase.ready ||
        phase == Phase.gameOver ||
        phase == Phase.none) {
      return false;
    }

    setGameOver(PieceColor.opponent(loser), GameOverReason.loseReasonResign);

    return true;
  }

  String getWinner() {
    return winner;
  }

  void setGameOver(String w, GameOverReason reason) {
    phase = Phase.gameOver;
    gameOverReason = reason;
    winner = w;

    print("[position] Game over, $w win, because of $reason");
    updateScore();
  }

  void updateScore() {
    if (phase == Phase.gameOver) {
      if (winner == PieceColor.draw) {
        if (score[PieceColor.draw] != null) {
          score[PieceColor.draw] = score[PieceColor.draw]! + 1;
        }

        return;
      }

      if (score[winner] != null) {
        score[winner] = score[winner]! + 1;
      }
    }
  }

  bool checkIfGameIsOver() {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return true;
    }

    if (rule.maxStepsLedToDraw > 0 &&
        posKeyHistory.length > rule.maxStepsLedToDraw) {
      setGameOver(PieceColor.draw, GameOverReason.drawReasonRule50);
      return true;
    }

    if (pieceOnBoardCount[PieceColor.white]! +
            pieceOnBoardCount[PieceColor.black]! >=
        rankNumber * fileNumber) {
      if (rule.isWhiteLoseButNotDrawWhenBoardFull) {
        setGameOver(PieceColor.black, GameOverReason.loseReasonBoardIsFull);
      } else {
        setGameOver(PieceColor.draw, GameOverReason.drawReasonBoardIsFull);
      }

      return true;
    }

    if (phase == Phase.moving && action == Act.select && isAllSurrounded()) {
      if (rule.isLoseButNotChangeSideWhenNoWay) {
        setGameOver(
            PieceColor.opponent(sideToMove()), GameOverReason.loseReasonNoWay);
        return true;
      } else {
        changeSideToMove(); // TODO: Need?
        return false;
      }
    }

    return false;
  }

  void removeBanStones() {
    assert(rule.hasBannedLocations);

    int s = 0;

    for (int f = 1; f <= fileNumber; f++) {
      for (int r = 0; r < rankNumber; r++) {
        s = f * rankNumber + r;

        if (board[s] == Piece.ban) {
          board[s] = _grid[squareToIndex[s]!] = Piece.noPiece;
          revertKey(s);
        }
      }
    }
  }

  void setSideToMove(String color) {
    _sideToMove = color;
    //us = color;
    them = PieceColor.opponent(_sideToMove);
  }

  void changeSideToMove() {
    setSideToMove(PieceColor.opponent(_sideToMove));
    st.key ^= Zobrist.side;
    print("[position] $_sideToMove to move.");

    /*
    if (phase == Phase.moving &&
        !rule.isLoseButNotChangeSideWhenNoWay &&
        isAllSurrounded() &&
        !rule.mayFly &&
        pieceOnBoardCount[sideToMove()]! >= rule.piecesAtLeastCount) {
      print("[position] $_sideToMove is no way to go.");
      changeSideToMove();
    }
    */
  }

  int updateKey(int s) {
    String pieceType = colorOn(s);

    st.key ^= Zobrist.psq[pieceColorIndex[pieceType]!][s];

    return st.key;
  }

  int revertKey(int s) {
    return updateKey(s);
  }

  int updateKeyMisc() {
    st.key = st.key << Zobrist.KEY_MISC_BIT >> Zobrist.KEY_MISC_BIT;

    st.key |= (pieceToRemoveCount) << (32 - Zobrist.KEY_MISC_BIT);

    return st.key;
  }

  ///////////////////////////////////////////////////////////////////////////////

  String colorOn(int sq) {
    return board[sq];
  }

  int potentialMillsCount(int to, String c, {int from = 0}) {
    int n = 0;
    String locbak = Piece.noPiece;

    assert(0 <= from && from < sqNumber);

    if (c == PieceColor.nobody) {
      c = colorOn(to);
    }

    if (from != 0 && from >= sqBegin && from < sqEnd) {
      locbak = board[from];
      board[from] = _grid[squareToIndex[from]!] = Piece.noPiece;
    }

    for (int l = 0; l < lineDirectionNumber; l++) {
      if (c == board[millTable[to][l][0]] && c == board[millTable[to][l][1]]) {
        n++;
      }
    }

    if (from != 0) {
      board[from] = _grid[squareToIndex[from]!] = locbak;
    }

    return n;
  }

  int millsCount(int s) {
    int n = 0;
    List<int?> idx = [0, 0, 0];
    int min = 0;
    int? temp = 0;
    String m = colorOn(s);

    for (int i = 0; i < idx.length; i++) {
      idx[0] = s;
      idx[1] = millTable[s][i][0];
      idx[2] = millTable[s][i][1];

      // no mill
      if (!(m == board[idx[1]!] && m == board[idx[2]!])) {
        continue;
      }

      // close mill

      // sort
      for (int j = 0; j < 2; j++) {
        min = j;

        for (int k = j + 1; k < 3; k++) {
          if (idx[min]! > idx[k]!) min = k;
        }

        if (min == j) {
          continue;
        }

        temp = idx[min];
        idx[min] = idx[j];
        idx[j] = temp;
      }

      n++;
    }

    return n;
  }

  bool isAllInMills(String c) {
    for (int i = sqBegin; i < sqEnd; i++) {
      if (board[i] == c) {
        if (potentialMillsCount(i, PieceColor.nobody) == 0) {
          return false;
        }
      }
    }

    return true;
  }

  bool isAllSurrounded() {
    // Full
    if (pieceOnBoardCount[PieceColor.white]! +
            pieceOnBoardCount[PieceColor.black]! >=
        rankNumber * fileNumber) {
      return true;
    }

    // Can fly
    if (pieceOnBoardCount[sideToMove()]! <= rule.flyPieceCount && rule.mayFly) {
      return false;
    }

    int? moveSquare;

    for (int s = sqBegin; s < sqEnd; s++) {
      if (!(sideToMove() == colorOn(s))) {
        continue;
      }

      for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
        moveSquare = adjacentSquares[s][d];
        if (moveSquare != 0 && board[moveSquare!] == Piece.noPiece) {
          return false;
        }
      }
    }

    return true;
  }

  bool isStarSquare(int s) {
    if (rule.hasDiagonalLines == true) {
      return (s == 17 || s == 19 || s == 21 || s == 23);
    }

    return (s == 16 || s == 18 || s == 20 || s == 22);
  }

  ///////////////////////////////////////////////////////////////////////////////

  int getNPiecesInHand() {
    pieceInHandCount[PieceColor.white] =
        rule.piecesCount - pieceOnBoardCount[PieceColor.white]!;
    pieceInHandCount[PieceColor.black] =
        rule.piecesCount - pieceOnBoardCount[PieceColor.black]!;

    return pieceOnBoardCount[PieceColor.white]! +
        pieceOnBoardCount[PieceColor.black]!;
  }

  void clearBoard() {
    for (int i = 0; i < _grid.length; i++) {
      _grid[i] = Piece.noPiece;
    }

    for (int i = 0; i < board.length; i++) {
      board[i] = Piece.noPiece;
    }
  }

  int setPosition(Rule newRule) {
    result = GameResult.pending;

    gamePly = 0;
    st.rule50 = 0;
    st.pliesFromNull = 0;

    gameOverReason = GameOverReason.noReason;
    phase = Phase.placing;
    setSideToMove(PieceColor.white);
    action = Act.place;
    currentSquare = 0;

    record = "";

    clearBoard();

    if (pieceOnBoardCountCount() == -1) {
      return -1;
    }

    getNPiecesInHand();
    pieceToRemoveCount = 0;

    winner = PieceColor.nobody;
    Mills.adjacentSquaresInit();
    Mills.millTableInit();
    currentSquare = 0;

    return -1;
  }

  int pieceOnBoardCountCount() {
    pieceOnBoardCount[PieceColor.white] =
        pieceOnBoardCount[PieceColor.black] = 0;

    for (int f = 1; f < fileExNumber; f++) {
      for (int r = 0; r < rankNumber; r++) {
        int s = f * rankNumber + r;
        if (board[s] == Piece.whiteStone) {
          if (pieceOnBoardCount[PieceColor.white] != null) {
            pieceOnBoardCount[PieceColor.white] =
                pieceOnBoardCount[PieceColor.white]! + 1;
          }
        } else if (board[s] == Piece.blackStone) {
          if (pieceOnBoardCount[PieceColor.black] != null) {
            pieceOnBoardCount[PieceColor.black] =
                pieceOnBoardCount[PieceColor.black]! + 1;
          }
        }
      }
    }

    if (pieceOnBoardCount[PieceColor.white]! > rule.piecesCount ||
        pieceOnBoardCount[PieceColor.black]! > rule.piecesCount) {
      return -1;
    }

    return pieceOnBoardCount[PieceColor.white]! +
        pieceOnBoardCount[PieceColor.black]!;
  }

///////////////////////////////////////////////////////////////////////////////

  Future<bool> _gotoHistory(int moveIndex) async {
    bool ret = false;

    if (recorder == null) {
      print("[goto] recorder is null.");
      return false;
    }

    var history = recorder!.getHistory();
    if (moveIndex < -1 || history.length <= moveIndex) {
      print("[goto] moveIndex is out of range.");
      return false;
    }

    if (recorder!.cur == moveIndex) {
      print("[goto] cur is equal to moveIndex.");
      return false;
    }

    // Backup context
    var engineTypeBackup = Game.instance.engineType;

    Game.instance.engineType = EngineType.humanVsHuman;
    Game.instance.setWhoIsAi(EngineType.humanVsHuman);

    var historyBack = history;

    await Game.instance.newGame();

    if (moveIndex == -1) {
      ret = true;
    }

    for (var i = 0; i <= moveIndex; i++) {
      Game.instance.doMove(history[i].move);
      ret = true;
      //await Future.delayed(Duration(seconds: 1));
      //setState(() {});
    }

    // Restore context
    Game.instance.engineType = engineTypeBackup;
    Game.instance.setWhoIsAi(engineTypeBackup);
    recorder!.setHistory(historyBack);
    recorder!.cur = moveIndex;

    return ret;
  }

  Future<bool> takeBackN(int n) async {
    int index = recorder!.cur - n;
    if (index < -1) {
      index = -1;
    }
    return _gotoHistory(index);
  }

  Future<bool> takeBack() async {
    return _gotoHistory(recorder!.cur - 1);
  }

  Future<bool> stepForward() async {
    return _gotoHistory(recorder!.cur + 1);
  }

  Future<bool> takeBackAll() async {
    return _gotoHistory(-1);
  }

  Future<bool> stepForwardAll() async {
    return _gotoHistory(recorder!.getHistory().length - 1);
  }

  String movesSinceLastRemove() {
    int? i = 0;
    String moves = "";
    int posAfterLastRemove = 0;

    //print("recorder.movesCount = ${recorder.movesCount}");

    for (i = recorder!.movesCount - 1; i! >= 0; i--) {
      //if (recorder.moveAt(i).type == MoveType.remove) break;
      if (recorder!.moveAt(i).move![0] == '-') break;
    }

    if (i >= 0) {
      posAfterLastRemove = i + 1;
    }

    //print("[movesSinceLastRemove] posAfterLastRemove = $posAfterLastRemove");

    for (int i = posAfterLastRemove; i < recorder!.movesCount; i++) {
      moves += " ${recorder!.moveAt(i).move}";
    }

    //print("moves = $moves");

    var idx = moves.indexOf('-(');
    if (idx != -1) {
      //print("moves[$idx] is -(");
      assert(false);
    }

    return moves.length > 0 ? moves.substring(1) : '';
  }

  get moveHistoryText => recorder!.buildMoveHistoryText();

  get side => _sideToMove;

  get lastMove => recorder!.last;

  get lastPositionWithRemove => recorder!.lastPositionWithRemove;
}
