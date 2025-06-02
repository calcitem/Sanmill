// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// types.dart

part of '../mill.dart';

int abs(int value) => value > 0 ? value : -value;

enum PieceColor { none, white, black, marked, nobody, draw }

Color getAverageColor(Color a, Color b) {
  return Color.fromARGB(
    (a.a + b.a) ~/ 2,
    (a.a + b.r) ~/ 2,
    (a.a + b.g) ~/ 2,
    (a.a + b.b) ~/ 2,
  );
}

Color getTranslucentColor(Color c, double opacity) {
  return c.withValues(alpha: opacity);
}

extension PieceColorExtension on PieceColor {
  String get string {
    switch (this) {
      case PieceColor.none:
        return "*";
      case PieceColor.white:
        return "O";
      case PieceColor.black:
        return "@";
      case PieceColor.marked:
        return "X";
      case PieceColor.nobody:
        return "-";
      case PieceColor.draw:
        return "=";
    }
  }

  String playerName(BuildContext context) {
    switch (this) {
      case PieceColor.white:
        return S.of(context).white;
      case PieceColor.black:
        return S.of(context).black;
      case PieceColor.none:
        return S.of(context).none;
      case PieceColor.draw:
        return S.of(context).draw;
      case PieceColor.marked:
      case PieceColor.nobody:
        throw UnimplementedError("Player has no name");
    }
  }

  String pieceName(BuildContext context) {
    switch (this) {
      case PieceColor.white:
        return S.of(context).whitePiece;
      case PieceColor.black:
        return S.of(context).blackPiece;
      case PieceColor.marked:
        return S.of(context).marked;
      case PieceColor.none:
        return S.of(context).emptyPoint;
      case PieceColor.nobody:
      case PieceColor.draw:
        throw UnimplementedError("No piece name available");
    }
  }

  PieceColor get opponent {
    switch (this) {
      case PieceColor.black:
        return PieceColor.white;
      case PieceColor.white:
        return PieceColor.black;
      case PieceColor.marked:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        return this;
    }
  }

  String? getWinString(BuildContext context) {
    switch (this) {
      case PieceColor.white:
        return S.of(context).whiteWin;
      case PieceColor.black:
        return S.of(context).blackWin;
      case PieceColor.draw:
        return S.of(context).isDraw;
      case PieceColor.nobody:
        return GameController().position.phase.getTip(context);
      case PieceColor.none:
      case PieceColor.marked:
        return null;
    }
  }

  GameResult? get result {
    final Game gameInstance = GameController().gameInstance;
    final Player currentPlayer = gameInstance.getPlayerByColor(this);

    final bool isAi = currentPlayer.isAi;

    switch (this) {
      case PieceColor.white:
        if (isAi == true) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.black:
        if (isAi == true) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.draw:
        return GameResult.draw;
      case PieceColor.marked:
      case PieceColor.none:
      case PieceColor.nobody:
        return null;
    }
  }

  IconData get icon {
    return GameController().position.phase == Phase.gameOver
        ? _arrow
        : _chevron;
  }

  IconData get _chevron {
    switch (this) {
      case PieceColor.white:
        return FluentIcons.chevron_left_24_regular;
      case PieceColor.black:
        return FluentIcons.chevron_right_24_regular;
      case PieceColor.marked:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        return FluentIcons.code_24_regular;
    }
  }

  IconData get _arrow {
    switch (GameController().position.winner) {
      case PieceColor.white:
        return FluentIcons.toggle_left_24_regular;
      case PieceColor.black:
        return FluentIcons.toggle_right_24_regular;
      case PieceColor.marked:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        return FluentIcons.handshake_24_regular;
    }
  }

  Color get mainColor {
    final ColorSettings colorSettings = DB().colorSettings;
    switch (this) {
      case PieceColor.white:
        return colorSettings.whitePieceColor;
      case PieceColor.black:
        return colorSettings.blackPieceColor;
      case PieceColor.marked:
        return getTranslucentColor(
            getAverageColor(
                colorSettings.whitePieceColor, colorSettings.blackPieceColor),
            0); // Fully transparent
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        throw Error();
    }
  }

  Color get borderColor {
    switch (this) {
      case PieceColor.white:
        return AppTheme.whitePieceBorderColor;
      case PieceColor.black:
        return AppTheme.blackPieceBorderColor;
      case PieceColor.marked:
        return getTranslucentColor(
            getAverageColor(
                AppTheme.whitePieceBorderColor, AppTheme.blackPieceBorderColor),
            0); // Fully transparent
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        throw Error();
    }
  }

