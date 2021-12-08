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

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/theme/colors.dart';

/// The Apps Theme
@immutable
class AppTheme {
  const AppTheme._();

  // TODO: [Leptopoda] when using a base theme the darkMode is somehow broken ¿?

  /// light theme
  static final lightThemeData = ThemeData(
    brightness: Brightness.light,
    primarySwatch: _appPrimaryColor,
    sliderTheme: _sliderThemeData,
    textTheme: _textTheme,
    dividerColor: _listItemDividerColor,
    cardTheme: _cardTheme,
    dividerTheme: _dividerTheme,
  );

  /// dark theme
  static final darkThemeData = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: _appPrimaryColor,
    toggleableActiveColor: _appPrimaryColor,
    sliderTheme: _sliderThemeData,
    textTheme: _textTheme,
    dividerColor: _listItemDividerColor,
    cardTheme: _cardTheme,
    dividerTheme: _dividerTheme,
  );

  // Color
  static const _appPrimaryColor = Colors.green; // App bar & Dialog button

  // Theme
  static const _sliderThemeData = SliderThemeData(
    trackHeight: 20,
    activeTrackColor: Colors.green,
    inactiveTrackColor: Colors.grey,
    disabledActiveTrackColor: Colors.yellow,
    disabledInactiveTrackColor: Colors.cyan,
    activeTickMarkColor: Colors.black,
    inactiveTickMarkColor: Colors.green,
    overlappingShapeStrokeColor: Colors.black,
    valueIndicatorColor: Colors.green,
    showValueIndicator: ShowValueIndicator.always,
    minThumbSeparation: 100,
    thumbShape: RoundSliderThumbShape(
      enabledThumbRadius: 2.0,
      disabledThumbRadius: 1.0,
    ),
    rangeTrackShape: RoundedRectRangeSliderTrackShape(),
    tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 2.0),
    valueIndicatorTextStyle: TextStyle(fontSize: 24),
  );

  static const _dividerTheme = DividerThemeData(
    indent: 16,
    endIndent: 16,
    space: 1.0,
    thickness: 1.0,
  );

  static const _cardTheme = CardTheme(
    margin: EdgeInsets.symmetric(vertical: 4.0),
    color: _cardColor,
  );

  static final _textTheme = TextTheme(
    bodyText2: TextStyle(
      fontSize: LocalDatabaseService.display.fontSize,
    ),
  );

  static FeedbackThemeData feedbackTheme = FeedbackThemeData(
    activeFeedbackModeColor: _appPrimaryColor,
  );

  static TextStyle simpleDialogOptionTextStyle = TextStyle(
    fontSize: LocalDatabaseService.display.fontSize + 4.0,
    color: _simpleDialogOptionTextColor,
  );

  static TextStyle moveHistoryTextStyle = TextStyle(
    fontSize: LocalDatabaseService.display.fontSize + 2.0,
    height: 1.5,
    color: _moveHistoryTextColor,
  );

  static TextStyle drawerHeaderTextStyle = TextStyle(
    fontSize: LocalDatabaseService.display.fontSize + 16,
    fontWeight: FontWeight.w600,
  );

  static TextStyle dialogTitleTextStyle = TextStyle(
    fontSize: LocalDatabaseService.display.fontSize + 4,
    color: _appPrimaryColor,
  );

  static const TextStyle copyrightTextStyle = TextStyle(
    fontSize: _copyrightFontSize,
  );

  static final TextStyle notationTextStyle = TextStyle(
    fontSize: 20,
    color: LocalDatabaseService.colorSettings.boardLineColor,
  );

  static const listTileSubtitleStyle = TextStyle(
    color: listTileSubtitleColor,
  );

  static const listTileTitleStyle = TextStyle(
    color: _switchListTileTitleColor,
  );

  static final mainToolbarTextStyle = TextStyle(
    color: LocalDatabaseService.colorSettings.mainToolbarIconColor,
  );

  static const helpTextStyle = TextStyle(
    color: helpTextColor,
  );

  static const licenseTextStyle = TextStyle(
    fontFamily: "Monospace",
    fontSize: 12,
  );

  static const double boardMargin = 10.0;
  static const double boardScreenPaddingH = 10.0;
  static const double boardBorderRadius = 5.0;
  static const double boardPadding = 5.0;

  static TextStyle settingsHeaderStyle = TextStyle(
    color: _settingsHeaderTextColor,
    fontSize: LocalDatabaseService.display.fontSize + 4,
  );

  static TextStyle settingsTextStyle = TextStyle(
    fontSize: LocalDatabaseService.display.fontSize,
  );

  static const double sizedBoxHeight = 16.0;

  static const double _copyrightFontSize = 12;

  /// Game page
  static const Color _moveHistoryTextColor = Colors.yellow;
  static const Color _simpleDialogOptionTextColor = Colors.yellow;
  static const Color whitePieceBorderColor = Color(0xFF660000);
  static const Color blackPieceBorderColor = Color(0xFF222222);
  static const Color moveHistoryDialogBackgroundColor = Colors.transparent;
  static const Color infoDialogBackgroundColor = Colors.transparent;

  /// Settings page
  static const Color _listItemDividerColor = Color(0x336D000D);
  static const Color _switchListTileTitleColor = UIColors.crusoe;
  static const Color _cardColor = UIColors.floralWhite;
  static const Color _settingsHeaderTextColor = UIColors.crusoe;
  static const Color lightBackgroundColor = UIColors.papayaWhip;
  static const Color listTileSubtitleColor = Color(0x99461220);

  /// Help page
  static const Color helpTextColor = UIColors.burlyWood;

  /// About
  static const Color aboutPageBackgroundColor = UIColors.papayaWhip;

  /// Drawer
  static const Color drawerDividerColor = Color(0x993A5160);
  static const Color drawerBoxerShadowColor = Color(0x993A5160);
  // TODO: [Leptopdoa] actually store the theme and not the color
  static const Color drawerAnimationIconColor = Colors.white;
  static const Color drawerSplashColor = Color(0X1A9E9E9E);
}
