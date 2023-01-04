// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

class Game {
  Game();

  static const String _tag = "[game]";

  PieceColor sideToMove = PieceColor.white;

  bool get isAiToMove {
    assert(sideToMove == PieceColor.white || sideToMove == PieceColor.black);
    return _isAi[sideToMove]!;
  }

  bool get isHumanToMove => !isAiToMove;

  int? focusIndex;
  int? blurIndex;

  // TODO: [Leptopoda] Give a game two players (new class) to hold a player. A player can have a color, be AI ...
  Map<PieceColor, bool> _isAi = <PieceColor, bool>{
    PieceColor.white: false,
    PieceColor.black: true,
  };

  void reverseWhoIsAi() {
    _isAi[PieceColor.white] = !_isAi[PieceColor.white]!;
    _isAi[PieceColor.black] = !_isAi[PieceColor.black]!;
  }

  // TODO: [Leptopoda] Make gameMode final and set it through the constructor.
  late GameMode _gameMode;
  GameMode get gameMode => _gameMode;

  set gameMode(GameMode type) {
    _gameMode = type;

    logger.i("$_tag Engine type: $type");

    _isAi = type.whoIsAI;

    logger.i(
      "$_tag White is AI? ${_isAi[PieceColor.white]}\n"
      "$_tag Black is AI? ${_isAi[PieceColor.black]}\n",
    );
  }

  void _select(int pos) {
    focusIndex = pos;
    blurIndex = null;
  }

  @visibleForTesting
  bool doMove(ExtMove extMove) {
    assert(MillController().position.phase != Phase.ready);

    logger.i("$_tag AI do move: $extMove");

    if (MillController().position.doMove(extMove.move) == false) {
      return false;
    }

    MillController().recorder.add(extMove);
    GifShare().captureView();

    // TODO: moveHistoryText is not lightweight.
    if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
      final CatcherOptions options = catcher.getCurrentConfig()!;
      options.customParameters["MoveList"] =
          MillController().recorder.moveHistoryText;
    }

    sideToMove = MillController().position.sideToMove;

    _logStat();

    return true;
  }

  void _logStat() {
    final Position position = MillController().position;
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

    logger.i("$_tag $scoreInfo");
  }
}