  Color get blurPositionColor => mainColor.withValues(alpha: 0.1);
}

enum AiMoveType { unknown, traditional, perfect, consensus, openingBook }

enum Phase { ready, placing, moving, gameOver }

extension PhaseExtension on Phase {
  String get fen {
    switch (this) {
      case Phase.ready:
        return "r";
      case Phase.placing:
        return "p";
      case Phase.moving:
        return "m";
      case Phase.gameOver:
        return "o";
    }
  }

  String? getTip(BuildContext context) {
    switch (this) {
      case Phase.placing:
        if (DB().ruleSettings.mayMoveInPlacingPhase) {
          final String side =
              GameController().position.sideToMove.playerName(context);
          return S.of(context).tipToMove(side);
        } else {
          return S.of(context).tipPlace;
        }
      case Phase.moving:
        if (GameController()
                .position
                .pieceToRemoveCount[GameController().position.sideToMove]! !=
            0) {
          return S.of(context).tipRemove;
        }
        return S.of(context).tipMove;
      case Phase.ready:
      case Phase.gameOver:
        return null;
    }
  }

  String? getName(BuildContext context) {
    switch (this) {
      case Phase.placing:
        return S.of(context).placingPhase;
      case Phase.moving:
        return S.of(context).movingPhase;
      case Phase.ready:
        return null;
      case Phase.gameOver:
        return S.of(context).gameOver;
    }
  }
}

enum Act { select, place, remove }

extension ActExtension on Act {
  String get fen {
    switch (this) {
      case Act.place:
        return "p";
      case Act.select:
        return "s";
      case Act.remove:
        return "r";
    }
  }
}

// TODO: [Leptopoda] Throw this stuff to faster detect a game over
enum GameOverReason {
  loseFewerThanThree,
  loseNoLegalMoves,
  loseFullBoard,
  loseResign,
  loseTimeout,
  drawThreefoldRepetition,
  drawFiftyMove,
  drawEndgameFiftyMove,
  drawFullBoard,
  drawStalemateCondition,
}

extension GameOverReasonExtension on GameOverReason {
  String getName(BuildContext context, PieceColor winner) {
    final String loserStr = winner.opponent.playerName(context);

    switch (this) {
      case GameOverReason.loseFewerThanThree:
        return S.of(context).loseReasonlessThanThree(loserStr);
      case GameOverReason.loseResign:
        return S.of(context).loseReasonResign(loserStr);
      case GameOverReason.loseNoLegalMoves:
        return S.of(context).loseReasonNoWay(loserStr);
      case GameOverReason.loseFullBoard:
        return S.of(context).loseReasonBoardIsFull(loserStr);
      case GameOverReason.loseTimeout:
        return S.of(context).loseReasonTimeOver(loserStr);
      case GameOverReason.drawFiftyMove:
        return S.of(context).drawReasonRule50;
      case GameOverReason.drawEndgameFiftyMove:
        return S.of(context).drawReasonEndgameRule50;
      case GameOverReason.drawFullBoard:
        return S.of(context).drawReasonBoardIsFull;
      case GameOverReason.drawStalemateCondition:
        return S.of(context).endWithStalemateDraw; // TODO: Not drawReasonXXX
      case GameOverReason.drawThreefoldRepetition:
        return S.of(context).drawReasonThreefoldRepetition;
    }
  }
}

enum GameResult { win, lose, draw }

extension GameResultExtension on GameResult {
  String winString(BuildContext context) {
    switch (this) {
      case GameResult.win:
        return GameController().gameInstance.gameMode == GameMode.humanVsAi
            ? S.of(context).youWin
            : S.of(context).gameOver;
      case GameResult.lose:
        return S.of(context).gameOver;
      case GameResult.draw:
        return S.of(context).isDraw;
    }
  }

  String toNagString() {
    switch (this) {
      case GameResult.win:
        return "1-0";
      case GameResult.lose:
        return "0-1";
      case GameResult.draw:
        return "1/2-1/2";
    }
  }
}

const int valueUnique = 100;
const int valueEachPiece = 5;

const int sqBegin = 8;
const int sqEnd = 32;
const int sqNumber = 40;

const int moveDirectionBegin = 0;
const int moveDirectionNumber = 4;

const int lineDirectionNumber = 3;

const int fileNumber = 3;
const int fileExNumber = fileNumber + 2;

const int rankNumber = 8;

