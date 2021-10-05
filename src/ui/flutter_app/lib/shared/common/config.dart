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

import 'package:flutter/foundation.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/mill/rule.dart';
import 'package:sanmill/shared/common/constants.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

import 'settings.dart';

class Config {
  const Config._();
  static bool settingsLoaded = false;

  static bool isPrivacyPolicyAccepted = false;

  // Preferences
  static bool toneEnabled = true;
  static bool keepMuteWhenTakingBack = true;
  static bool screenReaderSupport = false;
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
  static int algorithm = 2;
  static bool drawOnHumanExperience = true;
  static bool considerMobility = true;
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
  static int pieceHighlightColor = AppTheme.pieceHighlightColor.value;
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
  static bool hasDiagonalLines = specialCountryAndRegion == "Iran";
  static bool hasBannedLocations = false;
  static bool mayMoveInPlacingPhase = false;
  static bool isDefenderMoveFirst = false;
  static bool mayRemoveMultiple = false;
  static bool mayRemoveFromMillsAlways = false;
  static bool mayOnlyRemoveUnplacedPieceInPlacingPhase = false;
  static bool isWhiteLoseButNotDrawWhenBoardFull = true;
  static bool isLoseButNotChangeSideWhenNoWay = true;
  static bool mayFly = true;
  static int nMoveRule = 100;
  static int endgameNMoveRule = 100;
  static bool threefoldRepetitionRule = true;

