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

part of '../mill.dart';

int abs(int value) => value > 0 ? value : -value;

enum _MoveType { place, move, remove }

enum PieceColor { none, white, black, ban, nobody, draw }

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
        throw Exception("Player has no name");
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
        throw Exception("No piece name available");
    }
  }

  PieceColor get opponent {
    switch (this) {
      case PieceColor.black:
        return PieceColor.white;
      case PieceColor.white:
        return PieceColor.black;
      default:
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
        return controller.position.phase.getTip(context);
      case PieceColor.none:
      case PieceColor.ban:
    }
  }

  GameResult get result {
    switch (this) {
      case PieceColor.white:
        if (controller.gameInstance._isAi[this]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.black:
        if (controller.gameInstance._isAi[this]!) {
          return GameResult.lose;
        } else {
          return GameResult.win;
        }
      case PieceColor.draw:
        return GameResult.draw;
      default:
        return GameResult.none;
    }
  }

  IconData get icon {
    return controller.position.phase == Phase.gameOver ? _arrow : _chevron;
  }

  IconData get _chevron {
    switch (this) {
      case PieceColor.white:
        return FluentIcons.chevron_left_24_regular;
      case PieceColor.black:
        return FluentIcons.chevron_right_24_regular;
      default:
        return FluentIcons.code_24_regular;
    }
  }

  IconData get _arrow {
    switch (this) {
      case PieceColor.white:
        return FluentIcons.toggle_left_24_regular;
      case PieceColor.black:
        return FluentIcons.toggle_right_24_regular;
      default:
        return FluentIcons.handshake_24_regular;
    }
  }
}

enum Phase { none, ready, placing, moving, gameOver }

extension PhaseExtension on Phase {
  String get fen {
    switch (this) {
      case Phase.none:
        return "n";
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
      case Phase.none:
      case Phase.ready:
      case Phase.gameOver:
    }
  }

  String? getName(BuildContext context) {
    switch (this) {
      case Phase.placing:
        return S.of(context).placingPhase;
      case Phase.moving:
        return S.of(context).movingPhase;
      case Phase.none:
      case Phase.ready:
      case Phase.gameOver:
    }
  }
}

enum Act { none, select, place, remove }

extension ActExtension on Act {
  String get fen {
    switch (this) {
      case Act.place:
        return "p";
      case Act.select:
        return "s";
      case Act.remove:
        return "r";
      case Act.none:
        return "?";
    }
  }
}

enum GameOverReason {
  none,
  loseLessThanThree,
  loseNoWay,
  loseBoardIsFull,
  loseResign,
  loseTimeOver,
  drawThreefoldRepetition,
  drawRule50,
  drawEndgameRule50,
  drawBoardIsFull
}

extension GameOverReasonExtension on GameOverReason {
  String getName(BuildContext context, PieceColor winner) {
    final loserStr = winner.opponent.playerName(context);

    switch (this) {
      case GameOverReason.loseLessThanThree:
        return S.of(context).loseReasonlessThanThree(loserStr);
      case GameOverReason.loseResign:
        return S.of(context).loseReasonResign(loserStr);
      case GameOverReason.loseNoWay:
        return S.of(context).loseReasonNoWay(loserStr);
      case GameOverReason.loseBoardIsFull:
        return S.of(context).loseReasonBoardIsFull(loserStr);
      case GameOverReason.loseTimeOver:
        return S.of(context).loseReasonTimeOver(loserStr);
      case GameOverReason.drawRule50:
        return S.of(context).drawReasonRule50;
      case GameOverReason.drawEndgameRule50:
        return S.of(context).drawReasonEndgameRule50;
      case GameOverReason.drawBoardIsFull:
        return S.of(context).drawReasonBoardIsFull;
      case GameOverReason.drawThreefoldRepetition:
        return S.of(context).drawReasonThreefoldRepetition;
      case GameOverReason.none:
        return S.of(context).gameOverUnknownReason;
    }
  }
}

enum GameResult { pending, win, lose, draw, none }

extension GameResultExtension on GameResult {
  String winString(BuildContext context) {
    switch (this) {
      case GameResult.win:
        return controller.gameInstance.engineType == EngineType.humanVsAi
            ? S.of(context).youWin
            : S.of(context).gameOver;
      case GameResult.lose:
        return S.of(context).gameOver;
      case GameResult.draw:
        return S.of(context).isDraw;
      case GameResult.pending:
      case GameResult.none:
        throw Exception("No winnig string available");
    }
  }
}

enum _HistoryResponse { equal, outOfRange, error }

extension HistoryResponseExtension on _HistoryResponse {
  String getString(BuildContext context) {
    switch (this) {
      case _HistoryResponse.outOfRange:
      case _HistoryResponse.equal:
        return S.of(context).atEnd;
      case _HistoryResponse.error:
        return S.of(context).movesAndRulesNotMatch;
    }
  }
}

enum SelectionResponse { r0, r1, r2, r3, r4 }
enum RemoveResponse { r0, r1, r2, r3 }

enum HistoryMove { forwardAll, backAll, forward, backN, backOne }

extension HistoryMoveExtension on HistoryMove {
  int gotoHistoryIndex([int? index]) {
    switch (this) {
      case HistoryMove.forwardAll:
        return controller.position.recorder.moveCount - 1;
      case HistoryMove.backAll:
        return -1;
      case HistoryMove.forward:
        return controller.position.recorder.cur + 1;
      case HistoryMove.backN:
        assert(index != null);
        int _index = controller.position.recorder.cur - index!;
        if (_index < -1) {
          _index = -1;
        }
        return _index;
      case HistoryMove.backOne:
        return controller.position.recorder.cur - 1;
    }
  }

  Future<void> gotoHistoryPlaySound() async {
    if (!LocalDatabaseService.preferences.keepMuteWhenTakingBack) {
      switch (this) {
        case HistoryMove.forwardAll:
        case HistoryMove.forward:
          return Audios.playTone(Sound.place);
        case HistoryMove.backAll:
        case HistoryMove.backN:
        case HistoryMove.backOne:
          return Audios.playTone(Sound.remove);
      }
    }
  }
}

const sqBegin = 8;
const sqEnd = 32;
const sqNumber = 40;

const moveDirectionBegin = 0;
const moveDirectionNumber = 4;

const lineDirectionNumber = 3;

const fileNumber = 3;
const fileExNumber = fileNumber + 2;

const rankNumber = 8;

int makeSquare(int file, int rank) {
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

Map<int, int> squareToIndex = {
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

Map<int, int> indexToSquare = squareToIndex.map((k, v) => MapEntry(v, k));

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
Map<int, String> _squareToWmdNotation = {
  8: "d5",
  9: "e5",
  10: "e4",
  11: "e3",
  12: "d3",
  13: "c3",
  14: "c4",
  15: "c5",
  16: "d6",
  17: "f6",
  18: "f4",
  19: "f2",
  20: "d2",
  21: "b2",
  22: "b4",
  23: "b6",
  24: "d7",
  25: "g7",
  26: "g4",
  27: "g1",
  28: "d1",
  29: "a1",
  30: "a4",
  31: "a7"
};

Map<String, String> wmdNotationToMove = {
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

Map<String, String> playOkNotationToMove = {
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
