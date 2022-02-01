// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/shared/theme/colors.dart';

/// The Apps Theme
///
/// Before introducing a new [TextStyle] please have a look at the ones we have in the current [TextTheme].
///
/// ```
/// NAME         SIZE  WEIGHT  SPACING
/// headline1    96.0  light   -1.5
/// headline2    60.0  light   -0.5
/// headline3    48.0  regular  0.0
/// headline4    34.0  regular  0.25
/// headline5    24.0  regular  0.0
/// headline6    20.0  medium   0.15
/// subtitle1    16.0  regular  0.15
/// subtitle2    14.0  medium   0.1
/// body1        16.0  regular  0.5   (bodyText1)
/// body2        14.0  regular  0.25  (bodyText2)
/// button       14.0  medium   1.25
/// caption      12.0  regular  0.4
/// overline     10.0  regular  1.5
/// ```
@immutable
class AppTheme {
  const AppTheme._();

  /// Light theme
  static final lightThemeData = ThemeData(
    brightness: Brightness.light,
    primarySwatch: _appPrimaryColor,
    sliderTheme: _sliderThemeData,
    dividerColor: _listItemDividerColor,
    cardTheme: _cardTheme,
    dividerTheme: _dividerTheme,
  );

  /// Dark theme
  static final darkThemeData = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: _appPrimaryColor,
    toggleableActiveColor: _appPrimaryColor,
    sliderTheme: _sliderThemeData,
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

  static FeedbackThemeData feedbackTheme = FeedbackThemeData(
    activeFeedbackModeColor: _appPrimaryColor,
  );

  static const TextStyle dialogTitleTextStyle = TextStyle(
    color: _appPrimaryColor,
  );

  static final TextStyle notationTextStyle = TextStyle(
    fontSize: 20,
    color: DB().colorSettings.boardLineColor,
  );

  static const listTileSubtitleStyle = TextStyle(
    color: listTileSubtitleColor,
  );

  static const listTileTitleStyle = TextStyle(
    color: _switchListTileTitleColor,
  );

  static final mainToolbarTextStyle = TextStyle(
    color: DB().colorSettings.mainToolbarIconColor,
  );

  static const helpTextStyle = TextStyle(
    color: helpTextColor,
  );

  static const double boardMargin = 10.0;
  static const double boardBorderRadius = 5.0;
  static const double boardPadding = 25.0;
  static const double sizedBoxHeight = 16.0;

  /// Game page
  static const Color whitePieceBorderColor = Color(0xFF660000);
  static const Color blackPieceBorderColor = Color(0xFF222222);
  static const Color moveHistoryDialogBackgroundColor = Colors.transparent;
  static const Color infoDialogBackgroundColor = Colors.transparent;
  static const Color gamePageActionSheetTextColor = Colors.yellow;

  /// Settings page
  static const Color _listItemDividerColor = Color(0x336D000D);
  static const Color _switchListTileTitleColor = UIColors.crusoe;
  static const Color _cardColor = UIColors.floralWhite;
  static const Color settingsHeaderTextColor = UIColors.crusoe;
  static const Color lightBackgroundColor = UIColors.papayaWhip;
  static const Color listTileSubtitleColor = Color(0x99461220);

  /// Help page
  static const Color helpTextColor = UIColors.burlyWood;

  /// About
  static const Color aboutPageBackgroundColor = UIColors.papayaWhip;

  /// Drawer
  static const Color drawerDividerColor = Color(0x993A5160);
  static const Color drawerBoxerShadowColor = Color(0x993A5160);
  // TODO: [Leptopoda] Actually store the theme and not the color
  static const Color drawerAnimationIconColor = Colors.white;
  static const Color drawerSplashColor = Color(0X1A9E9E9E);
}
