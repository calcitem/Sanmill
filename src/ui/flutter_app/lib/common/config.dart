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

import 'package:sanmill/common/constants.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/style/app_theme.dart';

import 'settings.dart';

class Config {
  static bool settingsLoaded = false;

  static bool isPrivacyPolicyAccepted = false;

  // Preferences
  static bool toneEnabled = true;
  static bool keepMuteWhenTakingBack = true;
  static bool aiMovesFirst = false;
  static bool aiIsLazy = false;
  static int skillLevel = 1;
  static int moveTime = 1;
  static bool isAutoRestart = false;
  static bool isAutoChangeFirstMove = false;
  static bool resignIfMostLose = false;
  static bool shufflingEnabled = true;
  static bool learnEndgame = false;
  static bool openingBook = false;
  static bool drawOnHumanExperience = true;
  static bool considerMobility = false;
  static bool developerMode = false;
  static bool experimentsEnabled = false;

  // Display
  static String languageCode = Constants.defaultLanguageCodeName;
  static bool standardNotationEnabled = true;
  static bool isPieceCountInHandShown = true;
  static bool isNotationsShown = false;
  static bool isHistoryNavigationToolbarShown = false;
  static double boardBorderLineWidth = 2.0;
  static double boardInnerLineWidth = 2.0;
  static double pieceWidth = 0.9;
  static double fontSize = 16.0;
  static double boardTop = isLargeScreen() ? 75.0 : 36.0;
  static double animationDuration = 0.0;

  // Color
  static int boardLineColor = AppTheme.boardLineColor.value;
  static int darkBackgroundColor = AppTheme.darkBackgroundColor.value;
  static int boardBackgroundColor = AppTheme.boardBackgroundColor.value;
  static int whitePieceColor = AppTheme.whitePieceColor.value;
  static int blackPieceColor = AppTheme.blackPieceColor.value;
  static int messageColor = AppTheme.messageColor.value;
  static int drawerColor = AppTheme.drawerColor.value;
  static int drawerBackgroundColor = AppTheme.drawerBackgroundColor.value;
  static int drawerTextColor = AppTheme.drawerTextColor.value;
  static int drawerHighlightItemColor = AppTheme.drawerHighlightItemColor.value;
  static int mainToolbarBackgroundColor =
      AppTheme.mainToolbarBackgroundColor.value;
  static int mainToolbarIconColor = AppTheme.mainToolbarIconColor.value;
  static int navigationToolbarBackgroundColor =
      AppTheme.navigationToolbarBackgroundColor.value;
  static int navigationToolbarIconColor =
      AppTheme.navigationToolbarIconColor.value;

  // Rules
  static int piecesCount = specialCountryAndRegion == "Iran" ? 12 : 9;
  static int flyPieceCount = 3;
  static int piecesAtLeastCount = 3;
  static bool hasDiagonalLines =
      specialCountryAndRegion == "Iran" ? true : false;
  static bool hasBannedLocations = false;
  static bool mayMoveInPlacingPhase = false;
  static bool isDefenderMoveFirst = false;
  static bool mayRemoveMultiple = false;
  static bool mayRemoveFromMillsAlways = false;
  static bool isWhiteLoseButNotDrawWhenBoardFull = true;
  static bool isLoseButNotChangeSideWhenNoWay = true;
  static bool mayFly = true;
  static int nMoveRule = 100;

