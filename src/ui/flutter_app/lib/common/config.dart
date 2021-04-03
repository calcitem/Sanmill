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
import 'package:sanmill/style/app_theme.dart';

import 'settings.dart';

class Config {
  static bool toneEnabled = true;
  static int thinkingTime = 10000; // TODO: waitResponse
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
  static int boardLineColor = AppTheme.boardLineColor.value;
  static int darkBackgroundColor = AppTheme.darkBackgroundColor.value;
  static int boardBackgroundColor = AppTheme.boardBackgroundColor.value;
  static int blackPieceColor = AppTheme.blackPieceColor.value;
  static int whitePieceColor = AppTheme.whitePieceColor.value;

  // Rules
  static int piecesCount = 9;
  static int piecesAtLeastCount = 3;
  static bool hasDiagonalLines = false;
  static bool hasBannedLocations = false;
  static bool isDefenderMoveFirst = false;
  static bool mayRemoveMultiple = false;
  static bool mayRemoveFromMillsAlways = false;
  static bool isBlackLoseButNotDrawWhenBoardFull = true;
  static bool isLoseButNotChangeSideWhenNoWay = true;
  static bool mayFly = true;
  static int maxStepsLedToDraw = 50;

  static Future<void> loadProfile() async {
    final settings = await Settings.instance();

    Config.toneEnabled = settings['ToneEnabled'] ?? true;
    Config.thinkingTime =
        settings['ThinkingTime'] ?? 10000; // TODO: waitResponse
    Config.aiMovesFirst = settings['AiMovesFirst'] ?? false;
    Config.aiIsLazy = settings['AiIsLazy'] ?? false;
    Config.skillLevel = settings['SkillLevel'] ?? 20;
    Config.isAutoRestart = settings['IsAutoRestart'] ?? false;
    Config.isAutoChangeFirstMove = settings['IsAutoChangeFirstMove'] ?? false;
    Config.resignIfMostLose = settings['ResignIfMostLose'] ?? false;
    Config.shufflingEnabled = settings['ShufflingEnabled'] ?? true;
    Config.learnEndgame = settings['LearnEndgame'] ?? false;
    Config.idsEnabled = settings['IdsEnabled'] ?? false;
    Config.depthExtension = settings['DepthExtension'] ?? false;
    Config.openingBook = settings['OpeningBook'] ?? false;

    // Display
    Config.isPieceCountInHandShown =
        settings['IsPieceCountInHandShown'] ?? false;
    Config.boardBorderLineWidth = settings['BoardBorderLineWidth'] ?? 2;
    Config.boardInnerLineWidth = settings['BoardInnerLineWidth'] ?? 2;

    // Color
    Config.boardLineColor =
        settings['BoardLineColor'] ?? AppTheme.boardLineColor.value;
    Config.darkBackgroundColor =
        settings['DarkBackgroundColor'] ?? AppTheme.darkBackgroundColor.value;
    Config.boardBackgroundColor =
        settings['BoardBackgroundColor'] ?? AppTheme.boardBackgroundColor.value;
    Config.blackPieceColor =
        settings['BlackPieceColor'] ?? AppTheme.blackPieceColor.value;
    Config.whitePieceColor =
        settings['WhitePieceColor'] ?? AppTheme.whitePieceColor.value;

    // Rules
    rule.piecesCount = Config.piecesCount = settings['PiecesCount'] ?? 9;
    rule.piecesAtLeastCount =
        Config.piecesAtLeastCount = settings['PiecesAtLeastCount'] ?? 3;
    rule.hasDiagonalLines =
        Config.hasDiagonalLines = settings['HasDiagonalLines'] ?? false;
    rule.hasBannedLocations =
        Config.hasBannedLocations = settings['HasBannedLocations'] ?? false;
    rule.isDefenderMoveFirst =
        Config.isDefenderMoveFirst = settings['IsDefenderMoveFirst'] ?? false;
    rule.mayRemoveMultiple =
        Config.mayRemoveMultiple = settings['MayRemoveMultiple'] ?? false;
    rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways =
        settings['MayRemoveFromMillsAlways'] ?? false;
    rule.isBlackLoseButNotDrawWhenBoardFull =
        Config.isBlackLoseButNotDrawWhenBoardFull =
            settings['IsBlackLoseButNotDrawWhenBoardFull'] ?? true;
    rule.isLoseButNotChangeSideWhenNoWay =
        Config.isLoseButNotChangeSideWhenNoWay =
            settings['IsLoseButNotChangeSideWhenNoWay'] ?? true;
    rule.mayFly = Config.mayFly = settings['MayFly'] ?? true;
    rule.maxStepsLedToDraw =
        Config.maxStepsLedToDraw = settings['MaxStepsLedToDraw'] ?? 50;
  }

  static Future<bool> save() async {
    final settings = await Settings.instance();

    settings['ToneEnabled'] = Config.toneEnabled;
    settings['ThinkingTime'] = Config.thinkingTime;
    settings['AiMovesFirst'] = Config.aiMovesFirst;
    settings['AiIsLazy'] = Config.aiIsLazy;
    settings['SkillLevel'] = Config.skillLevel;
    settings['IsAutoRestart'] = Config.isAutoRestart;
    settings['IsAutoChangeFirstMove'] = Config.isAutoChangeFirstMove;
    settings['ResignIfMostLose'] = Config.resignIfMostLose;
    settings['ShufflingEnabled'] = Config.shufflingEnabled;
    settings['LearnEndgame'] = Config.learnEndgame;
    settings['IdsEnabled'] = Config.idsEnabled;
    settings['DepthExtension'] = Config.depthExtension;
    settings['OpeningBook'] = Config.openingBook;

    // Display
    settings['IsPieceCountInHandShown'] = Config.isPieceCountInHandShown;
    settings['BoardBorderLineWidth'] = Config.boardBorderLineWidth;
    settings['BoardInnerLineWidth'] = Config.boardInnerLineWidth;

    // Color
    settings['BoardLineColor'] = Config.boardLineColor;
    settings['DarkBackgroundColor'] = Config.darkBackgroundColor;
    settings['BoardBackgroundColor'] = Config.boardBackgroundColor;
    settings['BlackPieceColor'] = Config.blackPieceColor;
    settings['WhitePieceColor'] = Config.whitePieceColor;

    // Rules
    settings['PiecesCount'] = Config.piecesCount;
    settings['PiecesAtLeastCount'] = Config.piecesAtLeastCount;
    settings['HasDiagonalLines'] = Config.hasDiagonalLines;
    settings['HasBannedLocations'] = Config.hasBannedLocations;
    settings['IsDefenderMoveFirst'] = Config.isDefenderMoveFirst;
    settings['MayRemoveMultiple'] = Config.mayRemoveMultiple;
    settings['MayRemoveFromMillsAlways'] = Config.mayRemoveFromMillsAlways;
    settings['IsBlackLoseButNotDrawWhenBoardFull'] =
        Config.isBlackLoseButNotDrawWhenBoardFull;
    settings['IsLoseButNotChangeSideWhenNoWay'] =
        Config.isLoseButNotChangeSideWhenNoWay;
    settings['MayFly'] = Config.mayFly;
    settings['MaxStepsLedToDraw'] = Config.maxStepsLedToDraw;

    settings.commit();

    return true;
  }
}
