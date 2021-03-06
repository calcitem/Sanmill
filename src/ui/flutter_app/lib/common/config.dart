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

import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/style/colors.dart';

import 'profile.dart';

class Config {
  static bool toneEnabled = true;
  static int thinkingTime = 5000;
  static bool aiMovesFirst = false;
  static bool aiIsLazy = false;
  static int skillLevel = 20;
  static bool isAutoRestart = false;
  static bool isAutoChangeFirstMove = false;
  static bool resignIfMostLose = false;
  static bool shufflingEnabled = true;
  static bool learnEndgame = false;
  static bool idsEnabled = false;
  static bool depthExtension = true;
  static bool openingBook = false;

  // Display
  static bool isPieceCountInHandShown = false;
  static double boardBorderLineWidth = 2.0;
  static double boardInnerLineWidth = 2.0;

  // Color
  static int boardLineColor = UIColors.boardLineColor.value;
  static int darkBackgroundColor = UIColors.darkBackgroundColor.value;
  static int boardBackgroundColor = UIColors.boardBackgroundColor.value;
  static int blackPieceColor = UIColors.blackPieceColor.value;
  static int whitePieceColor = UIColors.whitePieceColor.value;

  // Rules
  static int piecesCount = 12;
  static int piecesAtLeastCount = 3;
  static bool hasObliqueLines = true;
  static bool hasBannedLocations = true;
  static bool isDefenderMoveFirst = true;
  static bool mayRemoveMultiple = false;
  static bool mayRemoveFromMillsAlways = true;
  static bool isBlackLoseButNotDrawWhenBoardFull = true;
  static bool isLoseButNotChangeSideWhenNoWay = true;
  static bool mayFly = false;
  static int maxStepsLedToDraw = 50;

  static Future<void> loadProfile() async {
    final profile = await Profile.shared();

    Config.toneEnabled = profile['ToneEnabled'] ?? true;
    Config.thinkingTime = profile['ThinkingTime'] ?? 5000;
    Config.aiMovesFirst = profile['AiMovesFirst'] ?? false;
    Config.aiIsLazy = profile['AiIsLazy'] ?? false;
    Config.skillLevel = profile['SkillLevel'] ?? 20;
    Config.isAutoRestart = profile['IsAutoRestart'] ?? false;
    Config.isAutoChangeFirstMove = profile['IsAutoChangeFirstMove'] ?? false;
    Config.resignIfMostLose = profile['ResignIfMostLose'] ?? false;
    Config.shufflingEnabled = profile['ShufflingEnabled'] ?? true;
    Config.learnEndgame = profile['LearnEndgame'] ?? false;
    Config.idsEnabled = profile['IdsEnabled'] ?? false;
    Config.depthExtension = profile['DepthExtension'] ?? false;
    Config.openingBook = profile['OpeningBook'] ?? false;

    // Display
    Config.isPieceCountInHandShown =
        profile['IsPieceCountInHandShown'] ?? false;
    Config.boardBorderLineWidth = profile['BoardBorderLineWidth'] ?? 2;
    Config.boardInnerLineWidth = profile['BoardInnerLineWidth'] ?? 2;

    // Color
    Config.boardLineColor =
        profile['BoardLineColor'] ?? UIColors.boardLineColor.value;
    Config.darkBackgroundColor =
        profile['DarkBackgroundColor'] ?? UIColors.darkBackgroundColor.value;
    Config.boardBackgroundColor =
        profile['BoardBackgroundColor'] ?? UIColors.boardBackgroundColor.value;
    Config.blackPieceColor =
        profile['BlackPieceColor'] ?? UIColors.blackPieceColor.value;
    Config.whitePieceColor =
        profile['WhitePieceColor'] ?? UIColors.whitePieceColor.value;

    // Rules
    rule.piecesCount = Config.piecesCount = profile['PiecesCount'] ?? 12;
    rule.piecesAtLeastCount =
        Config.piecesAtLeastCount = profile['PiecesAtLeastCount'] ?? 3;
    rule.hasObliqueLines =
        Config.hasObliqueLines = profile['HasObliqueLines'] ?? true;
    rule.hasBannedLocations =
        Config.hasBannedLocations = profile['HasBannedLocations'] ?? true;
    rule.isDefenderMoveFirst =
        Config.isDefenderMoveFirst = profile['IsDefenderMoveFirst'] ?? true;
    rule.mayRemoveMultiple =
        Config.mayRemoveMultiple = profile['MayRemoveMultiple'] ?? false;
    rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways =
        profile['MayRemoveFromMillsAlways'] ?? true;
    rule.isBlackLoseButNotDrawWhenBoardFull =
        Config.isBlackLoseButNotDrawWhenBoardFull =
            profile['IsBlackLoseButNotDrawWhenBoardFull'] ?? true;
    rule.isLoseButNotChangeSideWhenNoWay =
        Config.isLoseButNotChangeSideWhenNoWay =
            profile['IsLoseButNotChangeSideWhenNoWay'] ?? true;
    rule.mayFly = Config.mayFly = profile['MayFly'] ?? false;
    rule.maxStepsLedToDraw =
        Config.maxStepsLedToDraw = profile['MaxStepsLedToDraw'] ?? 50;
  }