  static Future<void> loadSettings() async {
    print("[config] Loading settings...");

    final settings = await Settings.instance();

    Config.isPrivacyPolicyAccepted =
        settings['IsPrivacyPolicyAccepted'] ?? false;

    // Preferences
    Config.toneEnabled = settings['ToneEnabled'] ?? true;
    Config.keepMuteWhenTakingBack = settings['KeepMuteWhenTakingBack'] ?? true;
    Config.aiMovesFirst = settings['AiMovesFirst'] ?? false;
    Config.aiIsLazy = settings['AiIsLazy'] ?? false;
    Config.skillLevel = settings['SkillLevel'] ?? 1;
    Config.moveTime = settings['MoveTime'] ?? 1;
    Config.isAutoRestart = settings['IsAutoRestart'] ?? false;
    Config.isAutoChangeFirstMove = settings['IsAutoChangeFirstMove'] ?? false;
    Config.resignIfMostLose = settings['ResignIfMostLose'] ?? false;
    Config.shufflingEnabled = settings['ShufflingEnabled'] ?? true;
    Config.learnEndgame = settings['LearnEndgame'] ?? false;
    Config.openingBook = settings['OpeningBook'] ?? false;
    Config.drawOnHumanExperience = settings['DrawOnHumanExperience'] ?? true;
    Config.considerMobility = settings['ConsiderMobility'] ?? false;
    Config.developerMode = settings['DeveloperMode'] ?? false;
    Config.experimentsEnabled = settings['ExperimentsEnabled'] ?? false;

    // Display
    Config.languageCode =
        settings['LanguageCode'] ?? Constants.defaultLanguageCodeName;
    Config.standardNotationEnabled =
        settings['StandardNotationEnabled'] ?? true;
    Config.isPieceCountInHandShown =
        settings['IsPieceCountInHandShown'] ?? true;
    Config.isNotationsShown = settings['IsNotationsShown'] ?? false;
    Config.isHistoryNavigationToolbarShown =
        settings['IsHistoryNavigationToolbarShown'] ?? false;
    Config.boardBorderLineWidth = settings['BoardBorderLineWidth'] ?? 2;
    Config.boardInnerLineWidth = settings['BoardInnerLineWidth'] ?? 2;
    Config.pieceWidth = settings['PieceWidth'] ?? 0.9;
    Config.fontSize = settings['FontSize'] ?? 16.0;
    Config.boardTop = settings['BoardTop'] ?? (isLargeScreen() ? 75 : 36);
    Config.animationDuration = settings['AnimationDuration'] ?? 0;

    // Color
    Config.boardLineColor =
        settings['BoardLineColor'] ?? AppTheme.boardLineColor.value;
    Config.darkBackgroundColor =
        settings['DarkBackgroundColor'] ?? AppTheme.darkBackgroundColor.value;
    Config.boardBackgroundColor =
        settings['BoardBackgroundColor'] ?? AppTheme.boardBackgroundColor.value;
    Config.whitePieceColor =
        settings['WhitePieceColor'] ?? AppTheme.whitePieceColor.value;
    Config.blackPieceColor =
        settings['BlackPieceColor'] ?? AppTheme.blackPieceColor.value;
    Config.messageColor =
        settings['MessageColor'] ?? AppTheme.messageColor.value;
    Config.drawerColor = settings['DrawerColor'] ?? AppTheme.drawerColor.value;
    Config.drawerBackgroundColor = settings['DrawerBackgroundColor'] ??
        AppTheme.drawerBackgroundColor.value;
    Config.drawerTextColor =
        settings['DrawerTextColor'] ?? AppTheme.drawerTextColor.value;
    Config.drawerHighlightItemColor = settings['DrawerHighlightItemColor'] ??
        AppTheme.drawerHighlightItemColor.value;
    Config.mainToolbarBackgroundColor =
        settings['MainToolbarBackgroundColor'] ??
            AppTheme.mainToolbarBackgroundColor.value;
    Config.mainToolbarIconColor =
        settings['MainToolbarIconColor'] ?? AppTheme.mainToolbarIconColor.value;
    Config.navigationToolbarBackgroundColor =
        settings['NavigationToolbarBackgroundColor'] ??
            AppTheme.navigationToolbarBackgroundColor.value;
    Config.navigationToolbarIconColor =
        settings['NavigationToolbarIconColor'] ??
            AppTheme.navigationToolbarIconColor.value;

    // Rules
    rule.piecesCount = Config.piecesCount =
        settings['PiecesCount'] ?? (specialCountryAndRegion == "Iran" ? 12 : 9);
    rule.flyPieceCount = Config.flyPieceCount = settings['FlyPieceCount'] ?? 3;
    rule.piecesAtLeastCount =
        Config.piecesAtLeastCount = settings['PiecesAtLeastCount'] ?? 3;
    rule.hasDiagonalLines = Config.hasDiagonalLines =
        settings['HasDiagonalLines'] ??
            (specialCountryAndRegion == "Iran" ? true : false);
    rule.hasBannedLocations =
        Config.hasBannedLocations = settings['HasBannedLocations'] ?? false;
    rule.mayMoveInPlacingPhase = Config.mayMoveInPlacingPhase =
        settings['MayMoveInPlacingPhase'] ?? false;
    rule.isDefenderMoveFirst =
        Config.isDefenderMoveFirst = settings['IsDefenderMoveFirst'] ?? false;
    rule.mayRemoveMultiple =
        Config.mayRemoveMultiple = settings['MayRemoveMultiple'] ?? false;
    rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways =
        settings['MayRemoveFromMillsAlways'] ?? false;
    rule.isWhiteLoseButNotDrawWhenBoardFull =
        Config.isWhiteLoseButNotDrawWhenBoardFull =
            settings['IsWhiteLoseButNotDrawWhenBoardFull'] ?? true;
    rule.isLoseButNotChangeSideWhenNoWay =
        Config.isLoseButNotChangeSideWhenNoWay =
            settings['IsLoseButNotChangeSideWhenNoWay'] ?? true;
    rule.mayFly = Config.mayFly = settings['MayFly'] ?? true;
    rule.nMoveRule = Config.nMoveRule = settings['NMoveRule'] ?? 100;

    settingsLoaded = true;
    print("[config] Loading settings done!");
  }

