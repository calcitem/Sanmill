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

import 'package:sanmill/mill/game.dart';

import 'profile.dart';

class Config {
  static bool bgmEnabled = false;
  static bool toneEnabled = true;
  static int thinkingTime = 5000;
  static PlayerType whoMovesFirst = PlayerType.human;

  static bool isAutoRestart = false;
  static bool isAutoChangeFirstMove = false;
  static bool resignIfMostLose = false;
  static bool randomMoveEnabled = true;
  static bool learnEndgame = false;
  static bool idsEnabled = false;
  static bool depthExtension = true;
  static bool openingBook = false;

  // Rules
  static int nTotalPiecesEachSide = 12;
  static int nPiecesAtLeast = 3;
  static bool hasObliqueLines = true;
  static bool hasBannedLocations = true;
  static bool isDefenderMoveFirst = true;
  static bool allowRemoveMultiPiecesWhenCloseMultiMill = false;
  static bool allowRemovePieceInMill = true;
  static bool isBlackLoseButNotDrawWhenBoardFull = true;
  static bool isLoseButNotChangeSideWhenNoWay = true;
  static bool allowFlyWhenRemainThreePieces = false;
  static int maxStepsLedToDraw = 50;

  static Future<void> loadProfile() async {
    final profile = await Profile.shared();

    Config.bgmEnabled = profile['bgm-enabled'] ?? false;
    Config.toneEnabled = profile['tone-enabled'] ?? true;
    Config.thinkingTime = profile['thinking-time'] ?? 5000;
    Config.whoMovesFirst = profile['who-moves-first'] ?? PlayerType.human;

    Config.isAutoRestart = profile['isAutoRestart'] ?? false;
    Config.isAutoChangeFirstMove = profile['isAutoChangeFirstMove'] ?? false;
    Config.resignIfMostLose = profile['resignIfMostLose'] ?? false;
    Config.randomMoveEnabled = profile['randomMoveEnabled'] ?? true;
    Config.learnEndgame = profile['learnEndgame'] ?? false;
    Config.idsEnabled = profile['idsEnabled'] ?? false;
    Config.depthExtension = profile['depthExtension'] ?? false;
    Config.openingBook = profile['openingBook'] ?? false;

    // Rules
    Game.shared.position.rule.nTotalPiecesEachSide =
        Config.nTotalPiecesEachSide = profile['nTotalPiecesEachSide'] ?? 12;
    Game.shared.position.rule.nPiecesAtLeast =
        Config.nPiecesAtLeast = profile['nPiecesAtLeast'] ?? 3;
    Game.shared.position.rule.hasObliqueLines =
        Config.hasObliqueLines = profile['hasObliqueLines'] ?? true;
    Game.shared.position.rule.hasBannedLocations =
        Config.hasBannedLocations = profile['hasBannedLocations'] ?? true;
    Game.shared.position.rule.isDefenderMoveFirst =
        Config.isDefenderMoveFirst = profile['isDefenderMoveFirst'] ?? true;
    Game.shared.position.rule.allowRemoveMultiPiecesWhenCloseMultiMill =
        Config.allowRemoveMultiPiecesWhenCloseMultiMill =
            profile['allowRemoveMultiPiecesWhenCloseMultiMill'] ?? false;
    Game.shared.position.rule.allowRemovePieceInMill = Config
        .allowRemovePieceInMill = profile['allowRemovePieceInMill'] ?? true;
    Game.shared.position.rule.isBlackLoseButNotDrawWhenBoardFull =
        Config.isBlackLoseButNotDrawWhenBoardFull =
            profile['isBlackLoseButNotDrawWhenBoardFull'] ?? true;
    Game.shared.position.rule.isLoseButNotChangeSideWhenNoWay =
        Config.isLoseButNotChangeSideWhenNoWay =
            profile['isLoseButNotChangeSideWhenNoWay'] ?? true;
    Game.shared.position.rule.allowFlyWhenRemainThreePieces =
        Config.allowFlyWhenRemainThreePieces =
            profile['allowFlyWhenRemainThreePieces'] ?? false;
    Game.shared.position.rule.maxStepsLedToDraw =
        Config.maxStepsLedToDraw = profile['maxStepsLedToDraw'] ?? 50;

    return true;
  }

  static Future<bool> save() async {
    final profile = await Profile.shared();

    profile['bgm-enabled'] = Config.bgmEnabled;
    profile['tone-enabled'] = Config.toneEnabled;
    profile['thinking-time'] = Config.thinkingTime;
    profile['who-moves-first'] = Config.whoMovesFirst;

    profile['isAutoRestart'] = Config.isAutoRestart;
    profile['isAutoChangeFirstMove'] = Config.isAutoChangeFirstMove;
    profile['resignIfMostLose'] = Config.resignIfMostLose;
    profile['randomMoveEnabled'] = Config.randomMoveEnabled;
    profile['learnEndgame'] = Config.learnEndgame;
    profile['idsEnabled'] = Config.idsEnabled;
    profile['depthExtension'] = Config.depthExtension;
    profile['openingBook'] = Config.openingBook;

    // Rules
    profile['nTotalPiecesEachSide'] = Config.nTotalPiecesEachSide;
    profile['nPiecesAtLeast'] = Config.nPiecesAtLeast;
    profile['hasObliqueLines'] = Config.hasObliqueLines;
    profile['hasBannedLocations'] = Config.hasBannedLocations;
    profile['isDefenderMoveFirst'] = Config.isDefenderMoveFirst;
    profile['allowRemoveMultiPiecesWhenCloseMultiMill'] =
        Config.allowRemoveMultiPiecesWhenCloseMultiMill;
    profile['allowRemovePieceInMill'] = Config.allowRemovePieceInMill;
    profile['isBlackLoseButNotDrawWhenBoardFull'] =
        Config.isBlackLoseButNotDrawWhenBoardFull;
    profile['isLoseButNotChangeSideWhenNoWay'] =
        Config.isLoseButNotChangeSideWhenNoWay;
    profile['allowFlyWhenRemainThreePieces'] =
        Config.allowFlyWhenRemainThreePieces;
    profile['maxStepsLedToDraw'] = Config.maxStepsLedToDraw;

    profile.commit();

    return true;
  }
}