int makeSquare(int file, int rank) {
  // TODO: -2
  assert(file != -2 && rank != -2);

  if (file == 0 && rank == 0) {
    return 0;
  }
  if (file == -1 && rank == -1) {
    return -1;
  }

  return (file << 3) + rank - 1;
}

bool isOk(int sq) {
  final bool ret = sq == 0 || (sq >= sqBegin && sq < sqEnd);

  if (!ret) {
    logger.w("[types] $sq is not OK");
  }

  return ret; // TODO: SQ_NONE?
}

int fileOf(int sq) {
  return sq >> 3;
}

int rankOf(int sq) {
  return (sq & 0x07) + 1;
}

int fromSq(int move) {
  return abs(move) >> 8;
}

int toSq(int move) {
  return abs(move) & 0x00FF;
}

int makeMove(int from, int to) {
  return (from << 8) + to;
}

Map<int, int> squareToIndex = <int, int>{
  8: 17,
  9: 18,
  10: 25,
  11: 32,
  12: 31,
  13: 30,
  14: 23,
  15: 16,
  16: 10,
  17: 12,
  18: 26,
  19: 40,
  20: 38,
  21: 36,
  22: 22,
  23: 8,
  24: 3,
  25: 6,
  26: 27,
  27: 48,
  28: 45,
  29: 42,
  30: 21,
  31: 0
};

int notationToSquare(String notation) {
  const Map<String, int> notationToSquare = <String, int>{
    // inner ring (8-15)
    'd5': 8,
    'e5': 9,
    'e4': 10,
    'e3': 11,
    'd3': 12,
    'c3': 13,
    'c4': 14,
    'c5': 15,
    // middle ring (16-23)
    'd6': 16,
    'f6': 17,
    'f4': 18,
    'f2': 19,
    'd2': 20,
    'b2': 21,
    'b4': 22,
    'b6': 23,
    // outer ring (24-31)
    'd7': 24,
    'g7': 25,
    'g4': 26,
    'g1': 27,
    'd1': 28,
    'a1': 29,
    'a4': 30,
    'a7': 31,
  };

  final String key = notation.trim().toLowerCase();
  return notationToSquare[key] ?? -1;
}

Map<int, int> indexToSquare =
    squareToIndex.map((int k, int v) => MapEntry<int, int>(v, k));

/*
          a b c d e f g
        7 X --- X --- X 7
          |\    |    /|
        6 | X - X - X | 6
          | |\  |  /| |
        5 | | X-X-X | | 5
        4 X-X-X   X-X-X 4
        3 | | X-X-X | | 3
          | |/  |  \| |
        2 | X - X - X | 2
          |/    |    \|
        1 X --- X --- X 1
          a b c d e f g

PlayOK numbering (left to right, top to bottom):

   a7(1)  ---- d7(2)  ---- g7(3)
   |            |             |
   | b6(4)  - d6(5)  - f6(6)  |
   | |          |           | |
   | | c5(7) -d5(8) -e5(9)  | |
a4(10)-b4(11)-c4(12) e4(13)-f4(14)-g4(15)
   | | c3(16)-d3(17)-e3(18) | |
   | |          |           | |
   | b2(19) - d2(20) - f2(21) |
   |            |             |
   a1(22) ---- d1(23) ---- g1(24)
 */

// PlayOK notation to standard notation mapping
// PlayOK uses numbers 1-24 to represent board positions
// Numbering is from left to right, top to bottom
const Map<String, String> playOkNotationToStandardNotation = <String, String>{
  "1": "a7", // outer ring, top left
  "2": "d7", // outer ring, top center
  "3": "g7", // outer ring, top right
  "4": "b6", // middle ring, top left
  "5": "d6", // middle ring, top center
  "6": "f6", // middle ring, top right
  "7": "c5", // inner ring, top left
  "8": "d5", // inner ring, top center
  "9": "e5", // inner ring, top right
  "10": "a4", // left side, middle
  "11": "b4", // middle left
  "12": "c4", // inner left
  "13": "e4", // inner right
  "14": "f4", // middle right
  "15": "g4", // right side, middle
  "16": "c3", // inner ring, bottom left
  "17": "d3", // inner ring, bottom center
  "18": "e3", // inner ring, bottom right
  "19": "b2", // middle ring, bottom left
  "20": "d2", // middle ring, bottom center
  "21": "f2", // middle ring, bottom right
  "22": "a1", // outer ring, bottom left
  "23": "d1", // outer ring, bottom center
  "24": "g1", // outer ring, bottom right
};