  // TODO: use jsonSerializable
  static Future<void> loadSettings() async {
   debugPrint("[config] Loading settings...");

    final settings = await Settings.instance();

    Config.isPrivacyPolicyAccepted =
        settings['IsPrivacyPolicyAccepted'] as bool? ?? false;

    // Preferences
    Config.toneEnabled = settings['ToneEnabled'] as bool? ?? true;
    Config.keepMuteWhenTakingBack =
        settings['KeepMuteWhenTakingBack'] as bool? ?? true;
    Config.screenReaderSupport =
        settings['ScreenReaderSupport'] as bool? ?? false;
    Config.aiMovesFirst = settings['AiMovesFirst'] as bool? ?? false;
    Config.aiIsLazy = settings['AiIsLazy'] as bool? ?? false;
    Config.skillLevel = settings['SkillLevel'] as int? ?? 1;
    Config.moveTime = settings['MoveTime'] as int? ?? 1;
    Config.isAutoRestart = settings['IsAutoRestart'] as bool? ?? false;
    Config.isAutoChangeFirstMove =
        settings['IsAutoChangeFirstMove'] as bool? ?? false;
    Config.resignIfMostLose = settings['ResignIfMostLose'] as bool? ?? false;
    Config.shufflingEnabled = settings['ShufflingEnabled'] as bool? ?? true;
    Config.learnEndgame = settings['LearnEndgame'] as bool? ?? false;
    Config.openingBook = settings['OpeningBook'] as bool? ?? false;
    Config.algorithm = settings['Algorithm'] as int? ?? 2;
    Config.drawOnHumanExperience =
        settings['DrawOnHumanExperience'] as bool? ?? true;
    Config.considerMobility = settings['ConsiderMobility'] as bool? ?? true;
    Config.developerMode = settings['DeveloperMode'] as bool? ?? false;
    Config.experimentsEnabled =
        settings['ExperimentsEnabled'] as bool? ?? false;

    // Display
    Config.languageCode = settings['LanguageCode'] as String? ??
        Constants.defaultLanguageCodeName;
    Config.standardNotationEnabled =
        settings['StandardNotationEnabled'] as bool? ?? true;
    Config.isPieceCountInHandShown =
        settings['IsPieceCountInHandShown'] as bool? ?? true;
    Config.isNotationsShown = settings['IsNotationsShown'] as bool? ?? false;
    Config.isHistoryNavigationToolbarShown =
        settings['IsHistoryNavigationToolbarShown'] as bool? ?? false;
    Config.boardBorderLineWidth =
        settings['BoardBorderLineWidth'] as double? ?? 2;
    Config.boardInnerLineWidth =
        settings['BoardInnerLineWidth'] as double? ?? 2;
    Config.pieceWidth = settings['PieceWidth'] as double? ?? 0.9;
    Config.fontSize = settings['FontSize'] as double? ?? 16.0;
    Config.boardTop =
        settings['BoardTop'] as double? ?? (isLargeScreen() ? 75 : 36);
    Config.animationDuration = settings['AnimationDuration'] as double? ?? 0;

    // Color
    Config.boardLineColor =
        settings['BoardLineColor'] as int? ?? AppTheme.boardLineColor.value;
    Config.darkBackgroundColor = settings['DarkBackgroundColor'] as int? ??
        AppTheme.darkBackgroundColor.value;
    Config.boardBackgroundColor = settings['BoardBackgroundColor'] as int? ??
        AppTheme.boardBackgroundColor.value;
    Config.whitePieceColor =
        settings['WhitePieceColor'] as int? ?? AppTheme.whitePieceColor.value;
    Config.blackPieceColor =
        settings['BlackPieceColor'] as int? ?? AppTheme.blackPieceColor.value;
    Config.pieceHighlightColor = settings['PieceHighlightColor'] as int? ??
        AppTheme.pieceHighlightColor.value;
    Config.messageColor =
        settings['MessageColor'] as int? ?? AppTheme.messageColor.value;
    Config.drawerColor =
        settings['DrawerColor'] as int? ?? AppTheme.drawerColor.value;
    Config.drawerBackgroundColor = settings['DrawerBackgroundColor'] as int? ??
        AppTheme.drawerBackgroundColor.value;
    Config.drawerTextColor =
        settings['DrawerTextColor'] as int? ?? AppTheme.drawerTextColor.value;
    Config.drawerHighlightItemColor =
        settings['DrawerHighlightItemColor'] as int? ??
            AppTheme.drawerHighlightItemColor.value;
    Config.mainToolbarBackgroundColor =
        settings['MainToolbarBackgroundColor'] as int? ??
            AppTheme.mainToolbarBackgroundColor.value;
    Config.mainToolbarIconColor = settings['MainToolbarIconColor'] as int? ??
        AppTheme.mainToolbarIconColor.value;
    Config.navigationToolbarBackgroundColor =
        settings['NavigationToolbarBackgroundColor'] as int? ??
            AppTheme.navigationToolbarBackgroundColor.value;
    Config.navigationToolbarIconColor =
        settings['NavigationToolbarIconColor'] as int? ??
            AppTheme.navigationToolbarIconColor.value;

    // Rules
    rule.piecesCount = Config.piecesCount = settings['PiecesCount'] as int? ??
        (specialCountryAndRegion == "Iran" ? 12 : 9);
    rule.flyPieceCount =
        Config.flyPieceCount = settings['FlyPieceCount'] as int? ?? 3;
    rule.piecesAtLeastCount =
        Config.piecesAtLeastCount = settings['PiecesAtLeastCount'] as int? ?? 3;
    rule.hasDiagonalLines = Config.hasDiagonalLines =
        settings['HasDiagonalLines'] as bool? ??
            (specialCountryAndRegion == "Iran");
    rule.hasBannedLocations = Config.hasBannedLocations =
        settings['HasBannedLocations'] as bool? ?? false;
    rule.mayMoveInPlacingPhase = Config.mayMoveInPlacingPhase =
        settings['MayMoveInPlacingPhase'] as bool? ?? false;
    rule.isDefenderMoveFirst = Config.isDefenderMoveFirst =
        settings['IsDefenderMoveFirst'] as bool? ?? false;
    rule.mayRemoveMultiple = Config.mayRemoveMultiple =
        settings['MayRemoveMultiple'] as bool? ?? false;
    rule.mayRemoveFromMillsAlways = Config.mayRemoveFromMillsAlways =
        settings['MayRemoveFromMillsAlways'] as bool? ?? false;
    rule.mayOnlyRemoveUnplacedPieceInPlacingPhase = Config
            .mayOnlyRemoveUnplacedPieceInPlacingPhase =
        settings['MayOnlyRemoveUnplacedPieceInPlacingPhase'] as bool? ?? false;
    rule.isWhiteLoseButNotDrawWhenBoardFull =
        Config.isWhiteLoseButNotDrawWhenBoardFull =
            settings['IsWhiteLoseButNotDrawWhenBoardFull'] as bool? ?? true;
    rule.isLoseButNotChangeSideWhenNoWay =
        Config.isLoseButNotChangeSideWhenNoWay =
            settings['IsLoseButNotChangeSideWhenNoWay'] as bool? ?? true;
    rule.mayFly = Config.mayFly = settings['MayFly'] as bool? ?? true;
    rule.nMoveRule = Config.nMoveRule = settings['NMoveRule'] as int? ?? 100;
    rule.endgameNMoveRule =
        Config.endgameNMoveRule = settings['EndgameNMoveRule'] as int? ?? 100;
    rule.threefoldRepetitionRule = Config.threefoldRepetitionRule =
        settings['ThreefoldRepetitionRule'] as bool? ?? true;

    settingsLoaded = true;
   debugPrint("[config] Loading settings done!");
  }

  static Future<bool> save() async {
    final settings = await Settings.instance();

    settings['IsPrivacyPolicyAccepted'] = Config.isPrivacyPolicyAccepted;

    // Preferences
    settings['ToneEnabled'] = Config.toneEnabled;
    settings['KeepMuteWhenTakingBack'] = Config.keepMuteWhenTakingBack;
    settings['ScreenReaderSupport'] = Config.screenReaderSupport;
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
    settings['Algorithm'] = Config.algorithm;
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
    settings['PieceHighlightColor'] = Config.pieceHighlightColor;
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
    settings['MayOnlyRemoveUnplacedPieceInPlacingPhase'] =
        Config.mayOnlyRemoveUnplacedPieceInPlacingPhase;
    settings['IsWhiteLoseButNotDrawWhenBoardFull'] =
        Config.isWhiteLoseButNotDrawWhenBoardFull;
    settings['IsLoseButNotChangeSideWhenNoWay'] =
        Config.isLoseButNotChangeSideWhenNoWay;
    settings['MayFly'] = Config.mayFly;
    settings['NMoveRule'] = Config.nMoveRule;
    settings['EndgameNMoveRule'] = Config.endgameNMoveRule;
    settings['ThreefoldRepetitionRule'] = Config.threefoldRepetitionRule;

    settings.commit();

    return true;
  }
}