  static Future<bool> save() async {
    final settings = await Settings.instance();

    settings['IsPrivacyPolicyAccepted'] = Config.isPrivacyPolicyAccepted;

    // Preferences
    settings['ToneEnabled'] = Config.toneEnabled;
    settings['KeepMuteWhenTakingBack'] = Config.keepMuteWhenTakingBack;
    settings['AiMovesFirst'] = Config.aiMovesFirst;
    settings['AiIsLazy'] = Config.aiIsLazy;
    settings['SkillLevel'] = Config.skillLevel;
    settings['MoveTime'] = Config.moveTime;
    settings['IsAutoRestart'] = Config.isAutoRestart;
    settings['IsAutoChangeFirstMove'] = Config.isAutoChangeFirstMove;
    settings['ResignIfMostLose'] = Config.resignIfMostLose;
    settings['ShufflingEnabled'] = Config.shufflingEnabled;
    settings['LearnEndgame'] = Config.learnEndgame;
    settings['OpeningBook'] = Config.openingBook;
    settings['DrawOnHumanExperience'] = Config.drawOnHumanExperience;
    settings['ConsiderMobility'] = Config.considerMobility;
    settings['DeveloperMode'] = Config.developerMode;
    settings['ExperimentsEnabled'] = Config.experimentsEnabled;

    // Display
    settings['LanguageCode'] = Config.languageCode;
    settings['StandardNotationEnabled'] = Config.standardNotationEnabled;
    settings['IsPieceCountInHandShown'] = Config.isPieceCountInHandShown;
    settings['IsNotationsShown'] = Config.isNotationsShown;
    settings['IsHistoryNavigationToolbarShown'] =
        Config.isHistoryNavigationToolbarShown;
    settings['BoardBorderLineWidth'] = Config.boardBorderLineWidth;
    settings['BoardInnerLineWidth'] = Config.boardInnerLineWidth;
    settings['PieceWidth'] = Config.pieceWidth;
    settings['FontSize'] = Config.fontSize;
    settings['BoardTop'] = Config.boardTop;
    settings['AnimationDuration'] = Config.animationDuration;

    // Color
    settings['BoardLineColor'] = Config.boardLineColor;
    settings['DarkBackgroundColor'] = Config.darkBackgroundColor;
    settings['BoardBackgroundColor'] = Config.boardBackgroundColor;
    settings['WhitePieceColor'] = Config.whitePieceColor;
    settings['BlackPieceColor'] = Config.blackPieceColor;
    settings['MessageColor'] = Config.messageColor;
    settings['DrawerColor'] = Config.drawerColor;
    settings['DrawerBackgroundColor'] = Config.drawerBackgroundColor;
    settings['DrawerTextColor'] = Config.drawerTextColor;
    settings['DrawerHighlightItemColor'] = Config.drawerHighlightItemColor;
    settings['MainToolbarBackgroundColor'] = Config.mainToolbarBackgroundColor;
    settings['MainToolbarIconColor'] = Config.mainToolbarIconColor;
    settings['NavigationToolbarBackgroundColor'] =
        Config.navigationToolbarBackgroundColor;
    settings['NavigationToolbarIconColor'] = Config.navigationToolbarIconColor;

    // Rules
    settings['PiecesCount'] = Config.piecesCount;
    settings['FlyPieceCount'] = Config.flyPieceCount;
    settings['PiecesAtLeastCount'] = Config.piecesAtLeastCount;
    settings['HasDiagonalLines'] = Config.hasDiagonalLines;
    settings['HasBannedLocations'] = Config.hasBannedLocations;
    settings['MayMoveInPlacingPhase'] = Config.mayMoveInPlacingPhase;
    settings['IsDefenderMoveFirst'] = Config.isDefenderMoveFirst;
    settings['MayRemoveMultiple'] = Config.mayRemoveMultiple;
    settings['MayRemoveFromMillsAlways'] = Config.mayRemoveFromMillsAlways;
    settings['IsWhiteLoseButNotDrawWhenBoardFull'] =
        Config.isWhiteLoseButNotDrawWhenBoardFull;
    settings['IsLoseButNotChangeSideWhenNoWay'] =
        Config.isLoseButNotChangeSideWhenNoWay;
    settings['MayFly'] = Config.mayFly;
    settings['NMoveRule'] = Config.nMoveRule;

    settings.commit();

    return true;
  }
}