  static Future<bool> save() async {
    final profile = await Profile.shared();

    profile['ToneEnabled'] = Config.toneEnabled;
    profile['ThinkingTime'] = Config.thinkingTime;
    profile['AiMovesFirst'] = Config.aiMovesFirst;
    profile['AiIsLazy'] = Config.aiIsLazy;
    profile['SkillLevel'] = Config.skillLevel;
    profile['IsAutoRestart'] = Config.isAutoRestart;
    profile['IsAutoChangeFirstMove'] = Config.isAutoChangeFirstMove;
    profile['ResignIfMostLose'] = Config.resignIfMostLose;
    profile['ShufflingEnabled'] = Config.shufflingEnabled;
    profile['LearnEndgame'] = Config.learnEndgame;
    profile['IdsEnabled'] = Config.idsEnabled;
    profile['DepthExtension'] = Config.depthExtension;
    profile['OpeningBook'] = Config.openingBook;

    // Display
    profile['IsPieceCountInHandShown'] = Config.isPieceCountInHandShown;
    profile['BoardBorderLineWidth'] = Config.boardBorderLineWidth;
    profile['BoardInnerLineWidth'] = Config.boardInnerLineWidth;

    // Color
    profile['BoardLineColor'] = Config.boardLineColor;
    profile['DarkBackgroundColor'] = Config.darkBackgroundColor;
    profile['BoardBackgroundColor'] = Config.boardBackgroundColor;
    profile['BlackPieceColor'] = Config.blackPieceColor;
    profile['WhitePieceColor'] = Config.whitePieceColor;

    // Rules
    profile['PiecesCount'] = Config.piecesCount;
    profile['PiecesAtLeastCount'] = Config.piecesAtLeastCount;
    profile['HasObliqueLines'] = Config.hasObliqueLines;
    profile['HasBannedLocations'] = Config.hasBannedLocations;
    profile['IsDefenderMoveFirst'] = Config.isDefenderMoveFirst;
    profile['MayRemoveMultiple'] = Config.mayRemoveMultiple;
    profile['MayRemoveFromMillsAlways'] = Config.mayRemoveFromMillsAlways;
    profile['IsBlackLoseButNotDrawWhenBoardFull'] =
        Config.isBlackLoseButNotDrawWhenBoardFull;
    profile['IsLoseButNotChangeSideWhenNoWay'] =
        Config.isLoseButNotChangeSideWhenNoWay;
    profile['MayFly'] = Config.mayFly;
    profile['MaxStepsLedToDraw'] = Config.maxStepsLedToDraw;

    profile.commit();

    return true;
  }
}
