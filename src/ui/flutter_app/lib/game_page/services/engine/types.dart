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

int abs(int value) => value > 0 ? value : -value;

enum PieceColor { none, white, black, ban, nobody, draw }

Color getAverageColor(Color a, Color b) {
  return Color.fromARGB(
    (a.alpha + b.alpha) ~/ 2,
    (a.alpha + b.red) ~/ 2,
    (a.alpha + b.green) ~/ 2,
    (a.alpha + b.blue) ~/ 2,
  );
}

Color getTranslucentColor(Color c, double opacity) {
  return c.withOpacity(opacity);
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
      case PieceColor.ban:
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
      case PieceColor.ban:
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
      case PieceColor.ban:
        return S.of(context).banPoint;
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
      case PieceColor.ban:
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
      case PieceColor.ban:
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
      case PieceColor.ban:
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
      case PieceColor.ban:
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
      case PieceColor.ban:
      case PieceColor.draw:
      case PieceColor.none:
      case PieceColor.nobody:
        return FluentIcons.handshake_24_regular;
    }
  }

  Color get pieceColor {
    final ColorSettings colorSettings = DB().colorSettings;
    switch (this) {
      case PieceColor.white:
        return colorSettings.whitePieceColor;
      case PieceColor.black:
        return colorSettings.blackPieceColor;
      case PieceColor.ban:
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
      case PieceColor.ban:
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

  Color get blurPositionColor => pieceColor.withOpacity(0.1);
}

enum AiMoveType { unknown, traditional, perfect, consensus }

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
        return S.of(context).tipPlace;
      case Phase.moving:
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
 */

Map<String, String> wmdNotationToMove = <String, String>{
  "d5": "(1,1)",
  "e5": "(1,2)",
  "e4": "(1,3)",
  "e3": "(1,4)",
  "d3": "(1,5)",
  "c3": "(1,6)",
  "c4": "(1,7)",
  "c5": "(1,8)",
  "d6": "(2,1)",
  "f6": "(2,2)",
  "f4": "(2,3)",
  "f2": "(2,4)",
  "d2": "(2,5)",
  "b2": "(2,6)",
  "b4": "(2,7)",
  "b6": "(2,8)",
  "d7": "(3,1)",
  "g7": "(3,2)",
  "g4": "(3,3)",
  "g1": "(3,4)",
  "d1": "(3,5)",
  "a1": "(3,6)",
  "a4": "(3,7)",
  "a7": "(3,8)",
};

Map<String, String> playOkNotationToMove = <String, String>{
  "8": "(1,1)",
  "9": "(1,2)",
  "13": "(1,3)",
  "18": "(1,4)",
  "17": "(1,5)",
  "16": "(1,6)",
  "12": "(1,7)",
  "7": "(1,8)",
  "5": "(2,1)",
  "6": "(2,2)",
  "14": "(2,3)",
  "21": "(2,4)",
  "20": "(2,5)",
  "19": "(2,6)",
  "11": "(2,7)",
  "4": "(2,8)",
  "2": "(3,1)",
  "3": "(3,2)",
  "15": "(3,3)",
  "24": "(3,4)",
  "23": "(3,5)",
  "22": "(3,6)",
  "10": "(3,7)",
  "1": "(3,8)",
};
