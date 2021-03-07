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

import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/mill/recorder.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/services/audios.dart';

import 'types.dart';

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

  List<String> board = List.filled(sqNumber, "");
  List<String> _grid = List.filled(7 * 7, "");

  GameRecorder? recorder;

  Map<String, int> pieceInHandCount = {
    PieceColor.black: -1,
    PieceColor.white: -1
  };
  Map<String, int> pieceOnBoardCount = {
    PieceColor.black: 0,
    PieceColor.white: 0
  };
  int pieceToRemoveCount = 0;

  int gamePly = 0;
  String _sideToMove = PieceColor.black;

  int rule50 = 0;
  int pliesFromNull = 0;

  // TODO
  StateInfo? st;

  String us = PieceColor.black;
  String them = PieceColor.white;
  String winner = PieceColor.nobody;

  GameOverReason gameOverReason = GameOverReason.noReason;

  Phase phase = Phase.none;
  Act action = Act.none;

  Map<String, int> score = {
    PieceColor.black: 0,
    PieceColor.white: 0,
    PieceColor.draw: 0
  };

  int currentSquare = 0;
  int nPlayed = 0;

  String? cmdline;

  late var millTable;
  late var moveTable;

  // TODO: null-safety
  Move? move;

  Position.boardToGrid() {
    _grid = [];
    for (int sq = 0; sq < board.length; sq++) {
      _grid[squareToIndex[sq]!] = board[sq];
    }
  }

  Position.gridToBoard() {
    board = [];
    for (int i = 0; i < _grid.length; i++) {
      board[indexToSquare[i]!] = _grid[i];
    }
  }

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

    rule50 = other.rule50;
    pliesFromNull = other.pliesFromNull;

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

  void setSideToMove(String color) {
    _sideToMove = color;
    us = _sideToMove;
    them = PieceColor.opponent(us);
  }

  String movedPiece(int move) {
    return pieceOn(fromSq(move));
  }

  bool movePiece(int from, int to) {
    if (selectPiece(from)) {
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

    //const DEFAULT_RULE_NUMBER = 1;

    //setPosition(rules[DEFAULT_RULE_NUMBER]);
    setPosition(rule); // TODO

    // TODO

    recorder = GameRecorder(lastPositionWithRemove: fen());
  }

  Position() {
    //score[Color.black] = score[Color.white] = score[Color.draw] = nPlayed = 0;
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
    ss += _sideToMove == PieceColor.black ? "b" : "w";

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

    ss += pieceOnBoardCount[PieceColor.black].toString() +
        " " +
        pieceInHandCount[PieceColor.black].toString() +
        " " +
        pieceOnBoardCount[PieceColor.white].toString() +
        " " +
        pieceInHandCount[PieceColor.white].toString() +
        " " +
        pieceToRemoveCount.toString() +
        " ";

    int sideIsBlack = _sideToMove == PieceColor.black ? 1 : 0;

    ss +=
        rule50.toString() + " " + (1 + (gamePly - sideIsBlack) ~/ 2).toString();

    // step counter
    //ss += '${recorder?.halfMove ?? 0} ${recorder?.fullMove ?? 0}';

    //print("fen = " + ss);

    return ss;
  }

  /// Position::legal() tests whether a pseudo-legal move is legal

  bool legal(Move move) {
    if (!isOk(move.from) || !isOk(move.to)) return false;

    String us = _sideToMove;

    if (move.from == move.to) {
      print("Move $move.move from == to");
      return false; // TODO: Same with is_ok(m)
    }

    if (move.type == MoveType.remove) {
      if (movedPiece(move.to) != us) {
        print("Move $move.to to != us");
        return false;
      }
    }

    // TODO: Add more

    return true;
  }

  bool doMove(String move) {
    // TODO
    /*
    if (sscanf(cmd, "r%1u s%3d t%2u", &ruleIndex, &step, &t) == 3) {
      if (ruleIndex <= 0 || ruleIndex > N_RULES) {
        return false;
      }

      return set_position(&RULES[ruleIndex - 1]) >= 0 ? true : false;
    }
  */
    bool ret = false;

    //print("doMove $move");

    if (move.length > "Player".length &&
        move.substring(0, "Player".length - 1) == "Player") {
      if (move["Player".length] == '1') {
        return resign(PieceColor.black);
      } else {
        return resign(PieceColor.white);
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

      // TODO
      gameOverReason = GameOverReason.drawReasonThreefoldRepetition;
      return true;
    }

    Move m = Move(move);

    switch (m.type) {
      case MoveType.move:
        ret = movePiece(m.from, m.to);
        break;
      case MoveType.place:
        ret = putPiece(m.to);
        break;
      case MoveType.remove:
        rule50 = 0;
        ret = removePiece(m.to);
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
    ++rule50;
    ++pliesFromNull;

    this.move = m;

    recorder!.moveIn(m, this);

    return true;
  }

  bool posIsOk() {
    // TODO
    return true;
  }

///////////////////////////////////////////////////////////////////////////////

  int pieceOnBoardCountCount() {
    pieceOnBoardCount[PieceColor.black] =
        pieceOnBoardCount[PieceColor.white] = 0;

    for (int f = 1; f < fileExNumber; f++) {
      for (int r = 0; r < rankNumber; r++) {
        int s = f * rankNumber + r;
        if (board[s] == Piece.blackStone) {
          if (pieceOnBoardCount[PieceColor.black] != null) {
            pieceOnBoardCount[PieceColor.black] =
                pieceOnBoardCount[PieceColor.black]! + 1;
          }
        } else if (board[s] == Piece.whiteStone) {
          if (pieceOnBoardCount[PieceColor.white] != null) {
            pieceOnBoardCount[PieceColor.white] =
                pieceOnBoardCount[PieceColor.white]! + 1;
          }
        }
      }
    }

    if (pieceOnBoardCount[PieceColor.black]! > rule.piecesCount ||
        pieceOnBoardCount[PieceColor.white]! > rule.piecesCount) {
      return -1;
    }

    return pieceOnBoardCount[PieceColor.black]! +
        pieceOnBoardCount[PieceColor.white]!;
  }

  int getNPiecesInHand() {
    pieceInHandCount[PieceColor.black] =
        rule.piecesCount - pieceOnBoardCount[PieceColor.black]!;
    pieceInHandCount[PieceColor.white] =
        rule.piecesCount - pieceOnBoardCount[PieceColor.white]!;

    return pieceOnBoardCount[PieceColor.black]! +
        pieceOnBoardCount[PieceColor.white]!;
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
    rule50 = 0;
    pliesFromNull = 0;

    gameOverReason = GameOverReason.noReason;
    phase = Phase.placing;
    setSideToMove(PieceColor.black);
    action = Act.place;
    currentSquare = 0;

    cmdline = "";

    clearBoard();

    if (pieceOnBoardCountCount() == -1) {
      return -1;
    }

    getNPiecesInHand();
    pieceToRemoveCount = 0;

    winner = PieceColor.nobody;
    createMoveTable();
    createMillTable();
    currentSquare = 0;

    return -1;
  }

  bool reset() {
    gamePly = 0;
    rule50 = 0;

    phase = Phase.ready;
    setSideToMove(PieceColor.black);
    action = Act.place;

    winner = PieceColor.nobody;
    gameOverReason = GameOverReason.noReason;

    clearBoard();

    pieceOnBoardCount[PieceColor.black] =
        pieceOnBoardCount[PieceColor.white] = 0;
    pieceInHandCount[PieceColor.black] =
        pieceInHandCount[PieceColor.white] = rule.piecesCount;
    pieceToRemoveCount = 0;

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

  bool putPiece(int s) {
    var index = squareToIndex[s];
    var piece = _sideToMove;
    var us = _sideToMove;

    if (phase == Phase.gameOver ||
        action != Act.place ||
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

      _grid[index!] = piece;
      board[s] = piece;

      cmdline = "(" + fileOf(s).toString() + "," + rankOf(s).toString() + ")";

      currentSquare = s;

      int n = millsCount(currentSquare);

      if (n == 0) {
        assert(pieceInHandCount[PieceColor.black]! >= 0 &&
            pieceInHandCount[PieceColor.white]! >= 0);

        if (pieceInHandCount[PieceColor.black] == 0 &&
            pieceInHandCount[PieceColor.white] == 0) {
          if (checkIfGameIsOver()) {
            //Audios.playTone('mill.mp3');
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
            //Audios.playTone('mill.mp3');
            return true;
          }
        } else {
          changeSideToMove();
        }
        Game.shared.focusIndex = squareToIndex[s] ?? Move.invalidMove;
        Audios.playTone('place.mp3');
      } else {
        pieceToRemoveCount = rule.mayRemoveMultiple ? n : 1;
        action = Act.remove;
        Game.shared.focusIndex = squareToIndex[s] ?? Move.invalidMove;
        Audios.playTone('mill.mp3');
      }
    } else if (phase == Phase.moving) {
      if (checkIfGameIsOver()) {
        //Audios.playTone('mill.mp3');
        return true;
      }

      // if illegal
      if (pieceOnBoardCount[sideToMove()]! > rule.piecesAtLeastCount ||
          !rule.mayFly) {
        int md;

        for (md = 0; md < moveDirectionNumber; md++) {
          if (s == moveTable[currentSquare][md]) break;
        }

        // not in moveTable
        if (md == moveDirectionNumber) {
          print("putPiece: [$s] is not in [$currentSquare]'s move table.");
          return false;
        }
      }

      cmdline = "(" +
          fileOf(currentSquare).toString() +
          "," +
          rankOf(currentSquare).toString() +
          ")->(" +
          fileOf(s).toString() +
          "," +
          rankOf(s).toString() +
          ")";

      rule50++;

      board[s] = _grid[squareToIndex[s]!] = board[currentSquare];
      board[currentSquare] =
          _grid[squareToIndex[currentSquare]!] = Piece.noPiece;

      currentSquare = s;
      int n = millsCount(currentSquare);

      // midgame
      if (n == 0) {
        action = Act.select;
        changeSideToMove();

        if (checkIfGameIsOver()) {
          //Audios.playTone('mill.mp3');
          return true;
        } else {
          Game.shared.focusIndex = squareToIndex[s] ?? Move.invalidMove;
          Audios.playTone('place.mp3');
        }
      } else {
        pieceToRemoveCount = rule.mayRemoveMultiple ? n : 1;
        action = Act.remove;
        Game.shared.focusIndex = squareToIndex[s] ?? Move.invalidMove;
        Audios.playTone('mill.mp3');
      }
    } else {
      assert(false);
    }

    return true;
  }

  bool removePiece(int s) {
    if (phase == Phase.ready || phase == Phase.gameOver) return false;

    if (action != Act.remove) return false;

    if (pieceToRemoveCount <= 0) return false;

    // if piece is not their
    if (!(PieceColor.opponent(sideToMove()) == board[s])) return false;

    if (!rule.mayRemoveFromMillsAlways &&
        potentialMillsCount(s, PieceColor.nobody) > 0 &&
        !isAllInMills(PieceColor.opponent(sideToMove()))) {
      return false;
    }

    Audios.playTone('remove.mp3');

    if (rule.hasBannedLocations && phase == Phase.placing) {
      board[s] = _grid[squareToIndex[s]!] = Piece.ban;
    } else {
      // Remove
      board[s] = _grid[squareToIndex[s]!] = Piece.noPiece;
    }

    cmdline = "-(" + fileOf(s).toString() + "," + rankOf(s).toString() + ")";
    rule50 = 0; // TODO: Need to move out?

    if (pieceOnBoardCount[them] != null) {
      pieceOnBoardCount[them] = pieceOnBoardCount[them]! - 1;
    }

    if (pieceOnBoardCount[them]! + pieceInHandCount[them]! <
        rule.piecesAtLeastCount) {
      setGameOver(sideToMove(), GameOverReason.loseReasonlessThanThree);
      return true;
    }

    currentSquare = 0;

    pieceToRemoveCount--;

    if (pieceToRemoveCount > 0) {
      return true;
    }

    if (phase == Phase.placing) {
      if (pieceInHandCount[PieceColor.black] == 0 &&
          pieceInHandCount[PieceColor.white] == 0) {
        phase = Phase.moving;
        action = Act.select;

        if (rule.hasBannedLocations) {
          removeBanStones();
        }

        if (rule.isDefenderMoveFirst) {
          checkIfGameIsOver();
          return true;
        }
      } else {
        action = Act.place;
      }
    } else {
      action = Act.select;
    }

    changeSideToMove();
    checkIfGameIsOver();

    return true;
  }

  bool selectPiece(int sq) {
    if (phase != Phase.moving) return false;

    if (action != Act.select && action != Act.place) return false;

    if (board[sq] == sideToMove()) {
      currentSquare = sq;
      action = Act.place;
      //Audios.playTone('select.mp3');
      Game.shared.blurIndex = squareToIndex[sq];

      return true;
    }

    return false;
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
    print("Game over, $w win, because of $reason");
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
    //print("Is game over?");

    if (phase == Phase.ready || phase == Phase.gameOver) {
      return true;
    }

    if (rule.maxStepsLedToDraw > 0 && rule50 > rule.maxStepsLedToDraw) {
      winner = PieceColor.draw;
      phase = Phase.gameOver;
      gameOverReason = GameOverReason.drawReasonRule50;
      print("Game over, draw, because of $gameOverReason.");
      return true;
    }

    if (pieceOnBoardCount[PieceColor.black]! +
            pieceOnBoardCount[PieceColor.white]! >=
        rankNumber * fileNumber) {
      if (rule.isBlackLoseButNotDrawWhenBoardFull) {
        setGameOver(PieceColor.white, GameOverReason.loseReasonBoardIsFull);
      } else {
        setGameOver(PieceColor.draw, GameOverReason.drawReasonBoardIsFull);
      }

      return true;
    }

    bool isNoWay = isAllSurrounded();
    //print("phase = $phase, action = $action, isAllSurrounded = $isNoWay");
    if (phase == Phase.moving && action == Act.select && isNoWay) {
      if (rule.isLoseButNotChangeSideWhenNoWay) {
        setGameOver(
            PieceColor.opponent(sideToMove()), GameOverReason.loseReasonNoWay);
        return true;
      } else {
        changeSideToMove(); // TODO: Need?
        //print("Game is not over");
        return false;
      }
    }

    //print("Game is NOT over");
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
        }
      }
    }
  }

  void createMillTable() {
    const millTable_noObliqueLine = [
      /* 0 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 1 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 2 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 3 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 4 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 5 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 6 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 7 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],

      /* 8 */ [
        [16, 24],
        [9, 15],
        [0, 0]
      ],
      /* 9 */ [
        [0, 0],
        [15, 8],
        [10, 11]
      ],
      /* 10 */ [
        [18, 26],
        [11, 9],
        [0, 0]
      ],
      /* 11 */ [
        [0, 0],
        [9, 10],
        [12, 13]
      ],
      /* 12 */ [
        [20, 28],
        [13, 11],
        [0, 0]
      ],
      /* 13 */ [
        [0, 0],
        [11, 12],
        [14, 15]
      ],
      /* 14 */ [
        [22, 30],
        [15, 13],
        [0, 0]
      ],
      /* 15 */ [
        [0, 0],
        [13, 14],
        [8, 9]
      ],

      /* 16 */ [
        [8, 24],
        [17, 23],
        [0, 0]
      ],
      /* 17 */ [
        [0, 0],
        [23, 16],
        [18, 19]
      ],
      /* 18 */ [
        [10, 26],
        [19, 17],
        [0, 0]
      ],
      /* 19 */ [
        [0, 0],
        [17, 18],
        [20, 21]
      ],
      /* 20 */ [
        [12, 28],
        [21, 19],
        [0, 0]
      ],
      /* 21 */ [
        [0, 0],
        [19, 20],
        [22, 23]
      ],
      /* 22 */ [
        [14, 30],
        [23, 21],
        [0, 0]
      ],
      /* 23 */ [
        [0, 0],
        [21, 22],
        [16, 17]
      ],

      /* 24 */ [
        [8, 16],
        [25, 31],
        [0, 0]
      ],
      /* 25 */ [
        [0, 0],
        [31, 24],
        [26, 27]
      ],
      /* 26 */ [
        [10, 18],
        [27, 25],
        [0, 0]
      ],
      /* 27 */ [
        [0, 0],
        [25, 26],
        [28, 29]
      ],
      /* 28 */ [
        [12, 20],
        [29, 27],
        [0, 0]
      ],
      /* 29 */ [
        [0, 0],
        [27, 28],
        [30, 31]
      ],
      /* 30 */ [
        [14, 22],
        [31, 29],
        [0, 0]
      ],
      /* 31 */ [
        [0, 0],
        [29, 30],
        [24, 25]
      ],

      /* 32 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 33 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 34 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 35 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 36 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 37 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 38 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 39 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ]
    ];

    const millTable_hasObliqueLines = [
      /*  0 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  1 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  2 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  3 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  4 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  5 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  6 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /*  7 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],

      /*  8 */ [
        [16, 24],
        [9, 15],
        [0, 0]
      ],
      /*  9 */ [
        [17, 25],
        [15, 8],
        [10, 11]
      ],
      /* 10 */ [
        [18, 26],
        [11, 9],
        [0, 0]
      ],
      /* 11 */ [
        [19, 27],
        [9, 10],
        [12, 13]
      ],
      /* 12 */ [
        [20, 28],
        [13, 11],
        [0, 0]
      ],
      /* 13 */ [
        [21, 29],
        [11, 12],
        [14, 15]
      ],
      /* 14 */ [
        [22, 30],
        [15, 13],
        [0, 0]
      ],
      /* 15 */ [
        [23, 31],
        [13, 14],
        [8, 9]
      ],

      /* 16 */ [
        [8, 24],
        [17, 23],
        [0, 0]
      ],
      /* 17 */ [
        [9, 25],
        [23, 16],
        [18, 19]
      ],
      /* 18 */ [
        [10, 26],
        [19, 17],
        [0, 0]
      ],
      /* 19 */ [
        [11, 27],
        [17, 18],
        [20, 21]
      ],
      /* 20 */ [
        [12, 28],
        [21, 19],
        [0, 0]
      ],
      /* 21 */ [
        [13, 29],
        [19, 20],
        [22, 23]
      ],
      /* 22 */ [
        [14, 30],
        [23, 21],
        [0, 0]
      ],
      /* 23 */ [
        [15, 31],
        [21, 22],
        [16, 17]
      ],

      /* 24 */ [
        [8, 16],
        [25, 31],
        [0, 0]
      ],
      /* 25 */ [
        [9, 17],
        [31, 24],
        [26, 27]
      ],
      /* 26 */ [
        [10, 18],
        [27, 25],
        [0, 0]
      ],
      /* 27 */ [
        [11, 19],
        [25, 26],
        [28, 29]
      ],
      /* 28 */ [
        [12, 20],
        [29, 27],
        [0, 0]
      ],
      /* 29 */ [
        [13, 21],
        [27, 28],
        [30, 31]
      ],
      /* 30 */ [
        [14, 22],
        [31, 29],
        [0, 0]
      ],
      /* 31 */ [
        [15, 23],
        [29, 30],
        [24, 25]
      ],

      /* 32 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 33 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 34 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 35 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 36 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 37 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 38 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ],
      /* 39 */ [
        [0, 0],
        [0, 0],
        [0, 0]
      ]
    ];

    if (rule.hasObliqueLines) {
      millTable = millTable_hasObliqueLines;
    } else {
      millTable = millTable_noObliqueLine;
    }
  }

  void createMoveTable() {
    // Note: Not follow order of MoveDirection array
    const moveTable_obliqueLine = [
      /*  0 */ [0, 0, 0, 0],
      /*  1 */ [0, 0, 0, 0],
      /*  2 */ [0, 0, 0, 0],
      /*  3 */ [0, 0, 0, 0],
      /*  4 */ [0, 0, 0, 0],
      /*  5 */ [0, 0, 0, 0],
      /*  6 */ [0, 0, 0, 0],
      /*  7 */ [0, 0, 0, 0],

      /*  8 */ [9, 15, 16, 0],
      /*  9 */ [17, 8, 10, 0],
      /* 10 */ [9, 11, 18, 0],
      /* 11 */ [19, 10, 12, 0],
      /* 12 */ [11, 13, 20, 0],
      /* 13 */ [21, 12, 14, 0],
      /* 14 */ [13, 15, 22, 0],
      /* 15 */ [23, 8, 14, 0],

      /* 16 */ [17, 23, 8, 24],
      /* 17 */ [9, 25, 16, 18],
      /* 18 */ [17, 19, 10, 26],
      /* 19 */ [11, 27, 18, 20],
      /* 20 */ [19, 21, 12, 28],
      /* 21 */ [13, 29, 20, 22],
      /* 22 */ [21, 23, 14, 30],
      /* 23 */ [15, 31, 16, 22],

      /* 24 */ [25, 31, 16, 0],
      /* 25 */ [17, 24, 26, 0],
      /* 26 */ [25, 27, 18, 0],
      /* 27 */ [19, 26, 28, 0],
      /* 28 */ [27, 29, 20, 0],
      /* 29 */ [21, 28, 30, 0],
      /* 30 */ [29, 31, 22, 0],
      /* 31 */ [23, 24, 30, 0],

      /* 32 */ [0, 0, 0, 0],
      /* 33 */ [0, 0, 0, 0],
      /* 34 */ [0, 0, 0, 0],
      /* 35 */ [0, 0, 0, 0],
      /* 36 */ [0, 0, 0, 0],
      /* 37 */ [0, 0, 0, 0],
      /* 38 */ [0, 0, 0, 0],
      /* 39 */ [0, 0, 0, 0],
    ];

    const moveTable_noObliqueLine = [
      /*  0 */ [0, 0, 0, 0],
      /*  1 */ [0, 0, 0, 0],
      /*  2 */ [0, 0, 0, 0],
      /*  3 */ [0, 0, 0, 0],
      /*  4 */ [0, 0, 0, 0],
      /*  5 */ [0, 0, 0, 0],
      /*  6 */ [0, 0, 0, 0],
      /*  7 */ [0, 0, 0, 0],

      /*  8 */ [16, 9, 15, 0],
      /*  9 */ [10, 8, 0, 0],
      /* 10 */ [18, 11, 9, 0],
      /* 11 */ [12, 10, 0, 0],
      /* 12 */ [20, 13, 11, 0],
      /* 13 */ [14, 12, 0, 0],
      /* 14 */ [22, 15, 13, 0],
      /* 15 */ [8, 14, 0, 0],

      /* 16 */ [8, 24, 17, 23],
      /* 17 */ [18, 16, 0, 0],
      /* 18 */ [10, 26, 19, 17],
      /* 19 */ [20, 18, 0, 0],
      /* 20 */ [12, 28, 21, 19],
      /* 21 */ [22, 20, 0, 0],
      /* 22 */ [14, 30, 23, 21],
      /* 23 */ [16, 22, 0, 0],

      /* 24 */ [16, 25, 31, 0],
      /* 25 */ [26, 24, 0, 0],
      /* 26 */ [18, 27, 25, 0],
      /* 27 */ [28, 26, 0, 0],
      /* 28 */ [20, 29, 27, 0],
      /* 29 */ [30, 28, 0, 0],
      /* 30 */ [22, 31, 29, 0],
      /* 31 */ [24, 30, 0, 0],

      /* 32 */ [0, 0, 0, 0],
      /* 33 */ [0, 0, 0, 0],
      /* 34 */ [0, 0, 0, 0],
      /* 35 */ [0, 0, 0, 0],
      /* 36 */ [0, 0, 0, 0],
      /* 37 */ [0, 0, 0, 0],
      /* 38 */ [0, 0, 0, 0],
      /* 39 */ [0, 0, 0, 0],
    ];

    if (rule.hasObliqueLines) {
      moveTable = moveTable_obliqueLine;
    } else {
      moveTable = moveTable_noObliqueLine;
    }
  }

  String colorOn(int sq) {
    return board[sq];
  }

  int potentialMillsCount(int to, String c, {int from = 0}) {
    int n = 0;
    String ptBak = Piece.noPiece;

    assert(0 <= from && from < sqNumber);

    if (c == PieceColor.nobody) {
      c = colorOn(to);
    }

    if (from != 0) {
      ptBak = board[from];
      board[from] = _grid[squareToIndex[from]!] = Piece.noPiece;
    }

    for (int l = 0; l < lineDirectionNumber; l++) {
      if (c == board[millTable[to][l][0]] && c == board[millTable[to][l][1]]) {
        n++;
      }
    }

    if (from != 0) {
      board[from] = _grid[squareToIndex[from]!] = ptBak;
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
    if (pieceOnBoardCount[PieceColor.black]! +
            pieceOnBoardCount[PieceColor.white]! >=
        rankNumber * fileNumber) {
      //print("Board is full.");
      return true;
    }

    // Can fly
    if (pieceOnBoardCount[sideToMove()]! <= rule.piecesAtLeastCount &&
        rule.mayFly) {
      //print("Can fly.");
      return false;
    }

    int? moveSquare;

    for (int s = sqBegin; s < sqEnd; s++) {
      if (!(sideToMove() == colorOn(s))) {
        continue;
      }

      for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
        moveSquare = moveTable[s][d];
        if (moveSquare != 0 && board[moveSquare!] == Piece.noPiece) {
          return false;
        }
      }
    }

    //print("No way.");
    return true;
  }

  bool isStarSquare(int s) {
    if (rule.hasObliqueLines == true) {
      return (s == 17 || s == 19 || s == 21 || s == 23);
    }

    return (s == 16 || s == 18 || s == 20 || s == 22);
  }

///////////////////////////////////////////////////////////////////////////////

  bool regret() {
    // TODO
    final lastMove = recorder!.removeLast();
    if (lastMove == null) return false;

    _grid[lastMove.from] = _grid[lastMove.to];
    _grid[lastMove.to] = lastMove.removed;
    board[lastMove.from] = board[lastMove.to];
    board[lastMove.to] = lastMove.removed;

    changeSideToMove();

    final counterMarks = GameRecorder.fromCounterMarks(lastMove.counterMarks);
    recorder!.halfMove = counterMarks.halfMove;
    recorder!.fullMove = counterMarks.fullMove;

    if (lastMove.removed != Piece.noPiece) {
      //
      // Find last remove position (or opening), NativeEngine need
      final tempPosition = Position.clone(this);

      final moves = recorder!.reverseMovesToPrevRemove();
      moves.forEach((move) {
        //
        tempPosition._grid[move.from] = tempPosition._grid[move.to];
        tempPosition._grid[move.to] = move.removed;

        tempPosition._sideToMove =
            PieceColor.opponent(tempPosition._sideToMove);
      });

      recorder!.lastPositionWithRemove = tempPosition.fen();
    }

    result = GameResult.pending;

    return true;
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

  get manualText => recorder!.buildManualText();

  get side => _sideToMove;

  void changeSideToMove() {
    them = _sideToMove;
    _sideToMove = PieceColor.opponent(_sideToMove);
    print("$_sideToMove to move.");
  }

  get halfMove => recorder!.halfMove;

  get fullMove => recorder!.fullMove;

  get lastMove => recorder!.last;

  get lastPositionWithRemove => recorder!.lastPositionWithRemove;
}
