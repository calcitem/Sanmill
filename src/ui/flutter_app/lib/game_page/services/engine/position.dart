// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../mill.dart';

List<int> posKeyHistory = <int>[];

class SquareAttribute {
  SquareAttribute({
    required this.placedPieceNumber,
  });

  int placedPieceNumber;
}

class StateInfo {
  // Copied when making a move
  int rule50 = 0;
  int pliesFromNull = 0;

  // Not copied when making a move (will be recomputed anyhow)
  int key = 0;
}

class Position {
  Position();

  GameResult? result;

  final List<PieceColor> _board =
      List<PieceColor>.filled(sqNumber, PieceColor.none);
  final List<PieceColor> _grid =
      List<PieceColor>.filled(7 * 7, PieceColor.none);

  int placedPieceNumber = 0;
  int selectedPieceNumber = 0;
  late List<SquareAttribute> sqAttrList = List<SquareAttribute>.generate(
    sqNumber,
    (int index) => SquareAttribute(placedPieceNumber: 0),
  );

  final Map<PieceColor, int> pieceInHandCount = <PieceColor, int>{
    PieceColor.white: DB().ruleSettings.piecesCount,
    PieceColor.black: DB().ruleSettings.piecesCount,
  };
  final Map<PieceColor, int> pieceOnBoardCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };
  final Map<PieceColor, int> pieceToRemoveCount = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  int pieceCountDiff() {
    return pieceOnBoardCount[PieceColor.white]! +
        pieceInHandCount[PieceColor.white]! -
        pieceOnBoardCount[PieceColor.black]! -
        pieceInHandCount[PieceColor.black]!;
  }

  bool isNeedStalemateRemoval = false;
  bool isStalemateRemoving = false;

  int _gamePly = 0;
  PieceColor _sideToMove = PieceColor.white;

  final StateInfo st = StateInfo();

  PieceColor _them = PieceColor.black;
  PieceColor winner = PieceColor.nobody;

  GameOverReason? gameOverReason;

  Phase phase = Phase.placing;
  Act action = Act.place;

  static Map<PieceColor, int> score = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  String get scoreString =>
      "${score[PieceColor.white]} - ${score[PieceColor.draw]} - ${score[PieceColor.black]}";

  static void resetScore() => score[PieceColor.white] =
      score[PieceColor.black] = score[PieceColor.draw] = 0;

  Map<PieceColor, int> _currentSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  ExtMove? _record;

  static List<List<List<int>>> get _millTable => _Mills.millTableInit;
  static List<List<int>> get _adjacentSquares => _Mills.adjacentSquaresInit;

  static List<List<int>> get _millLinesHV => _Mills._horizontalAndVerticalLines;
  static List<List<int>> get _millLinesD => _Mills._diagonalLines;

  PieceColor pieceOnGrid(int index) => _grid[index];

  PieceColor get sideToMove => _sideToMove;
  set sideToMove(PieceColor color) {
    _sideToMove = color;
    _them = _sideToMove.opponent;
  }

  bool _movePiece(int from, int to) {
    try {
      _selectPiece(from);
      return _putPiece(to);
    } on GameResponse {
      return false;
    }
  }

  /// Returns a FEN representation of the position.
  /// Example: "@*O@O*O*/O*@@O@@@/O@O*@*O* b m s 8 0 9 0 0 3 10"
  /// Format: "[Inner ring]/[Middle Ring]/[Outer Ring]
  /// [Side to Move] [Phase] [Action]
  /// [White Piece On Board] [White Piece In Hand]
  /// [Black Piece On Board] [Black Piece In Hand]
  /// [Piece to Remove ]
  /// [Rule50] [Ply]"
  ///
  /// ([Rule50] and [Ply] are unused right now.)
  /// Param:
  ///
  /// Ring
  /// @ - Black piece
  /// O - White piece
  /// * - Empty point
  /// X - Marked point
  ///
  /// Side to move
  /// w - White to Move
  /// b - Black to Move
  ///
  /// Phase
  /// p - Placing Phase
  /// m - Moving Phase
  ///
  /// Action
  /// p - Place Action
  /// s - Select Action
  /// r - Remove Action
  String? get fen {
    final StringBuffer buffer = StringBuffer();

    // Piece placement data
    for (int file = 1; file <= fileNumber; file++) {
      for (int rank = 1; rank <= rankNumber; rank++) {
        final PieceColor piece =
            pieceOnGrid(squareToIndex[makeSquare(file, rank)]!);
        buffer.write(piece.string);
      }

      if (file == 3) {
        buffer.writeSpace();
      } else {
        buffer.write("/");
      }
    }

    // Active color
    buffer.writeSpace(_sideToMove == PieceColor.white ? "w" : "b");

    // Phrase
    if (pieceInHandCount[_sideToMove] == 0 && phase == Phase.placing) {
      logger.e("Invalid FEN: No piece to place in placing phase.");
    }
    buffer.writeSpace(phase.fen);

    // Action
    if (action == Act.remove) {
      if (pieceToRemoveCount[_sideToMove] == 0) {
        logger.e("Invalid FEN: No piece to remove.");
      }
      if (pieceOnBoardCount[_sideToMove.opponent] == 0 &&
          DB().ruleSettings.millFormationActionInPlacingPhase !=
              MillFormationActionInPlacingPhase.opponentRemovesOwnPiece) {
        logger.e("Invalid FEN: No piece to remove.");
      }
    }
    buffer.writeSpace(action.fen);

    buffer.writeSpace(pieceOnBoardCount[PieceColor.white]);
    buffer.writeSpace(pieceInHandCount[PieceColor.white]);
    buffer.writeSpace(pieceOnBoardCount[PieceColor.black]);
    buffer.writeSpace(pieceInHandCount[PieceColor.black]);
    buffer.writeSpace(pieceToRemoveCount[PieceColor.white]);
    buffer.writeSpace(pieceToRemoveCount[PieceColor.black]);

    final int sideIsBlack = _sideToMove == PieceColor.black ? 1 : 0;

    buffer.write("${st.rule50} ${1 + (_gamePly - sideIsBlack) ~/ 2}");

    logger.t("FEN is $buffer");

    final String fen = buffer.toString();

    if (validateFen(fen) == false) {
      logger.e("Invalid FEN: $fen");
    }

    return fen;
  }

  bool setFen(String fen) {
    const bool ret = true;
    final List<String> l = fen.split(" ");

    final String boardStr = l[0];
    final List<String> ring = boardStr.split("/");

    final Map<String, PieceColor> pieceMap = <String, PieceColor>{
      "*": PieceColor.none,
      "O": PieceColor.white,
      "@": PieceColor.black,
      "X": PieceColor.marked,
    };

    // Piece placement data
    for (int file = 1; file <= fileNumber; file++) {
      for (int rank = 1; rank <= rankNumber; rank++) {
        final PieceColor p = pieceMap[ring[file - 1][rank - 1]]!;
        final int sq = makeSquare(file, rank);
        _board[sq] = p;
        _grid[squareToIndex[sq]!] = p;
      }
    }

    final String sideToMoveStr = l[1];

    final Map<String, PieceColor> sideToMoveMap = <String, PieceColor>{
      "w": PieceColor.white,
      "b": PieceColor.black,
    };

    _sideToMove = sideToMoveMap[sideToMoveStr]!;
    _them = _sideToMove.opponent;

    final String phaseStr = l[2];

    final Map<String, Phase> phaseMap = <String, Phase>{
      "r": Phase.ready,
      "p": Phase.placing,
      "m": Phase.moving,
      "o": Phase.gameOver,
    };

    phase = phaseMap[phaseStr]!;

    final String actionStr = l[3];

    final Map<String, Act> actionMap = <String, Act>{
      "p": Act.place,
      "s": Act.select,
      "r": Act.remove,
    };

    action = actionMap[actionStr]!;

    final String whitePieceOnBoardCountStr = l[4];
    pieceOnBoardCount[PieceColor.white] = int.parse(whitePieceOnBoardCountStr);

    final String whitePieceInHandCountStr = l[5];
    pieceInHandCount[PieceColor.white] = int.parse(whitePieceInHandCountStr);

    final String blackPieceOnBoardCountStr = l[6];
    pieceOnBoardCount[PieceColor.black] = int.parse(blackPieceOnBoardCountStr);

    final String blackPieceInHandCountStr = l[7];
    pieceInHandCount[PieceColor.black] = int.parse(blackPieceInHandCountStr);

    final String whitePieceToRemoveCountStr = l[8];
    pieceToRemoveCount[PieceColor.white] =
        int.parse(whitePieceToRemoveCountStr);

    final String blackPieceToRemoveCountStr = l[9];
    pieceToRemoveCount[PieceColor.black] =
        int.parse(blackPieceToRemoveCountStr);

    final String rule50Str = l[10];
    st.rule50 = int.parse(rule50Str);

    final String gamePlyStr = l[11];
    _gamePly = int.parse(gamePlyStr);

    // Misc
    winner = PieceColor.nobody;
    gameOverReason = null;
    _currentSquare[PieceColor.white] = _currentSquare[PieceColor.black] = 0;
    _record = null;

    return ret;
  }

  // TODO: Implement with C++ in engine
  bool validateFen(String fen) {
    final List<String> parts = fen.split(' ');
    if (parts.length < 12) {
      logger.e('FEN does not contain enough parts.');
      return false;
    }

    // Part 0: Piece placement
    final String board = parts[0];
    if (board.length != 26 ||
        board[8] != '/' ||
        board[17] != '/' ||
        !RegExp(r'^[*OX@/]+$').hasMatch(board)) {
      logger.e('Invalid piece placement format.');
      return false;
    }

    // Part 1: Active color
    final String activeColor = parts[1];
    if (activeColor != 'w' && activeColor != 'b') {
      logger.e('Invalid active color. Must be "w" or "b".');
      return false;
    }

    // Part 2: Phrase
    final String phrase = parts[2];
    if (!RegExp(r'^[rpmo]$').hasMatch(phrase)) {
      logger.e('Invalid phrase. Must be one of "r", "p", "m", "o".');
      return false;
    }

    // Part 3: Action
    final String action = parts[3];
    if (!RegExp(r'^[psr]$').hasMatch(action)) {
      logger.e('Invalid action. Must be one of "p", "s", "r".');
      return false;
    }

    // Part 4: White piece on board
    final int whitePieceOnBoard = int.parse(parts[4]);
    if (phrase == 'm' &&
        whitePieceOnBoard < DB().ruleSettings.piecesAtLeastCount) {
      logger.e(
          'Invalid white piece on board. Must be at least ${DB().ruleSettings.piecesAtLeastCount}.');
      return false;
    }
    if (whitePieceOnBoard < 0 ||
        whitePieceOnBoard > DB().ruleSettings.piecesCount) {
      logger.e('Invalid white piece on board. Must be between 0 and 12.');
      return false;
    }

    // Part 5: White piece in hand
    final int whitePieceInHand = int.parse(parts[5]);
    if (whitePieceInHand < 0 ||
        whitePieceInHand > DB().ruleSettings.piecesCount) {
      logger.e('Invalid white piece in hand. Must be between 0 and 12.');
      return false;
    }
    if (activeColor == 'w' && phrase == 'p' && whitePieceInHand == 0) {
      logger.e('Invalid white piece in hand. Must be greater than 0.');
      return false;
    }

    // Part 6: Black piece on board
    final int blackPieceOnBoard = int.parse(parts[6]);
    if (phrase == 'm' &&
        blackPieceOnBoard < DB().ruleSettings.piecesAtLeastCount) {
      logger.e(
          'Invalid black piece on board. Must be at least ${DB().ruleSettings.piecesAtLeastCount}.');
      return false;
    }
    if (blackPieceOnBoard < 0 ||
        blackPieceOnBoard > DB().ruleSettings.piecesCount) {
      logger.e('Invalid black piece on board. Must be between 0 and 12.');
      return false;
    }

    // Part 7: Black piece in hand
    final int blackPieceInHand = int.parse(parts[7]);
    if (blackPieceInHand < 0 ||
        blackPieceInHand > DB().ruleSettings.piecesCount) {
      logger.e('Invalid black piece in hand. Must be between 0 and 12.');
      return false;
    }
    if (activeColor == 'b' && phrase == 'p' && blackPieceInHand == 0) {
      logger.e('Invalid black piece in hand. Must be greater than 0.');
      return false;
    }

    // Parts 4-7: Counts on and off board
    List<int> counts = parts.getRange(4, 8).map(int.parse).toList();
    if (counts.any((int count) =>
            count < 0 || count > DB().ruleSettings.piecesCount) ||
        counts.every((int count) => count == 0)) {
      logger.e('Invalid counts. Must be between 0 and 12 and not all zero.');
      return false;
    }

    // Parts 8-9: Need to remove
    counts = parts.getRange(8, 10).map(int.parse).toList();
    if (counts.any((int count) => count < 0 || count > 3)) {
      logger.e('Invalid need to remove count. Must be 0, 1, 2, or 3.');
      return false;
    }

    // Part 10: Half-move clock
    final int halfMoveClock = int.parse(parts[10]);
    if (halfMoveClock < 0) {
      logger.e('Invalid half-move clock. Cannot be negative.');
      return false;
    }

    // Part 11: Full move number
    final int fullMoveNumber = int.parse(parts[11]);
    if (fullMoveNumber < 1) {
      logger.e('Invalid full move number. Must start at 1.');
      return false;
    }

    return true;
  }

  @visibleForTesting
  bool doMove(String move) {
    // TODO: Resign is not implemented
    if (move.length > "Player".length &&
        move.substring(0, "Player".length - 1) == "Player") {
      // TODO: What?
      if (move["Player".length] == "1") {
        return _resign(PieceColor.white);
      } else {
        return _resign(PieceColor.black);
      }
    }

    // TODO: Right?
    if (move == "Threefold Repetition. Draw!") {
      return true;
    }

    // TODO: Duplicate with switch (m.type) and should throw exception.
    if (move == "none") {
      return false;
    }

    // TODO: Duplicate with switch (m.type)
    if (move == "draw") {
      phase = Phase.gameOver;
      winner = PieceColor.draw;

      score[PieceColor.draw] = score[PieceColor.draw]! + 1;

      // TODO: WAR to judge rule50, and endgameNMoveRule is not right.
      if (DB().ruleSettings.nMoveRule > 0 &&
          posKeyHistory.length >= DB().ruleSettings.nMoveRule - 1) {
        gameOverReason = GameOverReason.drawFiftyMove;
      } else if (DB().ruleSettings.endgameNMoveRule <
              DB().ruleSettings.nMoveRule &&
          _isThreeEndgame &&
          posKeyHistory.length >= DB().ruleSettings.endgameNMoveRule - 1) {
        gameOverReason = GameOverReason.drawEndgameFiftyMove;
      } else if (DB().ruleSettings.threefoldRepetitionRule) {
        gameOverReason = GameOverReason.drawThreefoldRepetition; // TODO: Sure?
      } else {
        gameOverReason = GameOverReason.drawFullBoard; // TODO: Sure?
      }

      return true;
    }

    // TODO: Above is diff from position.cpp

    bool ret = false;

    final ExtMove m = ExtMove(move);

    // TODO: [Leptopoda] The below functions should all throw exceptions so the ret and conditional stuff can be removed
    switch (m.type) {
      case MoveType.remove:
        if (_removePiece(m.to) == const GameResponseOK()) {
          ret = true;
          st.rule50 = 0;
        } else {
          return false;
        }

        GameController().gameRecorder.lastPositionWithRemove =
            GameController().position.fen;

        break;
      case MoveType.move:
        ret = _movePiece(m.from, m.to);
        if (ret) {
          ++st.rule50;
        }
        break;
      case MoveType.place:
        ret = _putPiece(m.to);
        if (ret) {
          // Reset rule 50 counter
          st.rule50 = 0;
        }
        break;
      case MoveType.draw:
        return false; // TODO
      case MoveType.none:
        // ignore: only_throw_errors
        throw const EngineNoBestMove();
      case null:
        logger.e("Invalid MoveType");
        break;
    }

    if (!ret) {
      return false;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++_gamePly;
    ++st.pliesFromNull;

    if (_record != null && _record!.move.length > "-(1,2)".length) {
      if (st.key != posKeyHistory.lastF) {
        posKeyHistory.add(st.key);
        if (DB().ruleSettings.threefoldRepetitionRule && _hasGameCycle) {
          _setGameOver(PieceColor.draw, GameOverReason.drawThreefoldRepetition);
        }
      }
    } else {
      posKeyHistory.clear();
    }

    return true;
  }

  bool get _hasGameCycle {
    final int repetition = posKeyHistory.where((int i) => st.key == i).length;

    if (repetition >= 3) {
      logger.i("[position] Has game cycle.");
      return true;
    }

    return false;
  }

///////////////////////////////////////////////////////////////////////////////

  bool _putPiece(int s) {
    final PieceColor us = _sideToMove;

    if (phase == Phase.gameOver ||
        !(sqBegin <= s && s < sqEnd) ||
        _board[s] == us.opponent ||
        _board[s] == PieceColor.marked) {
      return false;
    }

    if (!canMoveDuringPlacingPhase() && _board[s] != PieceColor.none) {
      return false;
    }

    isNeedStalemateRemoval = false;

    if (phase == Phase.placing && action == Act.place) {
      if (canMoveDuringPlacingPhase()) {
        if (_board[s] == PieceColor.none) {
          if (_currentSquare[us] != 0) {
            return handleMovingPhaseForPutPiece(s);
          } else {
            selectedPieceNumber = 0;
            GameController().gameInstance.blurIndex = null;
          }
        } else {
          // Select piece
          if (_currentSquare[us] == s) {
            _currentSquare[us] = 0;
            selectedPieceNumber = 0;
            GameController().gameInstance.focusIndex = null;
            SoundManager().playTone(Sound.mill);
          } else {
            _currentSquare[us] = s;
            GameController().gameInstance.focusIndex = squareToIndex[s];
            SoundManager().playTone(Sound.select);
          }
          selectedPieceNumber = sqAttrList[s].placedPieceNumber;
          GameController().gameInstance.blurIndex = null;
          return true;
        }
      }

      if (pieceInHandCount[us] != null) {
        if (pieceInHandCount[us] == 0) {
          // TODO: Maybe setup invalid position and tap the board.
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear("FEN: ${GameController().position.fen}");
          return false;
        }
        pieceInHandCount[us] = pieceInHandCount[us]! - 1;
      }

      if (pieceOnBoardCount[us] != null) {
        pieceOnBoardCount[us] = pieceOnBoardCount[us]! + 1;
      }

      // Set square number
      placedPieceNumber++;
      sqAttrList[s].placedPieceNumber = placedPieceNumber;

      _grid[squareToIndex[s]!] = sideToMove;
      _board[s] = sideToMove;

      _currentSquare[sideToMove] = 0;

      _record = ExtMove("(${fileOf(s)},${rankOf(s)})");

      _updateKey(s);

      final int n = _millsCount(s);

      if (n == 0) {
        // If no Mill

        if (pieceToRemoveCount[PieceColor.white]! > 0 ||
            pieceToRemoveCount[PieceColor.black]! > 0) {
          logger.e("[position] putPiece: pieceToRemoveCount is not 0.");
          return false;
        }

        GameController().gameInstance.focusIndex = squareToIndex[s];
        SoundManager().playTone(Sound.place);

        // Begin of set side to move

        // Board is full at the end of Placing phase
        if (DB().ruleSettings.piecesCount == 12 &&
            (pieceOnBoardCount[PieceColor.white]! +
                    pieceOnBoardCount[PieceColor.black]! >=
                rankNumber * fileNumber)) {
          // TODO: BoardFullAction: Support other actions
          switch (DB().ruleSettings.boardFullAction) {
            case BoardFullAction.firstPlayerLose:
              _setGameOver(PieceColor.black, GameOverReason.loseFullBoard);
              return true;
            case BoardFullAction.firstAndSecondPlayerRemovePiece:
              pieceToRemoveCount[PieceColor.white] =
                  pieceToRemoveCount[PieceColor.black] = 1;
              changeSideToMove();
              break;
            case BoardFullAction.secondAndFirstPlayerRemovePiece:
              pieceToRemoveCount[PieceColor.white] =
                  pieceToRemoveCount[PieceColor.black] = 1;
              keepSideToMove();
              break;
            case BoardFullAction.sideToMoveRemovePiece:
              _sideToMove = DB().ruleSettings.isDefenderMoveFirst
                  ? PieceColor.black
                  : PieceColor.white;
              pieceToRemoveCount[sideToMove] = 1;
              keepSideToMove();
              break;
            case BoardFullAction.agreeToDraw:
              _setGameOver(PieceColor.draw, GameOverReason.drawFullBoard);
              return true;
            case null:
              logger.e("[position] putPiece: Invalid BoardFullAction.");
              break;
          }
        } else {
          // Board is not full at the end of Placing phase
          if (!handlePlacingPhaseEnd()) {
            changeSideToMove();
          }

          // Check if Stalemate and change side to move if needed
          if (_checkIfGameIsOver()) {
            return true;
          }
        }
        // End of set side to move
      } else {
        // If forming Mill
        final int rm = pieceToRemoveCount[sideToMove] =
            DB().ruleSettings.mayRemoveMultiple ? n : 1;
        _updateKeyMisc();

        GameController().gameInstance.focusIndex = squareToIndex[s];
        SoundManager().playTone(Sound.mill);

        if ((DB().ruleSettings.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase
                        .removeOpponentsPieceFromHandThenYourTurn ||
                DB().ruleSettings.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase
                        .removeOpponentsPieceFromHandThenOpponentsTurn) &&
            pieceInHandCount[_them] != null) {
          for (int i = 0; i < rm; i++) {
            if (pieceInHandCount[_them] == 0) {
              pieceToRemoveCount[sideToMove] = rm - i;
              _updateKeyMisc();
              action = Act.remove;
              return true;
            } else {
              if (pieceInHandCount[_them] == 0) {
                logger.e(
                  "[position] putPiece: pieceInHandCount[_them] is 0.",
                );
              }
              pieceInHandCount[_them] = pieceInHandCount[_them]! - 1;

              if (pieceToRemoveCount[sideToMove] == 0) {
                logger.e(
                  "[position] putPiece: pieceToRemoveCount[sideToMove] is 0.",
                );
              }
              pieceToRemoveCount[sideToMove] =
                  pieceToRemoveCount[sideToMove]! - 1;

              _updateKeyMisc();
            }

            if (!(pieceInHandCount[PieceColor.white]! >= 0 &&
                pieceInHandCount[PieceColor.black]! >= 0)) {
              logger.e("[position] putPiece: pieceInHandCount is negative.");
            }
          }

          if (!handlePlacingPhaseEnd()) {
            if (DB().ruleSettings.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase
                    .removeOpponentsPieceFromHandThenOpponentsTurn) {
              changeSideToMove();
            }
          }

          if (_checkIfGameIsOver()) {
            return true;
          }
        } else {
          action = Act.remove;
          return true;
        }
      }
    } else if (phase == Phase.moving) {
      return handleMovingPhaseForPutPiece(s);
    } else {
      return false;
    }

    return true;
  }

  bool handleMovingPhaseForPutPiece(int s) {
    if (_checkIfGameIsOver()) {
      return true;
    }

    // If illegal
    if (pieceOnBoardCount[sideToMove]! > DB().ruleSettings.flyPieceCount ||
        !DB().ruleSettings.mayFly ||
        pieceInHandCount[sideToMove]! > 0 ||
        pieceInHandCount[sideToMove.opponent]! > 0) {
      int md;

      for (md = 0; md < moveDirectionNumber; md++) {
        if (s == _adjacentSquares[_currentSquare[sideToMove]!][md]) {
          break;
        }
      }

      // Not in moveTable
      if (md == moveDirectionNumber) {
        logger.i(
          "[position] putPiece: [$s] is not in [${_currentSquare[sideToMove]}]'s move table.",
        );
        return false;
      }
    }

    _record = ExtMove(
      "(${fileOf(_currentSquare[sideToMove]!)},${rankOf(_currentSquare[sideToMove]!)})->(${fileOf(s)},${rankOf(s)})",
    );

    st.rule50++;

    _board[s] = _grid[squareToIndex[s]!] = _board[_currentSquare[sideToMove]!];
    _updateKey(s);
    _revertKey(_currentSquare[sideToMove]!);

    if (_currentSquare[sideToMove] == 0) {
      // TODO: Find the root cause and fix it
      logger.e(
        "[position] putPiece: _currentSquare[sideToMove] is 0.",
      );
      return false;
    }
    _board[_currentSquare[sideToMove]!] =
        _grid[squareToIndex[_currentSquare[sideToMove]!]!] = PieceColor.none;
    _currentSquare[sideToMove] = 0;

    // Set square number
    sqAttrList[s].placedPieceNumber = placedPieceNumber;

    if (selectedPieceNumber != 0) {
      sqAttrList[s].placedPieceNumber = selectedPieceNumber;
      selectedPieceNumber = 0;
    } else {
      sqAttrList[s].placedPieceNumber = placedPieceNumber;
    }

    final int n = _millsCount(s);

    if (n == 0) {
      // If no mill during Moving phase
      changeSideToMove();

      if (_checkIfGameIsOver()) {
        return true;
      }

      GameController().gameInstance.focusIndex = squareToIndex[s];

      SoundManager().playTone(Sound.place);
    } else {
      // If forming mill during Moving phase
      pieceToRemoveCount[sideToMove] =
          DB().ruleSettings.mayRemoveMultiple ? n : 1;
      _updateKeyMisc();
      action = Act.remove;
      GameController().gameInstance.focusIndex = squareToIndex[s];
      SoundManager().playTone(Sound.mill);
    }

    return true;
  }

  GameResponse _removePiece(int s) {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return const IllegalPhase();
    }

    if (action != Act.remove) {
      return const IllegalAction();
    }

    if (pieceToRemoveCount[sideToMove]! <= 0) {
      return const NoPieceToRemove();
    }

    // If piece is not their
    if (!(sideToMove.opponent == _board[s])) {
      return const CanNotRemoveSelf();
    }

    if (isStalemateRemoval(sideToMove)) {
      if (isAdjacentTo(s, sideToMove) == false) {
        return const CanNotRemoveNonadjacent();
      }
    } else if (!DB().ruleSettings.mayRemoveFromMillsAlways &&
        _potentialMillsCount(s, PieceColor.nobody) > 0 &&
        !_isAllInMills(sideToMove.opponent)) {
      return const CanNotRemoveMill();
    }

    _revertKey(s);

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.markAndDelayRemovingPieces &&
        phase == Phase.placing) {
      // Remove and mark
      _board[s] = _grid[squareToIndex[s]!] = PieceColor.marked;
      _updateKey(s);
    } else {
      // Remove only
      _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;
    }

    _record = ExtMove("-(${fileOf(s)},${rankOf(s)})");
    st.rule50 = 0; // TODO: Need to move out?

    if (pieceOnBoardCount[_them] != null) {
      pieceOnBoardCount[_them] = pieceOnBoardCount[_them]! - 1;
    }

    if (pieceOnBoardCount[_them]! + pieceInHandCount[_them]! <
        DB().ruleSettings.piecesAtLeastCount) {
      _setGameOver(sideToMove, GameOverReason.loseFewerThanThree);
      SoundManager().playTone(Sound.remove);
      return const GameResponseOK();
    }

    _currentSquare[sideToMove] = 0;

    pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! - 1;
    _updateKeyMisc();

    // Need to remove rest pieces.
    if (pieceToRemoveCount[sideToMove] != 0) {
      SoundManager().playTone(Sound.remove);
      return const GameResponseOK();
    }

    if (handlePlacingPhaseEnd() == false) {
      if (isStalemateRemoving) {
        isStalemateRemoving = false;
        keepSideToMove();
      } else {
        changeSideToMove();
      }
    }

    if (pieceToRemoveCount[sideToMove] != 0) {
      // Audios().playTone(Sound.remove);
      return const GameResponseOK();
    }

    if (pieceInHandCount[sideToMove] == 0) {
      if (_checkIfGameIsOver()) {
        SoundManager().playTone(Sound.remove);
        return const GameResponseOK();
      }
    }

    SoundManager().playTone(Sound.remove);
    return const GameResponseOK();
  }

  GameResponse _selectPiece(int sq) {
    // Allow selecting pieces during placing phase if allowed
    if (phase != Phase.moving &&
        !(phase == Phase.placing && canMoveDuringPlacingPhase())) {
      return const IllegalPhase();
    }

    if (action != Act.select && action != Act.place) {
      return const IllegalAction();
    }

    if (_board[sq] == PieceColor.none) {
      return const CanOnlyMoveToAdjacentEmptyPoints();
    }

    if (!(_board[sq] == sideToMove)) {
      return const SelectOurPieceToMove();
    }

    _currentSquare[sideToMove] = sq;
    action = Act.place;
    GameController().gameInstance.blurIndex = squareToIndex[sq];

    // Set square number
    selectedPieceNumber = sqAttrList[sq].placedPieceNumber;

    return const GameResponseOK();
  }

  bool handlePlacingPhaseEnd() {
    if (phase != Phase.placing ||
        pieceInHandCount[PieceColor.white]! > 0 ||
        pieceInHandCount[PieceColor.black]! > 0 ||
        pieceToRemoveCount[PieceColor.white]! > 0 ||
        pieceToRemoveCount[PieceColor.black]! > 0) {
      return false;
    }

    final bool invariant =
        DB().ruleSettings.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase
                    .removeOpponentsPieceFromHandThenOpponentsTurn ||
            (DB().ruleSettings.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase
                        .removeOpponentsPieceFromHandThenYourTurn &&
                DB().ruleSettings.mayRemoveMultiple == true) ||
            DB().ruleSettings.mayMoveInPlacingPhase == true;

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      _removeMarkedStones();
    } else if (invariant) {
      if (DB().ruleSettings.isDefenderMoveFirst == true) {
        setSideToMove(PieceColor.black);
        return true;
      } else {
        // Ignore
        return false;
      }
    }

    setSideToMove(DB().ruleSettings.isDefenderMoveFirst == true
        ? PieceColor.black
        : PieceColor.white);

    return true;
  }

  bool canMoveDuringPlacingPhase() {
    return DB().ruleSettings.mayMoveInPlacingPhase;
  }

  bool _resign(PieceColor loser) {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return false;
    }

    _setGameOver(loser.opponent, GameOverReason.loseResign);

    return true;
  }

  void _setGameOver(PieceColor w, GameOverReason reason) {
    phase = Phase.gameOver;
    gameOverReason = reason;
    winner = w;

    logger.i("[position] Game over, $w win, because of $reason");
    _updateScore();
  }

  void _updateScore() {
    if (phase == Phase.gameOver) {
      score[winner] = score[winner]! + 1;
    }
  }

  bool get _isThreeEndgame {
    if (phase == Phase.placing) {
      return false;
    }

    return pieceOnBoardCount[PieceColor.white] == 3 ||
        pieceOnBoardCount[PieceColor.black] == 3;
  }

  bool _checkIfGameIsOver() {
    if (phase == Phase.ready || phase == Phase.gameOver) {
      return true;
    }

    if (pieceOnBoardCount[sideToMove]! + pieceInHandCount[sideToMove]! <
        DB().ruleSettings.piecesAtLeastCount) {
      // Engine doesn't have this because of improving performance.
      _setGameOver(sideToMove.opponent, GameOverReason.loseFewerThanThree);
      return true;
    }

    if (DB().ruleSettings.nMoveRule > 0 &&
        posKeyHistory.length >= DB().ruleSettings.nMoveRule) {
      _setGameOver(PieceColor.draw, GameOverReason.drawFiftyMove);
      return true;
    }

    if (DB().ruleSettings.endgameNMoveRule < DB().ruleSettings.nMoveRule &&
        _isThreeEndgame &&
        posKeyHistory.length >= DB().ruleSettings.endgameNMoveRule) {
      _setGameOver(PieceColor.draw, GameOverReason.drawEndgameFiftyMove);
      return true;
    }

    // Stalemate.
    if (phase == Phase.moving &&
        action == Act.select &&
        _isAllSurrounded(sideToMove)) {
      switch (DB().ruleSettings.stalemateAction) {
        case StalemateAction.endWithStalemateLoss:
          _setGameOver(sideToMove.opponent, GameOverReason.loseNoLegalMoves);
          return true;
        case StalemateAction.changeSideToMove:
          changeSideToMove(); // TODO(calcitem): Need?
          break;
        case StalemateAction.removeOpponentsPieceAndMakeNextMove:
          pieceToRemoveCount[sideToMove] = 1;
          isStalemateRemoving = true;
          break;
        case StalemateAction.removeOpponentsPieceAndChangeSideToMove:
          pieceToRemoveCount[sideToMove] = 1;
          break;
        case StalemateAction.endWithStalemateDraw:
          _setGameOver(PieceColor.draw, GameOverReason.drawStalemateCondition);
          return true;
        case null:
          logger.e("[position] _checkIfGameIsOver: Invalid StalemateAction.");
          break;
      }
    }

    if (pieceToRemoveCount[sideToMove]! > 0) {
      action = Act.remove;
    }

    return false;
  }

  void _removeMarkedStones() {
    assert(DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces);

    int s = 0;

    for (int f = 1; f <= fileNumber; f++) {
      for (int r = 0; r < rankNumber; r++) {
        s = f * rankNumber + r;

        if (_board[s] == PieceColor.marked) {
          _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;
          _revertKey(s);
        }
      }
    }
  }

  void setSideToMove(PieceColor c) {
    if (sideToMove != c) {
      sideToMove = c;
      // us = c;
      st.key ^= _Zobrist.side;
    }

    _them = sideToMove.opponent;

    if (pieceInHandCount[sideToMove]! == 0) {
      phase = Phase.moving;
      action = Act.select;
    } else if (pieceInHandCount[sideToMove]! > 0) {
      phase = Phase.placing;
      action = Act.place;
    } else {
      logger.e("[position] setSideToMove: Invalid pieceInHandCount.");
    }

    if (pieceToRemoveCount[sideToMove]! > 0) {
      action = Act.remove;
    } else if (pieceToRemoveCount[sideToMove]! < 0) {
      logger.e("[position] setSideToMove: Invalid pieceToRemoveCount.");
    }
  }

  void keepSideToMove() {
    setSideToMove(_sideToMove);
    logger.t("[position] Keep $_sideToMove to move.");
  }

  void changeSideToMove() {
    setSideToMove(_sideToMove.opponent);

    logger.t("[position] $_sideToMove to move.");
  }

  /// Updates square if it hasn't been updated yet.
  int _updateKey(int s) {
    final PieceColor pieceType = _board[s];

    return st.key ^= _Zobrist.psq[pieceType.index][s];
  }

  /// If the square has been updated,
  /// then another update is equivalent to returning to
  /// the state before the update
  /// The significance of this function is to improve code readability.
  int _revertKey(int s) => _updateKey(s);

  void _updateKeyMisc() {
    st.key = st.key << _Zobrist.keyMiscBit >> _Zobrist.keyMiscBit;

    // TODO: pieceToRemoveCount[sideToMove] or
    // abs(pieceToRemoveCount[sideToMove] - pieceToRemoveCount[~sideToMove])?
    st.key |= pieceToRemoveCount[sideToMove]! << (32 - _Zobrist.keyMiscBit);
  }

  ///////////////////////////////////////////////////////////////////////////////

  int _potentialMillsCount(int to, PieceColor c, {int from = 0}) {
    int n = 0;
    PieceColor locbak = PieceColor.none;

    assert(0 <= from && from < sqNumber);

    if (c == PieceColor.nobody) {
      c = _board[to];
    }

    if (from != 0 && from >= sqBegin && from < sqEnd) {
      locbak = _board[from];
      _board[from] = _grid[squareToIndex[from]!] = PieceColor.none;
    }

    for (int ld = 0; ld < lineDirectionNumber; ld++) {
      if (c == _board[_millTable[to][ld][0]] &&
          c == _board[_millTable[to][ld][1]]) {
        n++;
      }
    }

    if (from != 0) {
      _board[from] = _grid[squareToIndex[from]!] = locbak;
    }

    return n;
  }

  int totalMillsCount(PieceColor pieceColor) {
    assert(pieceColor == PieceColor.white || pieceColor == PieceColor.black);

    int n = 0;

    for (final List<int> line in _millLinesHV) {
      if (_board[line[0]] == pieceColor &&
          _board[line[1]] == pieceColor &&
          _board[line[2]] == pieceColor) {
        n++;
      }
    }

    if (DB().ruleSettings.hasDiagonalLines == true) {
      for (final List<int> line in _millLinesD) {
        if (_board[line[0]] == pieceColor &&
            _board[line[1]] == pieceColor &&
            _board[line[2]] == pieceColor) {
          n++;
        }
      }
    }

    return n;
  }

  int _millsCount(int s) {
    int n = 0;
    final List<int?> idx = <int>[0, 0, 0];
    int min = 0;
    int? temp = 0;
    final PieceColor m = _board[s];

    for (int i = 0; i < idx.length; i++) {
      idx[0] = s;
      idx[1] = _millTable[s][i][0];
      idx[2] = _millTable[s][i][1];

      // No mill
      if (!(m == _board[idx[1]!] && m == _board[idx[2]!])) {
        continue;
      }

      // Close mill

      // Sort
      for (int j = 0; j < 2; j++) {
        min = j;

        for (int k = j + 1; k < 3; k++) {
          if (idx[min]! > idx[k]!) {
            min = k;
          }
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

  bool _isAllInMills(PieceColor c) {
    for (int i = sqBegin; i < sqEnd; i++) {
      if (_board[i] == c) {
        if (_potentialMillsCount(i, PieceColor.nobody) == 0) {
          return false;
        }
      }
    }

    return true;
  }

  bool _isAllSurrounded(PieceColor c) {
    // Full
    if (pieceOnBoardCount[PieceColor.white]! +
            pieceOnBoardCount[PieceColor.black]! >=
        rankNumber * fileNumber) {
      return true;
    }

    // Can fly
    if (pieceOnBoardCount[c]! <= DB().ruleSettings.flyPieceCount &&
        DB().ruleSettings.mayFly) {
      return false;
    }

    for (int s = sqBegin; s < sqEnd; s++) {
      if (c != _board[s]) {
        continue;
      }

      for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
        final int moveSquare = _adjacentSquares[s][d];
        if (moveSquare != 0 && _board[moveSquare] == PieceColor.none) {
          return false;
        }
      }
    }

    return true;
  }

  @visibleForTesting
  String? get movesSinceLastRemove {
    final GameRecorder recorder = GameController().gameRecorder;
    if (recorder.isEmpty) {
      return null;
    }

    final PointedListIterator<ExtMove> it = recorder.bidirectionalIterator;
    it.moveToLast();

    final StringBuffer buffer = StringBuffer();

    while (it.current != null && !it.current!.move.startsWith("-")) {
      if (!it.movePrevious()) {
        break;
      }
    }

    while (it.moveNext()) {
      buffer.writeSpace(it.current!.move);
    }

    final String moves = buffer.toString();

    assert(!moves.contains('-('));

    return moves.isNotEmpty ? moves : null;
  }
}

extension SetupPosition on Position {
  PieceColor get sideToSetup => _sideToMove;

  set sideToSetup(PieceColor color) {
    _sideToMove = color;
  }

  void reset() {
    phase = Phase.placing;
    action = Act.place;

    _sideToMove = PieceColor.white;
    _them = PieceColor.black;

    result = null;
    winner = PieceColor.nobody;
    gameOverReason = null;

    _record = null;
    _currentSquare[PieceColor.white] = _currentSquare[PieceColor.black] = 0;

    _gamePly = 0;

    pieceOnBoardCount[PieceColor.white] = 0;
    pieceOnBoardCount[PieceColor.black] = 0;

    pieceInHandCount[PieceColor.white] = DB().ruleSettings.piecesCount;
    pieceInHandCount[PieceColor.black] = DB().ruleSettings.piecesCount;

    pieceToRemoveCount[PieceColor.white] = 0;
    pieceToRemoveCount[PieceColor.black] = 0;

    isNeedStalemateRemoval = false;
    isStalemateRemoving = false;

    placedPieceNumber = 0;
    selectedPieceNumber = 0;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = 0;
    }

    for (int i = 0; i < sqNumber; i++) {
      _board[i] = PieceColor.none;
    }

    for (int i = 0; i < 7 * 7; i++) {
      _grid[i] = PieceColor.none;
    }

    st.rule50 = 0;
    st.key = 0;
    st.pliesFromNull = 0;
  }

  void copyWith(Position pos) {
    phase = pos.phase;
    action = pos.action;

    _sideToMove = pos._sideToMove;
    _them = pos._them;

    result = pos.result;
    winner = pos.winner;
    gameOverReason = pos.gameOverReason;

    _record = pos._record;
    _currentSquare = pos._currentSquare;

    _gamePly = pos._gamePly;

    pieceOnBoardCount[PieceColor.white] =
        pos.pieceOnBoardCount[PieceColor.white]!;
    pieceOnBoardCount[PieceColor.black] =
        pos.pieceOnBoardCount[PieceColor.black]!;

    if (pieceOnBoardCount[PieceColor.white]! < 0 ||
        pieceOnBoardCount[PieceColor.black]! < 0) {
      logger.e(
        "[position] copyWith: pieceOnBoardCount is less than 0.",
      );
    }

    pieceInHandCount[PieceColor.white] =
        pos.pieceInHandCount[PieceColor.white]!;
    pieceInHandCount[PieceColor.black] =
        pos.pieceInHandCount[PieceColor.black]!;

    if (pieceInHandCount[PieceColor.white]! < 0 ||
        pieceInHandCount[PieceColor.black]! < 0) {
      logger.e(
        "[position] copyWith: pieceInHandCount is less than 0.",
      );
    }

    pieceToRemoveCount[PieceColor.white] =
        pos.pieceToRemoveCount[PieceColor.white]!;
    pieceToRemoveCount[PieceColor.black] =
        pos.pieceToRemoveCount[PieceColor.black]!;

    if (pieceToRemoveCount[PieceColor.white]! < 0 ||
        pieceToRemoveCount[PieceColor.black]! < 0) {
      logger.e(
        "[position] copyWith: pieceToRemoveCount is less than 0.",
      );
    }

    isNeedStalemateRemoval = pos.isNeedStalemateRemoval;
    isStalemateRemoving = pos.isStalemateRemoving;

    placedPieceNumber = pos.placedPieceNumber;
    selectedPieceNumber = pos.selectedPieceNumber;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = pos.sqAttrList[i].placedPieceNumber;
    }

    for (int i = 0; i < sqNumber; i++) {
      _board[i] = pos._board[i];
    }

    for (int i = 0; i < 7 * 7; i++) {
      _grid[i] = pos._grid[i];
    }

    st.rule50 = pos.st.rule50;
    st.key = pos.st.key;
    st.pliesFromNull = pos.st.pliesFromNull;
  }

  Position clone() {
    final Position pos = Position();
    pos.copyWith(this);
    return pos;
  }

  bool _putPieceForSetupPosition(int s) {
    final PieceColor piece = GameController().isPositionSetupMarkedPiece
        ? PieceColor.marked
        : sideToMove;
    //final us = _sideToMove;

    // TODO: Allow to overwrite.
    if (_board[s] != PieceColor.none) {
      SoundManager().playTone(Sound.illegal);
      return false;
    }

    if (countPieceOnBoard(piece) == DB().ruleSettings.piecesCount) {
      SoundManager().playTone(Sound.illegal);
      return false;
    }

    if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      if (countTotalPieceOnBoard() >= DB().ruleSettings.piecesCount * 2) {
        SoundManager().playTone(Sound.illegal);
        return false;
      }
    }

    /*
    // No need to update
    if (pieceInHandCount[us] != null) {
      pieceInHandCount[us] = pieceInHandCount[us]! - 1;
    }

    if (pieceOnBoardCount[us] != null) {
      pieceOnBoardCount[us] = pieceOnBoardCount[us]! + 1;
    }
     */

    _grid[squareToIndex[s]!] = piece;
    _board[s] = piece;

    //MillController().gameInstance.focusIndex = squareToIndex[s];
    SoundManager().playTone(GameController().isPositionSetupMarkedPiece
        ? Sound.remove
        : Sound.place);

    GameController().setupPositionNotifier.updateIcons();

    return true;
  }

  GameResponse _removePieceForSetupPosition(int s) {
    if (action != Act.remove) {
      SoundManager().playTone(Sound.illegal);
      return const IllegalAction();
    }

    if (_board[s] == PieceColor.none) {
      SoundManager().playTone(Sound.illegal);
      return const IllegalAction();
    }

    // Remove only
    _board[s] = _grid[squareToIndex[s]!] = PieceColor.none;

    /*
    // No need to update
    // TODO: How to use it to verify?
    if (pieceOnBoardCount[_them] != null) {
      pieceOnBoardCount[_them] = pieceOnBoardCount[_them]! - 1;
    }
     */

    SoundManager().playTone(Sound.remove);
    GameController().setupPositionNotifier.updateIcons();

    return const GameResponseOK();
  }

  int countPieceOnBoard(PieceColor pieceColor) {
    int count = 0;
    for (int i = 0; i < sqNumber; i++) {
      if (_board[i] == pieceColor) {
        count++;
      }
    }
    return count;
  }

  int countPieceOnBoardMax() {
    final int w = countPieceOnBoard(PieceColor.white);
    final int b = countPieceOnBoard(PieceColor.black);

    return w > b ? w : b;
  }

  int countTotalPieceOnBoard() {
    return countPieceOnBoard(PieceColor.white) +
        countPieceOnBoard(PieceColor.black) +
        countPieceOnBoard(PieceColor.marked);
  }

  bool isBoardFullRemovalAtPlacingPhaseEnd() {
    if (DB().ruleSettings.piecesCount == 12 &&
        DB().ruleSettings.boardFullAction != BoardFullAction.firstPlayerLose &&
        DB().ruleSettings.boardFullAction != BoardFullAction.agreeToDraw &&
        phase == Phase.placing &&
        pieceInHandCount[PieceColor.white] == 0 &&
        pieceInHandCount[PieceColor.black] == 0 &&
        // TODO: Performance
        totalMillsCount(PieceColor.black) == 0) {
      return true;
    }

    return false;
  }

  bool isAdjacentTo(int sq, PieceColor c) {
    for (int d = moveDirectionBegin; d < moveDirectionNumber; d++) {
      final int moveSquare = Position._adjacentSquares[sq][d];
      if (moveSquare != 0 && _board[moveSquare] == c) {
        return true;
      }
    }
    return false;
  }

  bool isStalemateRemoval(PieceColor c) {
    if (isBoardFullRemovalAtPlacingPhaseEnd()) {
      return true;
    }

    if ((DB().ruleSettings.stalemateAction ==
                StalemateAction.removeOpponentsPieceAndChangeSideToMove ||
            DB().ruleSettings.stalemateAction ==
                StalemateAction.removeOpponentsPieceAndMakeNextMove) ==
        false) {
      return false;
    }

    if (isStalemateRemoving == true) {
      return true;
    }

    // TODO: StalemateAction: Improve performance.
    if (_isAllSurrounded(c)) {
      return true;
    }

    return false;
  }
}
