// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position.dart

part of '../mill.dart';

List<int> posKeyHistory = <int>[];

class SquareAttribute {
  SquareAttribute({
    required this.placedPieceNumber,
    this.specialPiece,
  });

  int placedPieceNumber;
  SpecialPiece? specialPiece;
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

  bool isEmpty() {
    return pieceInHandCount[PieceColor.white]! ==
            DB().ruleSettings.piecesCount &&
        pieceInHandCount[PieceColor.black]! == DB().ruleSettings.piecesCount &&
        pieceOnBoardCount[PieceColor.white]! == 0 &&
        pieceOnBoardCount[PieceColor.black]! == 0;
  }

  bool isNeedStalemateRemoval = false;
  bool isStalemateRemoving = false;

  /// Special piece selection bitmask for Zhuolu Chess (64-bit)
  /// Bits 0-23: White player's 6 selected pieces (4 bits each)
  /// Bits 24-47: Black player's 6 selected pieces (4 bits each)
  /// Bits 48-63: Reserved for future use
  int _specialPieceSelectionMask = 0;

  /// Available special pieces bitmask for each player
  /// Each bit represents one of the 15 special pieces (0-14)
  final Map<PieceColor, int> _availableSpecialPiecesMask = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
  };

  /// Currently selected piece type for placement (null = normal piece)
  SpecialPiece? _selectedPieceForPlacement;

  /// Zhuolu Chess capture statistics for game over display
  ZhuoluCaptureStats? _zhuoluCaptureStats;

  /// Return true if every playable square has no empty piece (marked counts as occupied)
  bool _isBoardFullyOccupied() {
    final List<int> emptySquares = <int>[];
    for (int s = sqBegin; s < sqEnd; s++) {
      if (_board[s] == PieceColor.none) {
        emptySquares.add(s);
      }
    }
    if (emptySquares.isNotEmpty) {
      logger.i("[Board Check] Board not full. Empty squares: $emptySquares");
      return false;
    }
    logger.i("[Board Check] Board is fully occupied.");
    return true;
  }

  /// Check if board is full and handle game ending if needed
  bool _checkAndHandleBoardFull() {
    logger.i("[Board Check] Calling _checkAndHandleBoardFull().");
    // Check if board is full
    if (_isBoardFullyOccupied()) {
      logger.i("[Board Check] Board is full, triggering game end.");
      if (DB().ruleSettings.zhuoluMode) {
        // In Zhuolu mode: end the game early and determine the result by counting captured pieces
        _endGameByCapturedCountsZhuolu();
        return true;
      } else if (DB().ruleSettings.piecesCount == 12) {
        // Legacy branch for classic 12-piece rules
        switch (DB().ruleSettings.boardFullAction) {
          case BoardFullAction.firstPlayerLose:
            setGameOver(PieceColor.black, GameOverReason.loseFullBoard);
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
            setGameOver(PieceColor.draw, GameOverReason.drawFullBoard);
            return true;
          case null:
            logger.e("[position] putPiece: Invalid BoardFullAction.");
            break;
        }
      }
    }
    return false;
  }

  /// Ends the game by comparing captured counts so far in Zhuolu mode.
  /// Winner is the player who lost fewer pieces; equal means draw.
  void _endGameByCapturedCountsZhuolu() {
    final int initialPieces = DB().ruleSettings.piecesCount;
    final int whiteRemaining = pieceOnBoardCount[PieceColor.white]! +
        pieceInHandCount[PieceColor.white]!;
    final int blackRemaining = pieceOnBoardCount[PieceColor.black]! +
        pieceInHandCount[PieceColor.black]!;
    final int whiteCaptured = initialPieces - whiteRemaining;
    final int blackCaptured = initialPieces - blackRemaining;

    logger.i(
        "[position] Zhuolu game ending - White captured: $whiteCaptured, Black captured: $blackCaptured");

    // Store capture statistics for UI display
    _zhuoluCaptureStats = ZhuoluCaptureStats(
      whiteCaptured: whiteCaptured,
      blackCaptured: blackCaptured,
    );

    if (whiteCaptured > blackCaptured) {
      // White lost more pieces, Black wins
      setGameOver(PieceColor.black, GameOverReason.zhuoluCaptureVictory);
    } else if (blackCaptured > whiteCaptured) {
      // Black lost more pieces, White wins
      setGameOver(PieceColor.white, GameOverReason.zhuoluCaptureVictory);
    } else {
      setGameOver(PieceColor.draw, GameOverReason.zhuoluCaptureDraw);
    }
  }

  bool isNoDraw() {
    if (score[PieceColor.white]! > 0 || score[PieceColor.black]! > 0) {
      return true;
    }
    return false;
  }

  int _gamePly = 0;

  /// _roundNumber tracks which round we are in. Each cycle of White->Black
  /// is one complete round. Whenever we switch from Black back to White,
  /// we increment this counter.
  int _roundNumber = 1;

  PieceColor _sideToMove = PieceColor.white;

  final StateInfo st = StateInfo();

  PieceColor _them = PieceColor.black;
  PieceColor winner = PieceColor.nobody;

  GameOverReason? gameOverReason;

  /// Indicates whether the current position already has a game result.
  bool get hasGameResult => phase == Phase.gameOver;

  /// The reason for game over, if any.
  GameOverReason? get reason => gameOverReason;

  /// Zhuolu Chess capture statistics, if available.
  ZhuoluCaptureStats? get zhuoluCaptureStats => _zhuoluCaptureStats;

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

  Map<PieceColor, int> _lastMillFromSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, int> _lastMillToSquare = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, int> _formedMillsBB = <PieceColor, int>{
    PieceColor.white: 0,
    PieceColor.black: 0,
    PieceColor.draw: 0,
  };

  Map<PieceColor, List<List<int>>> _formedMills = <PieceColor, List<List<int>>>{
    PieceColor.white: <List<int>>[],
    PieceColor.black: <List<int>>[],
    PieceColor.draw: <List<int>>[],
  };

  Map<PieceColor, List<List<int>>> get formedMills => _formedMills;

  ExtMove? _record;

  static List<List<List<int>>> get _millTable => _Mills.millTableInit;

  static List<List<int>> get _adjacentSquares => _Mills.adjacentSquaresInit;

  static List<List<int>> get _millLinesHV => _Mills._horizontalAndVerticalLines;

  static List<List<int>> get _millLinesD => _Mills._diagonalLines;

  PieceColor pieceOnGrid(int index) => _grid[index];

  PieceColor get sideToMove => _sideToMove;

  /// Convert special piece type to character for Zhuolu Chess
  String _specialPieceToChar(SpecialPiece specialType, PieceColor color) {
    if (specialType == null) {
      // Return normal piece character based on color
      return color.string;
    }

    // Map special pieces to their assigned letters
    // White pieces use uppercase, black pieces use lowercase
    switch (specialType) {
      case SpecialPiece.huangDi:
        return (color == PieceColor.white) ? "Y" : "y"; // Yellow Emperor
      case SpecialPiece.nuBa:
        return (color == PieceColor.white) ? "N" : "n"; // Nüba
      case SpecialPiece.yanDi:
        return (color == PieceColor.white) ? "F" : "f"; // Flame Emperor
      case SpecialPiece.chiYou:
        return (color == PieceColor.white) ? "C" : "c"; // Chiyou
      case SpecialPiece.changXian:
        return (color == PieceColor.white) ? "A" : "a"; // Changxian
      case SpecialPiece.xingTian:
        return (color == PieceColor.white)
            ? "T"
            : "t"; // Xingtian (using T to avoid conflict with MARKED_PIECE 'X')
      case SpecialPiece.zhuRong:
        return (color == PieceColor.white) ? "Z" : "z"; // Zhurong
      case SpecialPiece.yuShi:
        return (color == PieceColor.white) ? "U" : "u"; // Yushi
      case SpecialPiece.fengHou:
        return (color == PieceColor.white) ? "E" : "e"; // Fenghou
      case SpecialPiece.gongGong:
        return (color == PieceColor.white) ? "G" : "g"; // Gonggong
      case SpecialPiece.nuWa:
        return (color == PieceColor.white) ? "W" : "w"; // Nüwa
      case SpecialPiece.fuXi:
        return (color == PieceColor.white) ? "I" : "i"; // Fuxi
      case SpecialPiece.kuaFu:
        return (color == PieceColor.white) ? "K" : "k"; // Kuafu
      case SpecialPiece.yingLong:
        return (color == PieceColor.white) ? "L" : "l"; // Yinglong
      case SpecialPiece.fengBo:
        return (color == PieceColor.white) ? "B" : "b"; // Fengbo
    }
  }

  /// Get piece character for FEN, considering special pieces for Zhuolu Chess
  String _pieceToCharForFEN(int square) {
    final PieceColor piece = pieceOnGrid(squareToIndex[square]!);

    // Handle empty squares and marked pieces
    if (piece == PieceColor.none) {
      return "*";
    }
    if (piece == PieceColor.marked) {
      return "X";
    }

    // For Zhuolu Chess, check if this square has a special piece
    if (DB().ruleSettings.zhuoluMode) {
      final SpecialPiece? specialType = getSpecialPieceAt(square);
      if (specialType != null) {
        return _specialPieceToChar(specialType, piece);
      }
    }

    // Normal pieces
    return piece.string;
  }

  /// Convert character to special piece type for Zhuolu Chess
  SpecialPiece? _charToSpecialPieceType(String ch) {
    switch (ch) {
      // Both uppercase and lowercase map to same special piece type
      case 'Y':
      case 'y':
        return SpecialPiece.huangDi; // Yellow Emperor
      case 'N':
      case 'n':
        return SpecialPiece.nuBa; // Nüba
      case 'F':
      case 'f':
        return SpecialPiece.yanDi; // Flame Emperor
      case 'C':
      case 'c':
        return SpecialPiece.chiYou; // Chiyou
      case 'A':
      case 'a':
        return SpecialPiece.changXian; // Changxian
      case 'T':
      case 't':
        return SpecialPiece
            .xingTian; // Xingtian (using T to avoid conflict with MARKED_PIECE 'X')
      case 'Z':
      case 'z':
        return SpecialPiece.zhuRong; // Zhurong
      case 'U':
      case 'u':
        return SpecialPiece.yuShi; // Yushi
      case 'E':
      case 'e':
        return SpecialPiece.fengHou; // Fenghou
      case 'G':
      case 'g':
        return SpecialPiece.gongGong; // Gonggong
      case 'W':
      case 'w':
        return SpecialPiece.nuWa; // Nüwa
      case 'I':
      case 'i':
        return SpecialPiece.fuXi; // Fuxi
      case 'K':
      case 'k':
        return SpecialPiece.kuaFu; // Kuafu
      case 'L':
      case 'l':
        return SpecialPiece.yingLong; // Yinglong
      case 'B':
      case 'b':
        return SpecialPiece.fengBo; // Fengbo
      default:
        return null; // Normal piece or unrecognized character
    }
  }

  /// Check if a character represents a special piece
  bool _isSpecialPieceChar(String ch) {
    return _charToSpecialPieceType(ch) != null;
  }

  /// Get color from special piece character
  PieceColor _colorFromSpecialPieceChar(String ch) {
    if (ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
      return PieceColor.white; // Uppercase = white
    } else if (ch.toLowerCase() == ch && ch.toUpperCase() != ch) {
      return PieceColor.black; // Lowercase = black
    }
    return PieceColor.none; // Invalid character
  }

  set sideToMove(PieceColor color) {
    _sideToMove = color;
    _them = _sideToMove.opponent;
  }

  bool _movePiece(int from, int to) {
    // Ensure selecting the piece succeeds before placing it.
    // Previously this method ignored the return value of _selectPiece
    // and relied on exceptions, which _selectPiece does not throw.
    final GameResponse selectResult = _selectPiece(from);
    if (selectResult is! GameResponseOK) {
      return false;
    }

    return _putPiece(to);
  }

  /// Returns a FEN representation of the position.
  /// Example: "@*O@O*O*/O*@@O@@@/O@O*@*O* b m s 8 0 9 0 0 0 0 0 0 0 3 10"
  /// Format: "[Inner ring]/[Middle Ring]/[Outer Ring]
  /// [Side to Move] [Phase] [Action]
  /// [White Piece On Board] [White Piece In Hand]
  /// [Black Piece On Board] [Black Piece In Hand]
  /// [White Piece to Remove] [Black Piece to Remove]
  /// [White Piece Last Mill From Square] [White Piece Last Mill To Square]
  /// [Black Piece Last Mill From Square] [Black Piece Last Mill To Square]
  /// [MillsBitmask]
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
        final int square = makeSquare(file, rank);
        buffer.write(_pieceToCharForFEN(square));
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
    buffer.writeSpace(_lastMillFromSquare[PieceColor.white]);
    buffer.writeSpace(_lastMillToSquare[PieceColor.white]);
    buffer.writeSpace(_lastMillFromSquare[PieceColor.black]);
    buffer.writeSpace(_lastMillToSquare[PieceColor.black]);

    buffer.writeSpace((_formedMillsBB[PieceColor.white]! << 32) |
        _formedMillsBB[PieceColor.black]!);

    final int sideIsBlack = _sideToMove == PieceColor.black ? 1 : 0;

    buffer.write("${st.rule50} ${1 + (_gamePly - sideIsBlack) ~/ 2}");

    // Add special piece selection mask for Zhuolu Chess
    if (DB().ruleSettings.zhuoluMode) {
      buffer.writeSpace(_specialPieceSelectionMask);
    }

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
        final String charAtPos = ring[file - 1][rank - 1];
        final int sq = makeSquare(file, rank);

        PieceColor pieceColor;
        SpecialPiece? specialType;

        // Check if this is a special piece character for Zhuolu Chess
        if (DB().ruleSettings.zhuoluMode && _isSpecialPieceChar(charAtPos)) {
          pieceColor = _colorFromSpecialPieceChar(charAtPos);
          specialType = _charToSpecialPieceType(charAtPos);

          // Store special piece information
          if (specialType != null) {
            sqAttrList[sq].specialPiece = specialType;
          }
        } else {
          // Normal piece or empty square
          pieceColor = pieceMap[charAtPos]!;
          sqAttrList[sq].specialPiece = null; // Clear special piece info
        }

        _board[sq] = pieceColor;
        _grid[squareToIndex[sq]!] = pieceColor;
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

    final String whiteLastMillFromSquareStr = l[10];
    _lastMillFromSquare[PieceColor.white] =
        int.parse(whiteLastMillFromSquareStr);

    final String whiteLastMillToSquareStr = l[11];
    _lastMillToSquare[PieceColor.white] = int.parse(whiteLastMillToSquareStr);

    final String blackLastMillFromSquareStr = l[12];
    _lastMillFromSquare[PieceColor.black] =
        int.parse(blackLastMillFromSquareStr);

    final String blackLastMillToSquareStr = l[13];
    _lastMillToSquare[PieceColor.black] = int.parse(blackLastMillToSquareStr);

    final String millsBitmaskStr = l[14];
    setFormedMillsBB(int.parse(millsBitmaskStr));

    final String rule50Str = l[15];
    st.rule50 = int.parse(rule50Str);

    final String gamePlyStr = l[16];
    // Convert fullmove (starts from 1) to internal half-move ply
    // Formula matches C++: gamePly = max(2*(fullmove-1),0) + (sideToMove==BLACK)
    final int fullmove = int.parse(gamePlyStr);
    final int sideIsBlackInt = _sideToMove == PieceColor.black ? 1 : 0;
    _gamePly = (fullmove <= 1 ? 0 : 2 * (fullmove - 1)) + sideIsBlackInt;

    // Parse special piece selection mask for Zhuolu Chess
    if (DB().ruleSettings.zhuoluMode && l.length > 17) {
      final String specialPieceSelectionMaskStr = l[17];
      _specialPieceSelectionMask = int.parse(specialPieceSelectionMaskStr);
      _updateAvailablePiecesFromMask();
    }

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
    if (parts.length < 17) {
      logger.e('FEN does not contain enough parts.');
      return false;
    }

    // Part 0: Piece placement
    final String board = parts[0];
    if (board.length != 26 || board[8] != '/' || board[17] != '/') {
      logger.e('Invalid piece placement format.');
      return false;
    }

    // Check valid characters based on game mode
    RegExp validCharsRegex;
    if (DB().ruleSettings.zhuoluMode) {
      // For Zhuolu Chess, allow special piece characters
      validCharsRegex = RegExp(r'^[*OX@/YNFCATZUEGWIKLBynfcatzuegwiklb]+$');
    } else {
      // For normal mode, only basic characters
      validCharsRegex = RegExp(r'^[*OX@/]+$');
    }

    if (!validCharsRegex.hasMatch(board)) {
      logger.e('Invalid piece placement format for current game mode.');
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
    if (counts.any((int count) => count < -7 || count > 7)) {
      logger.e('Invalid need to remove count. Must be between -7 and 7.');
      return false;
    }

    // Parts 10-13: Last mill square
    counts = parts.getRange(10, 14).map(int.parse).toList();
    if (counts.any((int count) => count != 0 && (count < 8 || count > 32))) {
      logger.e('Invalid last mill square. Must be 0 or between 8 and 32.');
      return false;
    }

    // Part 14: Mills bitmask
    final int millsBitmask = int.parse(parts[14]);
    // Check if the lowest 8 bits are not zero
    if ((millsBitmask & 0xFF) != 0) {
      logger.e('The lowest 8 bits are not zero.');
      return false;
    }

    // Check if bits 32 to 39 are not zero
    // 0xFF << 32 shifts 0xFF (which is 8 bits of 1s) left by 32 positions to reach the 32nd position
    if ((millsBitmask & (0xFF << 32)) != 0) {
      logger.e('Bits 32 to 39 are not zero.');
      return false;
    }

    // Part 15: Half-move clock
    final int halfMoveClock = int.parse(parts[15]);
    if (halfMoveClock < 0) {
      logger.e('Invalid half-move clock. Cannot be negative.');
      return false;
    }

    // Part 16: Full move number
    final int fullMoveNumber = int.parse(parts[16]);
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

    final ExtMove m = ExtMove(move, side: _sideToMove);

    // Store the special piece info from the move for AI moves in Zhuolu mode
    if (DB().ruleSettings.zhuoluMode &&
        GameController().gameInstance.isAiSideToMove &&
        m.specialPiece != null) {
      _selectedPieceForPlacement = m.specialPiece;
      logger.i(
          "[position] AI move $move parsed as ${m.specialPiece} to square ${m.to} (${ExtMove.sqToNotation(m.to)})");
    }

    // TODO: [Leptopoda] The below functions should all throw exceptions so the ret and conditional stuff can be removed
    switch (m.type) {
      case MoveType.remove:
        // Handle special case where m.to is -1 for special piece removal
        if (m.to == -1 &&
            DB().ruleSettings.zhuoluMode &&
            m.specialPiece != null) {
          // For Zhuolu special piece removal, find the actual square to remove
          final int actualSquare =
              _findSpecialPieceSquare(m.specialPiece!, sideToMove.opponent);
          if (actualSquare != -1) {
            if (_removePiece(actualSquare) == const GameResponseOK()) {
              ret = true;
              st.rule50 = 0;
              GameController().gameInstance.removeIndex =
                  squareToIndex[actualSquare];
              GameController().animationManager.animateRemove();
            } else {
              return false;
            }
          } else {
            logger.e(
                "[position] Cannot find special piece ${m.specialPiece} to remove");
            return false;
          }
        } else if (m.to >= 0 && m.to < _board.length) {
          // Normal removal with valid square index
          if (_removePiece(m.to) == const GameResponseOK()) {
            ret = true;
            st.rule50 = 0;
            GameController().gameInstance.removeIndex = squareToIndex[m.to];
            GameController().animationManager.animateRemove();
          } else {
            return false;
          }
        } else {
          logger.e("[position] Invalid square index for removal: ${m.to}");
          return false;
        }

        if (_isGameControllerInitialized()) {
          GameController().gameRecorder.lastPositionWithRemove =
              GameController().position.fen;
        }

        break;
      case MoveType.move:
        ret = _movePiece(m.from, m.to);
        if (ret) {
          ++st.rule50;
          GameController().gameInstance.removeIndex = null;
          GameController().animationManager.animateMove();
        }
        break;
      case MoveType.place:
        ret = _putPiece(m.to);
        if (ret) {
          // Reset rule 50 counter
          st.rule50 = 0;
          GameController().gameInstance.removeIndex = null;
          //GameController().gameInstance.focusIndex = squareToIndex[m.to];
          //GameController().gameInstance.blurIndex = squareToIndex[m.from];
          GameController().animationManager.animatePlace();
        }
        break;
      case MoveType.draw:
        return false; // TODO
      case MoveType.none:
        // ignore: only_throw_errors
        throw const EngineNoBestMove();
    }

    // Clear the temporary selection after processing
    if (DB().ruleSettings.zhuoluMode &&
        GameController().gameInstance.isAiSideToMove) {
      _selectedPieceForPlacement = null;
    }

    if (!ret) {
      return false;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++_gamePly;
    ++st.pliesFromNull;

    // Check move type instead of string length for position key history
    if (_record != null && _record!.type == MoveType.move) {
      if (st.key != posKeyHistory.lastF) {
        posKeyHistory.add(st.key);
        if (DB().ruleSettings.threefoldRepetitionRule && _hasGameCycle) {
          setGameOver(PieceColor.draw, GameOverReason.drawThreefoldRepetition);
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
        _board[s] == us.opponent) {
      return false;
    }

    // Check special piece placement rules for Zhuolu Chess
    if (DB().ruleSettings.zhuoluMode) {
      final List<SpecialPiece> availablePieces = getAvailableSpecialPieces(us);
      SpecialPiece? targetSpecialPiece;

      // For AI moves, use the piece specified by the engine
      if (GameController().gameInstance.isAiSideToMove &&
          _selectedPieceForPlacement != null) {
        targetSpecialPiece = _selectedPieceForPlacement;
      } else {
        // For human moves or fallback, use first available
        targetSpecialPiece =
            availablePieces.isNotEmpty ? availablePieces.first : null;
      }

      if (!_canPlaceSpecialPieceAt(s, targetSpecialPiece)) {
        logger.w(
            "[position] Cannot place special piece $targetSpecialPiece at square $s (${ExtMove.sqToNotation(s)}). Square state: ${_board[s]}");
        return false;
      }
    } else {
      // Normal placement rules
      if (_board[s] == PieceColor.marked) {
        return false;
      }
    }

    // For Zhuolu Chess, check special piece placement rules first
    if (DB().ruleSettings.zhuoluMode) {
      // Special pieces might have different placement rules
      final SpecialPiece? targetPiece = _selectedPieceForPlacement;
      if (targetPiece != null) {
        // Special piece placement - use _canPlaceSpecialPieceAt result
        // (already checked above)
      } else if (_board[s] != PieceColor.none) {
        // Normal piece trying to place on occupied square
        return false;
      }
    } else {
      // Standard game mode
      if (!canMoveDuringPlacingPhase() && _board[s] != PieceColor.none) {
        return false;
      }
    }

    if (DB().ruleSettings.restrictRepeatedMillsFormation &&
        _currentSquare[us] == _lastMillToSquare[us] &&
        _currentSquare[us] != 0 &&
        s == _lastMillFromSquare[us]) {
      if (_potentialMillsCount(s, us, from: _currentSquare[us]!) > 0 &&
          _millsCount(_currentSquare[us]!) > 0) {
        // TODO: Show text
        rootScaffoldMessengerKey.currentState!.showSnackBarClear("3->3 X");
        return false;
      }
    }

    isNeedStalemateRemoval = false;

    // Check if this is the first move in Zhuolu Chess and special pieces need to be selected
    if (DB().ruleSettings.zhuoluMode &&
        _gamePly == 0 &&
        !hasCompleteSpecialPieceSelections) {
      // Need to select special pieces first - this will be handled by tap handler
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('请先完成特殊棋子选择'),
          duration: Duration(seconds: 2),
        ),
      );
      return false; // Prevent placement until selection is complete
    }

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
      _lastMillFromSquare[sideToMove] = _lastMillToSquare[sideToMove] = 0;

      // Defer constructing record until we know if a special piece was placed
      _updateKey(s);

      // Handle special piece placement for Zhuolu Chess
      SpecialPiece? placedSpecialPiece;
      if (DB().ruleSettings.zhuoluMode) {
        final List<SpecialPiece> availablePieces =
            getAvailableSpecialPieces(us);
        final bool isAIMove = GameController().gameInstance.isAiSideToMove;

        if (isAIMove) {
          // For AI moves, the special piece type MUST be specified by the engine
          // No fallback evaluation should be performed on Flutter side
          if (_selectedPieceForPlacement != null &&
              availablePieces.contains(_selectedPieceForPlacement)) {
            // Use the piece type specified by the engine via doMove
            placedSpecialPiece = _selectedPieceForPlacement;

            sqAttrList[s].specialPiece = placedSpecialPiece;
            if (placedSpecialPiece != null) {
              _removeSpecialPieceFromAvailable(us, placedSpecialPiece);
            }

            // Trigger placement ability
            if (placedSpecialPiece != null) {
              _triggerPlacementAbility(s, placedSpecialPiece);
            }

            // Update move record with special piece info
            _record?.specialPiece = placedSpecialPiece;
          } else {
            // AI move without special piece specification - place normal piece
            // This should only happen if C++ engine decided normal piece is best
            placedSpecialPiece = null; // Normal piece

            // Log this for debugging
            logger.w(
                "[position] AI move without special piece info: placing normal piece at ${ExtMove.sqToNotation(s)}");
          }
        } else if (!isAIMove &&
            _selectedPieceForPlacement != null &&
            availablePieces.contains(_selectedPieceForPlacement)) {
          // Human selected a special piece
          placedSpecialPiece = _selectedPieceForPlacement;
          sqAttrList[s].specialPiece = placedSpecialPiece;
          _removeSpecialPieceFromAvailable(us, placedSpecialPiece!);

          // Trigger placement ability
          if (placedSpecialPiece != null) {
            _triggerPlacementAbility(s, placedSpecialPiece);
          }

          // Update move record with special piece info
          _record?.specialPiece = placedSpecialPiece;
        }
        // Normal piece placement (human chose normal or no special pieces available)
        // No notification needed for piece placement in Zhuolu mode

        // Clear human selection after placement
        if (!isAIMove) {
          _selectedPieceForPlacement = null;
        }
      }

      // Build move record for placing moves (including Zhuolu Chess special pieces)
      {
        String moveNotation;
        if (DB().ruleSettings.zhuoluMode && placedSpecialPiece != null) {
          final String pieceChar =
              _specialPieceToChar(placedSpecialPiece, sideToMove);
          moveNotation = "$pieceChar${ExtMove.sqToNotation(s)}";
        } else {
          // Standard coordinate placement
          moveNotation = ExtMove.sqToNotation(s);
        }

        _record = ExtMove(
          moveNotation,
          side: sideToMove,
          boardLayout: generateBoardLayoutAfterThisMove(),
          moveIndex: _gamePly,
          roundIndex: _roundNumber,
          specialPiece: placedSpecialPiece,
        );
      }

      final int n = _millsCount(s);

      if (n == 0) {
        // If no Mill

        if (pieceToRemoveCount[PieceColor.white]! != 0 ||
            pieceToRemoveCount[PieceColor.black]! != 0) {
          logger.e("[position] putPiece: pieceToRemoveCount is not 0.");
          return false;
        }

        _lastMillToSquare[sideToMove] = 0;
        _lastMillToSquare[sideToMove] = 0;

        GameController().gameInstance.focusIndex = squareToIndex[s];
        SoundManager().playTone(Sound.place);

        if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
          if (pieceInHandCount[PieceColor.white]! == 0 &&
              pieceInHandCount[PieceColor.black]! == 0) {
            if (!handlePlacingPhaseEnd()) {
              changeSideToMove();
            }

            // Check if Stalemate and change side to move if needed
            if (_checkIfGameIsOver()) {
              return true;
            }
            return true;
          }
        }

        // Begin of set side to move

        // Check if board is full during the placing phase
        if (_checkAndHandleBoardFull()) {
          return true;
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
        int rm = 0;

        if (DB().ruleSettings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
          rm = pieceToRemoveCount[sideToMove] = 0;
        } else {
          rm = pieceToRemoveCount[sideToMove] =
              DB().ruleSettings.mayRemoveMultiple ? n : 1;
          _updateKeyMisc();
        }

        GameController().gameInstance.focusIndex = squareToIndex[s];
        SoundManager().playTone(Sound.mill);

        // Trigger special piece mill ability for Zhuolu Chess
        if (placedSpecialPiece != null) {
          _triggerMillAbility(placedSpecialPiece);
        }

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

          // Check if board is full after mill formation
          if (_checkAndHandleBoardFull()) {
            return true;
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
          if (DB().ruleSettings.millFormationActionInPlacingPhase ==
              MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
            if (pieceInHandCount[PieceColor.white]! == 0 &&
                pieceInHandCount[PieceColor.black]! == 0) {
              // Check if board is full after mill formation (when all pieces placed)
              if (_checkAndHandleBoardFull()) {
                return true;
              }

              if (!handlePlacingPhaseEnd()) {
                changeSideToMove();
              }

              // Check if Stalemate and change side to move if needed
              if (_checkIfGameIsOver()) {
                return true;
              }
              return true;
            } else {
              // Check if board is full even when not all pieces are placed
              if (_checkAndHandleBoardFull()) {
                return true;
              }
              changeSideToMove();
            }
          } else {
            action = Act.remove;
          }
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
    if (_board[s] != PieceColor.none) {
      return false;
    }

    if (_checkIfGameIsOver()) {
      return true;
    }

    // If illegal
    if (pieceOnBoardCount[sideToMove]! > DB().ruleSettings.flyPieceCount ||
        !DB().ruleSettings.mayFly ||
        pieceInHandCount[sideToMove]! > 0) {
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

    // Include boardLayout
    _record = ExtMove(
      (() {
        // If moving a special piece in Zhuolu, encode as "Y-a1"
        if (DB().ruleSettings.zhuoluMode) {
          final SpecialPiece? movingSpecial =
              getSpecialPieceAt(_currentSquare[sideToMove]!);
          if (movingSpecial != null) {
            final String pieceChar =
                _specialPieceToChar(movingSpecial, sideToMove);
            return "$pieceChar-${ExtMove.sqToNotation(s)}";
          }
        }
        return "${ExtMove.sqToNotation(_currentSquare[sideToMove]!)}-${ExtMove.sqToNotation(s)}";
      })(),
      side: sideToMove,
      boardLayout: generateBoardLayoutAfterThisMove(),
      moveIndex: _gamePly,
      roundIndex: _roundNumber,
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
      _currentSquare[sideToMove] = 0;
      _lastMillFromSquare[sideToMove] = _lastMillToSquare[sideToMove] = 0;
      changeSideToMove();

      if (_checkIfGameIsOver()) {
        return true;
      }

      GameController().gameInstance.focusIndex = squareToIndex[s];

      SoundManager().playTone(Sound.place);
    } else {
      // If forming mill during Moving phase
      if (DB().ruleSettings.restrictRepeatedMillsFormation) {
        final int m =
            _potentialMillsCount(_currentSquare[sideToMove]!, sideToMove);
        if (_currentSquare[sideToMove] == _lastMillToSquare[sideToMove] &&
            s == _lastMillFromSquare[sideToMove] &&
            m > 0) {
          return false;
        }

        if (m > 0) {
          _lastMillFromSquare[sideToMove] = _currentSquare[sideToMove]!;
          _lastMillToSquare[sideToMove] = s;
        } else {
          _lastMillFromSquare[sideToMove] = 0;
          _lastMillToSquare[sideToMove] = 0;
        }
      }

      _currentSquare[sideToMove] = 0;

      pieceToRemoveCount[sideToMove] =
          DB().ruleSettings.mayRemoveMultiple ? n : 1;
      _updateKeyMisc();
      action = Act.remove;

      // Trigger special piece mill ability for Zhuolu Chess in moving phase
      if (DB().ruleSettings.zhuoluMode) {
        final SpecialPiece? movedSpecialType = getSpecialPieceAt(s);
        if (movedSpecialType != null) {
          _triggerMillAbility(movedSpecialType);
        }
      }

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

    if (pieceToRemoveCount[sideToMove]! == 0) {
      return const NoPieceToRemove();
    } else if (pieceToRemoveCount[sideToMove]! > 0) {
      if (!(sideToMove.opponent == _board[s])) {
        return const CanNotRemoveSelf();
      }
    } else {
      if (!(sideToMove == _board[s])) {
        return const ShouldRemoveSelf();
      }
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

    // Check special piece protection for Zhuolu Chess
    if (DB().ruleSettings.zhuoluMode) {
      if (!_canRemoveSpecialPiece(s)) {
        // TODO: Add specific error message for protected special pieces
        return const CanNotRemoveMill(); // Reusing existing error for now
      }
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

    // If removing a special piece in Zhuolu, encode as "xY"; otherwise use coordinate
    if (DB().ruleSettings.zhuoluMode) {
      final SpecialPiece? removedSpecial = getSpecialPieceAt(s);
      if (removedSpecial != null) {
        final String pieceChar =
            _specialPieceToChar(removedSpecial, sideToMove.opponent);
        _record = ExtMove.fromZhuoluNotation(
          "x$pieceChar",
          side: sideToMove,
          boardLayout: generateBoardLayoutAfterThisMove(),
          moveIndex: _gamePly,
          roundIndex: _roundNumber,
        );
      } else {
        _record = ExtMove(
          "x${ExtMove.sqToNotation(s)}",
          side: sideToMove,
          boardLayout: generateBoardLayoutAfterThisMove(),
          moveIndex: _gamePly,
          roundIndex: _roundNumber,
        );
      }
    } else {
      _record = ExtMove(
        "x${ExtMove.sqToNotation(s)}",
        side: sideToMove,
        boardLayout: generateBoardLayoutAfterThisMove(),
        moveIndex: _gamePly,
        roundIndex: _roundNumber,
      );
    }
    st.rule50 = 0; // TODO: Need to move out?

    if (pieceOnBoardCount[_them] != null) {
      pieceOnBoardCount[_them] = pieceOnBoardCount[_them]! - 1;
    }

    if (pieceOnBoardCount[_them]! + pieceInHandCount[_them]! <
        DB().ruleSettings.piecesAtLeastCount) {
      setGameOver(sideToMove, GameOverReason.loseFewerThanThree);
      SoundManager().playTone(Sound.remove);
      return const GameResponseOK();
    }

    _currentSquare[sideToMove] = 0;

    if (pieceToRemoveCount[sideToMove]! > 0) {
      pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! - 1;
    } else {
      pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! + 1;
    }

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
      return const NoPieceSelected();
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
        pieceToRemoveCount[PieceColor.white]!.abs() > 0 ||
        pieceToRemoveCount[PieceColor.black]!.abs() > 0) {
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
    } else if (DB().ruleSettings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.removalBasedOnMillCounts) {
      _calculateRemovalBasedOnMillCounts();
    } else if (invariant) {
      if (DB().ruleSettings.isDefenderMoveFirst == true) {
        setSideToMove(PieceColor.black);
        return true;
      } else {
        // Ignore
        return false;
      }
    }

    // Check if game should end after placing phase (Zhuolu Chess rule)
    if (DB().ruleSettings.zhuoluMode) {
      // Calculate captured pieces to determine winner
      final int initialPieces = DB().ruleSettings.piecesCount;
      final int whiteRemaining = pieceOnBoardCount[PieceColor.white]! +
          pieceInHandCount[PieceColor.white]!;
      final int blackRemaining = pieceOnBoardCount[PieceColor.black]! +
          pieceInHandCount[PieceColor.black]!;
      final int whiteCaptured = initialPieces - whiteRemaining;
      final int blackCaptured = initialPieces - blackRemaining;

      if (whiteCaptured > blackCaptured) {
        // White lost more pieces, Black wins
        setGameOver(PieceColor.black, GameOverReason.loseFewerThanThree);
      } else if (blackCaptured > whiteCaptured) {
        // Black lost more pieces, White wins
        setGameOver(PieceColor.white, GameOverReason.loseFewerThanThree);
      } else {
        // Equal captures, draw
        setGameOver(PieceColor.draw, GameOverReason.drawFullBoard);
      }
      return true;
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

    setGameOver(loser.opponent, GameOverReason.loseResign);

    return true;
  }

  void setGameOver(PieceColor w, GameOverReason reason) {
    phase = Phase.gameOver;
    gameOverReason = reason;
    winner = w;

    logger.i("[position] Game over, $w win, because of $reason");
    _updateScore();

    GameController().gameInstance.focusIndex = null;
    GameController().gameInstance.blurIndex = null;
    GameController().gameInstance.removeIndex = null;
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
      setGameOver(sideToMove.opponent, GameOverReason.loseFewerThanThree);
      return true;
    }

    if (DB().ruleSettings.nMoveRule > 0 &&
        posKeyHistory.length >= DB().ruleSettings.nMoveRule) {
      setGameOver(PieceColor.draw, GameOverReason.drawFiftyMove);
      return true;
    }

    if (DB().ruleSettings.endgameNMoveRule < DB().ruleSettings.nMoveRule &&
        _isThreeEndgame &&
        posKeyHistory.length >= DB().ruleSettings.endgameNMoveRule) {
      setGameOver(PieceColor.draw, GameOverReason.drawEndgameFiftyMove);
      return true;
    }

    // Stalemate.
    if (phase == Phase.moving &&
        action == Act.select &&
        _isAllSurrounded(sideToMove)) {
      switch (DB().ruleSettings.stalemateAction) {
        case StalemateAction.endWithStalemateLoss:
          setGameOver(sideToMove.opponent, GameOverReason.loseNoLegalMoves);
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
          setGameOver(PieceColor.draw, GameOverReason.drawStalemateCondition);
          return true;
        case null:
          logger.e("[position] _checkIfGameIsOver: Invalid StalemateAction.");
          break;
      }
    }

    if (pieceToRemoveCount[sideToMove]! > 0 ||
        pieceToRemoveCount[sideToMove]! < 0) {
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

  void _calculateRemovalBasedOnMillCounts() {
    final int whiteMills = totalMillsCount(PieceColor.white);
    final int blackMills = totalMillsCount(PieceColor.black);

    int whiteRemove = 1;
    int blackRemove = 1;

    if (whiteMills == 0 && blackMills == 0) {
      whiteRemove = -1;
      blackRemove = -1;
    } else if (whiteMills > 0 && blackMills == 0) {
      whiteRemove = 2;
      blackRemove = 1;
    } else if (blackMills > 0 && whiteMills == 0) {
      whiteRemove = 1;
      blackRemove = 2;
    } else {
      if (whiteMills == blackMills) {
        whiteRemove = whiteMills;
        blackRemove = blackMills;
      } else {
        if (whiteMills > blackMills) {
          blackRemove = blackMills;
          whiteRemove = blackRemove + 1;
        } else if (whiteMills < blackMills) {
          whiteRemove = whiteMills;
          blackRemove = whiteRemove + 1;
        } else {
          assert(false);
        }
      }
    }

    pieceToRemoveCount[PieceColor.white] = whiteRemove;
    pieceToRemoveCount[PieceColor.black] = blackRemove;

    // TODO: Bits count is not enough
    _updateKeyMisc();
  }

  void setSideToMove(PieceColor c) {
    final PieceColor oldSide = _sideToMove;

    if (sideToMove != c) {
      sideToMove = c;
      // us = c;

      // If we just switched from Black -> White, that means a new round:
      if (oldSide == PieceColor.black && c == PieceColor.white) {
        _roundNumber++;
      }

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

    if (pieceToRemoveCount[sideToMove]! > 0 ||
        pieceToRemoveCount[sideToMove]! < 0) {
      action = Act.remove;
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
    // TODO: If pieceToRemoveCount[sideToMove]! <= 3,
    //  the top 2 bits can store its value correctly;
    //  if it is greater than 3, since only 2 bits are left,
    //  the storage will be truncated or directly get 0,
    //  and the original value cannot be completely retained.
    st.key |= pieceToRemoveCount[sideToMove]! << (32 - _Zobrist.keyMiscBit);
  }

  ///////////////////////////////////////////////////////////////////////////////

  int _potentialMillsCount(int to, PieceColor c, {int from = 0}) {
    int n = 0;
    PieceColor locbak = PieceColor.none;
    PieceColor color = c;

    assert(0 <= from && from < sqEnd);

    if (c == PieceColor.nobody) {
      color = _board[to];
    }

    if (from != 0 && from >= sqBegin && from < sqEnd) {
      locbak = _board[from];
      _board[from] = _grid[squareToIndex[from]!] = PieceColor.none;
    }

    if (DB().ruleSettings.oneTimeUseMill) {
      for (int ld = 0; ld < lineDirectionNumber; ld++) {
        final List<int> mill = <int>[
          _millTable[to][ld][0],
          _millTable[to][ld][1],
          to
        ];

        if (color == _board[mill[0]] && color == _board[mill[1]]) {
          if (c == PieceColor.nobody) {
            n++;
          } else {
            final int millBB =
                squareBb(mill[0]) | squareBb(mill[1]) | squareBb(mill[2]);
            if (!(millBB & _formedMillsBB[color]! == millBB)) {
              n++;
            }
          }
        }
      }
    } else {
      for (int ld = 0; ld < lineDirectionNumber; ld++) {
        if (color == _board[_millTable[to][ld][0]] &&
            color == _board[_millTable[to][ld][1]]) {
          n++;
        }
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
    final PieceColor m = _board[s];

    for (int i = 0; i < lineDirectionNumber; i++) {
      final List<int> mill = <int>[_millTable[s][i][0], _millTable[s][i][1], s];
      mill.sort();

      if (m == _board[mill[0]] &&
          m == _board[mill[1]] &&
          m == _board[mill[2]]) {
        final int millBB =
            squareBb(mill[0]) | squareBb(mill[1]) | squareBb(mill[2]);
        if (!DB().ruleSettings.oneTimeUseMill ||
            !(millBB & _formedMillsBB[m]! == millBB)) {
          _formedMillsBB[m] = _formedMillsBB[m]! | millBB;
          _formedMills[m]?.add(mill);
          n++;
        }
      }
    }

    return n;
  }

  // Helper function to check if two lists are equal
  bool listEquals(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) {
      return false;
    }
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) {
        return false;
      }
    }
    return true;
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

  void setFormedMillsBB(int millsBitmask) {
    final int whiteMills = (millsBitmask >> 32) & 0xFFFFFFFF;
    final int blackMills = millsBitmask & 0xFFFFFFFF;

    _formedMillsBB[PieceColor.white] = whiteMills;
    _formedMillsBB[PieceColor.black] = blackMills;
  }

  @visibleForTesting
  String? get movesSinceLastRemove {
    if (!_isGameControllerInitialized()) {
      return null;
    }
    final GameRecorder recorder = GameController().gameRecorder;

    // Build the move list up to (and including) the activeNode, not beyond it.
    final List<ExtMove> pathMoves = <ExtMove>[];
    PgnNode<ExtMove>? cur = recorder.activeNode;
    while (cur != null && cur.parent != null) {
      if (cur.data != null) {
        pathMoves.add(cur.data!);
      }
      cur = cur.parent;
    }
    if (pathMoves.isEmpty) {
      return null;
    }

    // Reverse to go from root -> activeNode
    final List<ExtMove> moves = pathMoves.reversed.toList();

    // 1) Start from the end of the truncated list
    int idx = moves.length - 1;

    // 2) Go backwards until the last remove (starts with 'x')
    while (idx >= 0 && !moves[idx].move.startsWith('x')) {
      idx--;
    }

    // 3) Collect everything after that remove
    idx++;

    final StringBuffer buffer = StringBuffer();
    for (int i = idx; i < moves.length; i++) {
      // Skip special piece selection records - they are already encoded in FEN
      if (moves[i].move.contains("Special Pieces")) {
        continue;
      }
      buffer.writeSpace(moves[i].move);
    }

    final String result = buffer.toString();
    return result.isEmpty ? null : result;
  }

  // ----------------------------------------------------------------------------------------
  // Dynamic board layout string in ExtMove
  // ----------------------------------------------------------------------------------------

  /// generateBoardLayoutAfterThisMove returns a 3-rings layout string,
  /// each ring has 8 positions, representing the outer/middle/inner ring.
  /// For example: "OO***@**/@@**O@*@/O@O*@*O*"
  /// 'O' means White, '@' means Black, '*' means None or empty.
  /// For Zhuolu Chess, special pieces are represented by their assigned letters.
  String generateBoardLayoutAfterThisMove() {
    // Helper to map PieceColor to a char, considering special pieces
    String pieceChar(PieceColor c, int square) {
      if (c == PieceColor.none) {
        return '*';
      }
      if (c == PieceColor.marked) {
        return 'X';
      }

      // For Zhuolu Chess, check if this square has a special piece
      if (DB().ruleSettings.zhuoluMode) {
        final SpecialPiece? specialType = getSpecialPieceAt(square);
        if (specialType != null) {
          return _specialPieceToChar(specialType, c);
        }
      }

      // Normal pieces
      if (c == PieceColor.white) {
        return 'O';
      }
      if (c == PieceColor.black) {
        return '@';
      }
      return '*';
    }

    // We know squares 8..15 = outer ring, 16..23 = middle ring, 24..31 = inner ring
    String ringToString(int startIndex) {
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < 8; i++) {
        final int square = startIndex + i;
        final PieceColor p = _board[square];
        sb.write(pieceChar(p, square));
      }
      return sb.toString();
    }

    final String outer = ringToString(8);
    final String middle = ringToString(16);
    final String inner = ringToString(24);

    return "$outer/$middle/$inner";
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
    _lastMillFromSquare[PieceColor.white] =
        _lastMillFromSquare[PieceColor.black] = 0;
    _lastMillToSquare[PieceColor.white] =
        _lastMillToSquare[PieceColor.black] = 0;
    _formedMillsBB[PieceColor.white] = _formedMillsBB[PieceColor.black] = 0;
    _formedMills[PieceColor.white] = <List<int>>[];
    _formedMills[PieceColor.black] = <List<int>>[];

    _gamePly = 0;

    pieceOnBoardCount[PieceColor.white] = 0;
    pieceOnBoardCount[PieceColor.black] = 0;

    pieceInHandCount[PieceColor.white] = DB().ruleSettings.piecesCount;
    pieceInHandCount[PieceColor.black] = DB().ruleSettings.piecesCount;

    pieceToRemoveCount[PieceColor.white] = 0;
    pieceToRemoveCount[PieceColor.black] = 0;

    // Reset special piece selections for Zhuolu Chess (do not auto-initialize)
    if (DB().ruleSettings.zhuoluMode) {
      _specialPieceSelectionMask = 0; // Clear selections, wait for user choice
      _availableSpecialPiecesMask[PieceColor.white] = 0;
      _availableSpecialPiecesMask[PieceColor.black] = 0;
      _zhuoluCaptureStats = null;
    }

    isNeedStalemateRemoval = false;
    isStalemateRemoving = false;

    placedPieceNumber = 0;
    selectedPieceNumber = 0;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = 0;
      sqAttrList[i].specialPiece = null;
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

    posKeyHistory.clear();
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
    _lastMillFromSquare = pos._lastMillFromSquare;
    _lastMillToSquare = pos._lastMillToSquare;
    _formedMillsBB = pos._formedMillsBB;
    _formedMills = pos._formedMills;

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

    isNeedStalemateRemoval = pos.isNeedStalemateRemoval;
    isStalemateRemoving = pos.isStalemateRemoving;

    placedPieceNumber = pos.placedPieceNumber;
    selectedPieceNumber = pos.selectedPieceNumber;
    for (int i = 0; i < sqNumber; i++) {
      sqAttrList[i].placedPieceNumber = pos.sqAttrList[i].placedPieceNumber;
      sqAttrList[i].specialPiece = pos.sqAttrList[i].specialPiece;
    }

    // Copy special piece data
    _specialPieceSelectionMask = pos._specialPieceSelectionMask;
    _availableSpecialPiecesMask[PieceColor.white] =
        pos._availableSpecialPiecesMask[PieceColor.white] ?? 0;
    _availableSpecialPiecesMask[PieceColor.black] =
        pos._availableSpecialPiecesMask[PieceColor.black] ?? 0;

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

  bool putPieceForSetupPosition(int s) {
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

    // Handle special piece placement for Zhuolu Chess setup
    if (DB().ruleSettings.zhuoluMode &&
        GameController().setupPositionToolbarState != null) {
      final dynamic toolbarState = GameController().setupPositionToolbarState;
      final SpecialPiece? selectedSpecialPiece =
          toolbarState?.selectedSpecialPiece as SpecialPiece?;
      if (selectedSpecialPiece != null) {
        sqAttrList[s].specialPiece = selectedSpecialPiece;
      }
    }

    //GameController().gameInstance.focusIndex = squareToIndex[s];
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

  /// Set special piece selections for both players
  void setSpecialPieceSelections({
    required List<SpecialPiece> whiteSelection,
    required List<SpecialPiece> blackSelection,
  }) {
    // Generate bitmask from selections
    int mask = 0;

    // Encode white player's selection (bits 0-23)
    for (int i = 0; i < 6 && i < whiteSelection.length; i++) {
      final int pieceIndex = whiteSelection[i].index;
      mask |= pieceIndex << (i * 4);
    }

    // Encode black player's selection (bits 24-47)
    for (int i = 0; i < 6 && i < blackSelection.length; i++) {
      final int pieceIndex = blackSelection[i].index;
      mask |= pieceIndex << (24 + i * 4);
    }

    setSpecialPieceSelectionMask(mask);
    _updateAvailablePiecesFromMask();

    // Record special piece selections in move history for Zhuolu Chess
    _recordSpecialPieceSelections(whiteSelection, blackSelection);
  }

  /// Record the special piece selections at the start of Zhuolu Chess game
  void _recordSpecialPieceSelections(
    List<SpecialPiece> whiteSelection,
    List<SpecialPiece> blackSelection,
  ) {
    // Avoid circular dependency during GameController initialization
    // Check if GameController is already initialized to prevent infinite recursion
    if (!_isGameControllerInitialized()) {
      return;
    }

    // Create a special record for white's selection
    final ExtMove whiteSelectionRecord = ExtMove(
      'White Special Pieces',
      side: PieceColor.white,
      moveIndex: 0,
      roundIndex: 0,
      comments: <String>[
        'Selected: ${whiteSelection.map((SpecialPiece p) => '${p.chineseName}(${p.englishName})').join(', ')}'
      ],
    );

    // Create a special record for black's selection
    final ExtMove blackSelectionRecord = ExtMove(
      'Black Special Pieces',
      side: PieceColor.black,
      moveIndex: 0,
      roundIndex: 0,
      comments: <String>[
        'Selected: ${blackSelection.map((SpecialPiece p) => '${p.chineseName}(${p.englishName})').join(', ')}'
      ],
    );

    // Add to game recorder
    GameController().gameRecorder.appendMove(whiteSelectionRecord);
    GameController().gameRecorder.appendMove(blackSelectionRecord);
  }

  /// Check if GameController is already initialized to avoid circular dependency
  bool _isGameControllerInitialized() {
    try {
      // Check if game logic is initialized to avoid circular dependency
      return GameController.instance.gameLogicInitialized;
    } catch (e) {
      // If there's any error accessing the instance, assume it's not initialized
      return false;
    }
  }

  /// Check if special piece selections are complete
  bool get hasCompleteSpecialPieceSelections {
    if (!DB().ruleSettings.zhuoluMode) {
      return true;
    }
    return _specialPieceSelectionMask != 0;
  }

  /// Get the current special piece selection (converted from bitmask)
  SpecialPieceSelection? get specialPieceSelection {
    if (_specialPieceSelectionMask == 0) {
      return null;
    }

    final List<SpecialPiece> whiteSelection = <SpecialPiece>[];
    final List<SpecialPiece> blackSelection = <SpecialPiece>[];

    // Extract white selection (bits 0-23)
    for (int i = 0; i < 6; i++) {
      final int pieceIndex = (_specialPieceSelectionMask >> (i * 4)) & 0xF;
      if (pieceIndex < 15) {
        whiteSelection.add(SpecialPiece.values[pieceIndex]);
      }
    }

    // Extract black selection (bits 24-47)
    for (int i = 0; i < 6; i++) {
      final int pieceIndex = (_specialPieceSelectionMask >> (24 + i * 4)) & 0xF;
      if (pieceIndex < 15) {
        blackSelection.add(SpecialPiece.values[pieceIndex]);
      }
    }

    return SpecialPieceSelection(
      whiteSelection: whiteSelection,
      blackSelection: blackSelection,
      isRevealed: true,
    );
  }

  /// Check if a square has a special piece
  SpecialPiece? getSpecialPieceAt(int square) {
    return sqAttrList[square].specialPiece;
  }

  /// Find the square where a specific special piece of a given color is located
  int _findSpecialPieceSquare(SpecialPiece piece, PieceColor color) {
    for (int square = sqBegin; square < sqEnd; square++) {
      if (_board[square] == color && getSpecialPieceAt(square) == piece) {
        return square;
      }
    }
    return -1; // Not found
  }

  /// Get available special pieces for a player
  List<SpecialPiece> getAvailableSpecialPieces(PieceColor player) {
    final int mask = _availableSpecialPiecesMask[player] ?? 0;
    final List<SpecialPiece> pieces = <SpecialPiece>[];

    for (int i = 0; i < 15; i++) {
      if ((mask & (1 << i)) != 0) {
        pieces.add(SpecialPiece.values[i]);
      }
    }

    return pieces;
  }

  /// Set the selected piece type for next placement
  set selectedPieceForPlacement(SpecialPiece? piece) {
    _selectedPieceForPlacement = piece;
  }

  /// Get the currently selected piece for placement
  SpecialPiece? get selectedPieceForPlacement => _selectedPieceForPlacement;

  /// Set special piece selections using bitmask
  void setSpecialPieceSelectionMask(int mask) {
    _specialPieceSelectionMask = mask;
    _updateAvailablePiecesFromMask();
  }

  /// Get special piece selections as bitmask
  int get specialPieceSelectionMask => _specialPieceSelectionMask;

  /// Update available pieces from the selection mask
  void _updateAvailablePiecesFromMask() {
    for (final PieceColor player in <PieceColor>[
      PieceColor.white,
      PieceColor.black
    ]) {
      final int startBit = player == PieceColor.white ? 0 : 24;
      int mask = 0;

      // Extract 6 pieces (4 bits each) for this player and mark as available
      for (int i = 0; i < 6; i++) {
        final int pieceIndex =
            (_specialPieceSelectionMask >> (startBit + i * 4)) & 0xF;
        if (pieceIndex < 15) {
          // Valid special piece index - mark as available
          mask |= 1 << pieceIndex;
        }
      }

      _availableSpecialPiecesMask[player] = mask;
    }
  }

  /// Remove a special piece from available pieces
  void _removeSpecialPieceFromAvailable(PieceColor player, SpecialPiece piece) {
    final int pieceIndex = piece.index;
    _availableSpecialPiecesMask[player] =
        _availableSpecialPiecesMask[player]! & ~(1 << pieceIndex);
  }

  /// Reveal special piece selections to both players
  void revealSpecialPieceSelections() {
    // Special piece selections are automatically revealed when set via bitmask
  }

  /// Check if a piece can be placed on a specific square (considering special piece rules)
  bool _canPlaceSpecialPieceAt(int square, SpecialPiece? specialPiece) {
    if (specialPiece == null) {
      return true;
    }

    final PieceColor squareState = _board[square];

    switch (specialPiece) {
      case SpecialPiece.gongGong:
        // Can ONLY be placed on abandoned squares
        return squareState == PieceColor.marked;
      case SpecialPiece.fengHou:
        // Can be placed on abandoned squares (in addition to normal squares)
        return squareState == PieceColor.none ||
            squareState == PieceColor.marked;
      case SpecialPiece.huangDi:
      case SpecialPiece.nuBa:
      case SpecialPiece.yanDi:
      case SpecialPiece.chiYou:
      case SpecialPiece.changXian:
      case SpecialPiece.xingTian:
      case SpecialPiece.zhuRong:
      case SpecialPiece.yuShi:
      case SpecialPiece.nuWa:
      case SpecialPiece.fuXi:
      case SpecialPiece.kuaFu:
      case SpecialPiece.yingLong:
      case SpecialPiece.fengBo:
        // Normal placement rules apply
        return squareState == PieceColor.none;
    }
  }

  /// Check if a piece can be removed (considering special piece protection)
  bool _canRemoveSpecialPiece(int square) {
    final SpecialPiece? specialPiece = getSpecialPieceAt(square);
    if (specialPiece == null) {
      return true;
    }

    switch (specialPiece) {
      case SpecialPiece.kuaFu:
        // Cannot be removed by opponent
        return false;
      case SpecialPiece.yingLong:
        // Cannot be removed when adjacent to own pieces
        return !_hasAdjacentOwnPieces(square);
      case SpecialPiece.huangDi:
      case SpecialPiece.nuBa:
      case SpecialPiece.yanDi:
      case SpecialPiece.chiYou:
      case SpecialPiece.changXian:
      case SpecialPiece.xingTian:
      case SpecialPiece.zhuRong:
      case SpecialPiece.yuShi:
      case SpecialPiece.fengHou:
      case SpecialPiece.gongGong:
      case SpecialPiece.nuWa:
      case SpecialPiece.fuXi:
      case SpecialPiece.fengBo:
        return true;
    }
  }

  /// Check if a square has adjacent pieces of the same color
  bool _hasAdjacentOwnPieces(int square) {
    final PieceColor pieceColor = _board[square];
    final List<int> adjacent = _getAdjacentSquares(square);

    for (final int adjSquare in adjacent) {
      if (_board[adjSquare] == pieceColor) {
        return true;
      }
    }
    return false;
  }

  /// Get all adjacent squares to a given square
  List<int> _getAdjacentSquares(int square) {
    final List<int> adjacent = <int>[];

    // Use the existing adjacency logic from Mills
    for (int d = 0; d < 4; d++) {
      final int adjSquare = Position._adjacentSquares[square][d];
      if (adjSquare != 0) {
        adjacent.add(adjSquare);
      }
    }

    return adjacent;
  }

  /// Trigger special piece ability when placing
  void _triggerPlacementAbility(int square, SpecialPiece specialPiece) {
    final PieceColor player = sideToMove;
    final PieceColor opponent = player.opponent;
    final List<int> adjacent = _getAdjacentSquares(square);

    switch (specialPiece) {
      case SpecialPiece.huangDi:
        // Convert all adjacent opponent pieces to own pieces
        for (final int adjSquare in adjacent) {
          if (_board[adjSquare] == opponent) {
            _board[adjSquare] = player;
            _grid[squareToIndex[adjSquare]!] = player;
          }
        }
        break;

      case SpecialPiece.nuBa:
        // Can convert one adjacent opponent piece to own piece
        final List<int> opponentAdjacent =
            adjacent.where((int sq) => _board[sq] == opponent).toList();
        if (opponentAdjacent.isNotEmpty) {
          // For now, convert the first found adjacent opponent piece
          // TODO: Allow user to choose which piece to convert
          final int targetSquare = opponentAdjacent.first;
          _board[targetSquare] = player;
          _grid[squareToIndex[targetSquare]!] = player;
        }
        break;

      case SpecialPiece.yanDi:
        // Remove all adjacent opponent pieces
        for (final int adjSquare in adjacent) {
          if (_board[adjSquare] == opponent) {
            _removeOpponentPiece(adjSquare);
          }
        }
        break;

      case SpecialPiece.chiYou:
        // Convert all adjacent empty squares to abandoned squares
        for (final int adjSquare in adjacent) {
          if (_board[adjSquare] == PieceColor.none) {
            _board[adjSquare] = PieceColor.marked;
            _grid[squareToIndex[adjSquare]!] = PieceColor.marked;
          }
        }
        break;

      case SpecialPiece.changXian:
        // Can remove any opponent piece on the board
        // For now, remove the first found opponent piece
        for (int i = sqBegin; i < sqEnd; i++) {
          if (_board[i] == opponent) {
            _removeOpponentPiece(i);
            break;
          }
        }
        break;

      case SpecialPiece.xingTian:
        // Can remove one adjacent opponent piece
        for (final int adjSquare in adjacent) {
          if (_board[adjSquare] == opponent) {
            _removeOpponentPiece(adjSquare);
            break; // Only remove one piece
          }
        }
        break;

      case SpecialPiece.nuWa:
        // Convert all adjacent abandoned squares to own pieces
        for (final int adjSquare in adjacent) {
          if (_board[adjSquare] == PieceColor.marked) {
            _board[adjSquare] = player;
            _grid[squareToIndex[adjSquare]!] = player;
            pieceOnBoardCount[player] = pieceOnBoardCount[player]! + 1;
          }
        }
        break;

      case SpecialPiece.fuXi:
        // Can convert any abandoned square to own piece
        // For now, convert the first found abandoned square
        for (int i = sqBegin; i < sqEnd; i++) {
          if (_board[i] == PieceColor.marked) {
            _board[i] = player;
            _grid[squareToIndex[i]!] = player;
            pieceOnBoardCount[player] = pieceOnBoardCount[player]! + 1;
            break;
          }
        }
        break;

      case SpecialPiece.fengBo:
        // Destroy any opponent piece without leaving abandoned square
        for (int i = sqBegin; i < sqEnd; i++) {
          if (_board[i] == opponent) {
            _board[i] = PieceColor.none;
            _grid[squareToIndex[i]!] = PieceColor.none;
            pieceOnBoardCount[opponent] = pieceOnBoardCount[opponent]! - 1;
            break;
          }
        }
        break;
      case SpecialPiece.zhuRong:
      case SpecialPiece.yuShi:
      case SpecialPiece.fengHou:
      case SpecialPiece.gongGong:
      case SpecialPiece.kuaFu:
      case SpecialPiece.yingLong:
        // No special placement ability
        break;
    }
  }

  /// Trigger special piece ability when forming mill
  void _triggerMillAbility(SpecialPiece specialPiece) {
    final PieceColor player = sideToMove;
    final PieceColor opponent = player.opponent;

    switch (specialPiece) {
      case SpecialPiece.zhuRong:
        // Fire God Zhu Rong: When forming mill, can additionally remove any opponent piece
        // This increases the removal count by 1, allowing consecutive removals
        if (pieceOnBoardCount[opponent]! > 0) {
          pieceToRemoveCount[sideToMove] = pieceToRemoveCount[sideToMove]! + 1;
          _updateKeyMisc();
        }
        break;

      case SpecialPiece.yuShi:
        // Can convert any empty square to abandoned square
        for (int i = sqBegin; i < sqEnd; i++) {
          if (_board[i] == PieceColor.none) {
            _board[i] = PieceColor.marked;
            _grid[squareToIndex[i]!] = PieceColor.marked;
            break;
          }
        }
        break;
      case SpecialPiece.huangDi:
      case SpecialPiece.nuBa:
      case SpecialPiece.yanDi:
      case SpecialPiece.chiYou:
      case SpecialPiece.changXian:
      case SpecialPiece.xingTian:
      case SpecialPiece.fengHou:
      case SpecialPiece.gongGong:
      case SpecialPiece.nuWa:
      case SpecialPiece.fuXi:
      case SpecialPiece.kuaFu:
      case SpecialPiece.yingLong:
      case SpecialPiece.fengBo:
        // No special mill ability
        break;
    }
  }

  /// Helper method to remove an opponent piece
  void _removeOpponentPiece(int square) {
    final PieceColor opponent = _board[square];
    if (opponent != PieceColor.none && opponent != PieceColor.marked) {
      if (DB().ruleSettings.zhuoluMode) {
        _board[square] = PieceColor.marked;
        _grid[squareToIndex[square]!] = PieceColor.marked;
      } else {
        _board[square] = PieceColor.none;
        _grid[squareToIndex[square]!] = PieceColor.none;
      }
      pieceOnBoardCount[opponent] = pieceOnBoardCount[opponent]! - 1;
    }
  }

  /// AI algorithm to select the best piece type for placement
  /// DEPRECATED: This function should not be used anymore.
  /// All AI decisions should be made by the C++ search engine.
  SpecialPiece? _getAISelectedPiece(
      PieceColor player, int square, List<SpecialPiece> availablePieces) {
    // This function is deprecated and should not be called
    // All AI special piece selection should be handled by C++ search engine
    logger.e("[position] DEPRECATED: _getAISelectedPiece should not be called. "
        "AI decisions should come from C++ search engine.");

    // Return null to force normal piece placement
    return null;
  }

  /// Evaluate the value of placing a specific piece type at a square
  double _evaluatePiecePlacement(
      PieceColor player, int square, SpecialPiece? piece) {
    double score = 0.0;
    final PieceColor opponent = player.opponent;
    final List<int> adjacent = _getAdjacentSquares(square);

    if (piece == null) {
      // Normal piece - base score
      score = 10.0;

      // Bonus for potential mills
      if (_potentialMillsCount(square, player) > 0) {
        score += 20.0;
      }

      return score;
    }

    // Special piece evaluation
    switch (piece) {
      case SpecialPiece.huangDi:
        {
          // Convert all adjacent opponent pieces - valuable only with adjacency
          final int opponentAdjacent =
              adjacent.where((int sq) => _board[sq] == opponent).length;
          if (opponentAdjacent == 0) {
            score = 5.0; // Avoid wasting early when no target
          } else {
            score = 50.0 + opponentAdjacent * 30.0;
          }
          break;
        }

      case SpecialPiece.yanDi:
        {
          // Remove all adjacent opponent pieces - needs adjacency
          final int opponentToRemove =
              adjacent.where((int sq) => _board[sq] == opponent).length;
          if (opponentToRemove == 0) {
            score = 6.0;
          } else {
            score = 40.0 + opponentToRemove * 25.0;
          }
          break;
        }

      case SpecialPiece.changXian:
        {
          // Can remove any opponent piece - more valuable when opponent has few pieces
          final int totalOpponentPieces = pieceOnBoardCount[opponent]!;
          score = totalOpponentPieces <= 5 ? 60.0 : 30.0;
          break;
        }

      case SpecialPiece.kuaFu:
        // Cannot be removed - valuable in endgame
        final int totalPieces =
            pieceOnBoardCount[player]! + pieceOnBoardCount[opponent]!;
        score = totalPieces > 15 ? 15.0 : 40.0; // More valuable in endgame
        break;

      case SpecialPiece.fengHou:
      case SpecialPiece.gongGong:
        {
          // Synergy with abandoned squares; prefer when they exist
          final int markedSquares =
              _board.where((PieceColor p) => p == PieceColor.marked).length;
          if (markedSquares == 0) {
            score = 8.0;
          } else {
            // Small bonus per available marked square
            score = 20.0 + markedSquares * 6.0;
          }
          break;
        }

      case SpecialPiece.zhuRong:
      case SpecialPiece.yuShi:
        {
          // Mill-triggered abilities - valuable if likely to form mills
          final int millPotential = _potentialMillsCount(square, player);
          score = 25.0 + millPotential * 15.0;
          break;
        }

      case SpecialPiece.nuBa:
        {
          final int oppAdj =
              adjacent.where((int sq) => _board[sq] == opponent).length;
          score = oppAdj > 0 ? 28.0 + 18.0 : 7.0;
          // Positional support bonus
          score +=
              adjacent.where((int sq) => _board[sq] == player).length * 2.0;
          break;
        }
      case SpecialPiece.chiYou:
        {
          // ChiYou converts adjacent empty squares to MARKED squares
          // This is rarely beneficial early in the game
          final int emptyAdj =
              adjacent.where((int sq) => _board[sq] == PieceColor.none).length;
          if (emptyAdj == 0) {
            score = 2.0; // No empty squares to convert
          } else {
            // Very low base value - creating MARKED squares is rarely beneficial early
            score = 8.0 + 3.0 * emptyAdj;

            // Discourage early use
            final int totalPieces =
                pieceOnBoardCount[player]! + pieceOnBoardCount[opponent]!;
            if (totalPieces <= 6) {
              // Early game
              score -= 5.0;
            }

            // Only valuable if we have pieces that benefit from MARKED squares
            final List<SpecialPiece> available =
                getAvailableSpecialPieces(player);
            if (available.contains(SpecialPiece.fengHou) ||
                available.contains(SpecialPiece.gongGong) ||
                available.contains(SpecialPiece.nuWa)) {
              score += 10.0; // Synergy bonus
            }
          }
          break;
        }
      case SpecialPiece.xingTian:
        {
          final int oppAdj =
              adjacent.where((int sq) => _board[sq] == opponent).length;
          score = oppAdj > 0 ? 32.0 + 18.0 : 7.0;
          break;
        }
      case SpecialPiece.nuWa:
      case SpecialPiece.fuXi:
      case SpecialPiece.yingLong:
      case SpecialPiece.fengBo:
        // Default moderate scores with small positional bonus
        score = 25.0 + adjacent.length * 2.0;
        break;
    }

    // Add positional bonus
    score += _getPositionalBonus(square);

    return score;
  }

  /// Get positional bonus for a square (center squares are more valuable)
  double _getPositionalBonus(int square) {
    // Center squares (middle ring) are more valuable
    final List<int> centerSquares = <int>[9, 10, 11, 12, 13, 14, 15, 16];
    if (centerSquares.contains(square)) {
      return 5.0;
    }

    // Corner squares are less valuable
    final List<int> cornerSquares = <int>[8, 16, 24];
    if (cornerSquares.contains(square)) {
      return -2.0;
    }

    return 0.0;
  }
}
