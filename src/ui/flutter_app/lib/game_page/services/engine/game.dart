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

class Player {
  Player({required this.color, required this.isAi});
  final PieceColor color;
  bool isAi;
}

class Game {
  Game({required GameMode gameMode}) {
    this.gameMode = gameMode;
  }

  static const String _logTag = "[game]";

  PieceColor sideToMove = PieceColor.white;

  bool get isAiToMove {
    assert(sideToMove == PieceColor.white || sideToMove == PieceColor.black);
    return getPlayerByColor(sideToMove).isAi;
  }

  bool get isHumanToMove => !isAiToMove;

  int? focusIndex;
  int? blurIndex;

  final List<Player> players = <Player>[
    Player(color: PieceColor.white, isAi: false),
    Player(color: PieceColor.black, isAi: true),
  ];

  Player getPlayerByColor(PieceColor color) {
    if (color == PieceColor.draw) {
      return Player(color: PieceColor.draw, isAi: false);
    } else if (color == PieceColor.ban) {
      return Player(color: PieceColor.ban, isAi: false);
    } else if (color == PieceColor.nobody) {
      return Player(color: PieceColor.nobody, isAi: false);
    } else if (color == PieceColor.none) {
      return Player(color: PieceColor.none, isAi: false);
    }

    return players.firstWhere((Player player) => player.color == color);
  }

  void reverseWhoIsAi() {
    if (GameController().gameInstance.gameMode == GameMode.humanVsAi) {
      for (final Player player in players) {
        player.isAi = !player.isAi;
      }
    } else if (GameController().gameInstance.gameMode ==
        GameMode.humanVsHuman) {
      final bool whiteIsAi = getPlayerByColor(PieceColor.white).isAi;
      final bool blackIsAi = getPlayerByColor(PieceColor.black).isAi;
      if (whiteIsAi == blackIsAi) {
        getPlayerByColor(GameController().position.sideToMove).isAi = true;
      } else {
        for (final Player player in players) {
          player.isAi = false;
        }
      }
    }
  }

  late GameMode _gameMode;
  GameMode get gameMode => _gameMode;

  set gameMode(GameMode type) {
    _gameMode = type;

    logger.i("$_logTag Engine type: $type");

    final Map<PieceColor, bool> whoIsAi = type.whoIsAI;
    for (final Player player in players) {
      player.isAi = whoIsAi[player.color]!;
    }

    logger.i(
      "$_logTag White is AI? ${getPlayerByColor(PieceColor.white).isAi}\n"
      "$_logTag Black is AI? ${getPlayerByColor(PieceColor.black).isAi}\n",
    );
  }

  void _select(int pos) {
    focusIndex = pos;
    blurIndex = null;
  }

  @visibleForTesting
  bool doMove(ExtMove extMove) {
    assert(GameController().position.phase != Phase.ready);

    logger.i("$_logTag AI do move: $extMove");

    if (GameController().position.doMove(extMove.move) == false) {
      return false;
    }

    GameController().gameRecorder.add(extMove);

    if (GameController().position.phase != Phase.gameOver) {
      GameController().gameResultNotifier.showResult(force: false);
    }

    GifShare().captureView();

    // TODO: moveHistoryText is not lightweight.
    if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
      final CatcherOptions options = catcher.getCurrentConfig()!;
      options.customParameters["MoveList"] =
          GameController().gameRecorder.moveHistoryText;
    }

    sideToMove = GameController().position.sideToMove;

    _logStat();

    return true;
  }

  void _logStat() {
    final Position position = GameController().position;
    final int total = Position.score[PieceColor.white]! +
        Position.score[PieceColor.black]! +
        Position.score[PieceColor.draw]!;

    double whiteWinRate = 0;
    double blackWinRate = 0;
    double drawRate = 0;
    if (total != 0) {
      whiteWinRate = Position.score[PieceColor.white]! * 100 / total;
      blackWinRate = Position.score[PieceColor.black]! * 100 / total;
      drawRate = Position.score[PieceColor.draw]! * 100 / total;
    }

    final String scoreInfo = "Score: ${position.scoreString}\ttotal:"
        " $total\n$whiteWinRate% : $blackWinRate% : $drawRate%\n";

    logger.i("$_logTag $scoreInfo");
  }
}
