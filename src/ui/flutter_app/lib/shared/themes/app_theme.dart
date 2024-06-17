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

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/widgets/appearance_settings_page.dart';
import '../database/database.dart';
import 'ui_colors.dart';

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




  static const TextTheme _textTheme = TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32.0,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.25, // Add appropriate letter spacing
    ),
    titleMedium: TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15, // Add appropriate letter spacing
    ),
    bodyMedium: TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w400, // Consider using regular font weights
      letterSpacing: 0.5, // Add appropriate letter spacing
    ),
    // You can add more text styles as needed, such as bodySmall, labelLarge, etc.
  );

  static FeedbackThemeData feedbackTheme = FeedbackThemeData(
  );

  static const BoxDecoration dialogDecoration = BoxDecoration(
    color: UIColors.semiTransparentBlack,
    borderRadius: BorderRadius.all(Radius.circular(28)), // Rounded corners
  );

  static const TextStyle dialogTitleTextStyle = TextStyle(
  );

  static const TextStyle listTileSubtitleStyle = TextStyle(
    color: listTileSubtitleColor,
    fontSize: 16,
  );

  static const TextStyle listTileTitleStyle = TextStyle(
    color: _switchListTileTitleColor,
  );

  static final TextStyle mainToolbarTextStyle = TextStyle(
    color: DB().colorSettings.mainToolbarIconColor,
  );

  static const TextStyle helpTextStyle = TextStyle(
    color: helpTextColor,
    fontSize: 20,
  );

  static const double smallFontSize = 14.0;
  static const double defaultFontSize = 16.0;
  static const double largeFontSize = 20.0;
  static const double extraLargeFontSize = 24.0;
  static const double hugeFontSize = 28.0;
  static const double giantFontSize = 32.0;

  static TextScaler textScaler =
      TextScaler.linear(DB().displaySettings.fontScale);

  static const double boardMargin = 10.0;
  static const double boardBorderRadius = 5.0;
  static late double boardPadding;
  static const double sizedBoxHeight = 16.0;

  static const double drawerItemHeight = 46.0;
  static const double drawerItemPadding = 8.0;
  static const double drawerItemPaddingSmallScreen = 3.0;

  /// Game page
  static const Color whitePieceBorderColor = UIColors.rosewood;
  static const Color blackPieceBorderColor = UIColors.darkJungleGreen;
  static const Color moveHistoryDialogBackgroundColor = Colors.transparent;
  static const Color infoDialogBackgroundColor = Colors.transparent;
  static const Color modalBottomSheetBackgroundColor = Colors.transparent;
  static const Color gamePageActionSheetTextColor = Colors.yellow;
  static Color gamePageActionSheetTextBackgroundColor =
      Colors.deepPurple.withOpacity(0.8);

  /// Settings page
  static const Color listItemDividerColor = UIColors.rosewood20;
  static const Color _switchListTileTitleColor = UIColors.spruce;
  static const Color cardColor = UIColors.floralWhite;
  static const Color settingsHeaderTextColor = UIColors.spruce;
  static const Color lightBackgroundColor = UIColors.papayaWhip;
  static const Color listTileSubtitleColor = UIColors.cocoaBean60;

  /// Help page
  static const Color helpTextColor = UIColors.burlyWood;

  /// About
  static const Color aboutPageBackgroundColor = UIColors.papayaWhip;

  /// Drawer
  static const Color drawerDividerColor = UIColors.riverBed60;
  static const Color drawerBoxerShadowColor = UIColors.riverBed60;

  static const Color drawerAnimationIconColor = UIColors.seashell;
  static const Color drawerSplashColor = UIColors.starDust10;

  /// Color themes
  // ignore_for_file: avoid_redundant_argument_values
  static const Map<ColorTheme, ColorSettings> colorThemes =
      <ColorTheme, ColorSettings>{
    ColorTheme.light: ColorSettings(),
    ColorTheme.dark: ColorSettings(
      boardLineColor: UIColors.osloGrey,
      darkBackgroundColor: Colors.black,
      boardBackgroundColor: Colors.black,
      whitePieceColor: UIColors.citrus,
      blackPieceColor: UIColors.butterflyBlue,
      pieceHighlightColor: Colors.white,
      messageColor: UIColors.tahitiGold,
      drawerColor: Colors.black,
      drawerTextColor: Colors.white,
      drawerHighlightItemColor: UIColors.highlighterGreen20,
      mainToolbarBackgroundColor: Colors.black,
      mainToolbarIconColor: UIColors.tahitiGold60,
      navigationToolbarBackgroundColor: Colors.black,
      navigationToolbarIconColor: UIColors.tahitiGold60,
      analysisToolbarBackgroundColor: Colors.black,
      analysisToolbarIconColor: UIColors.tahitiGold60,
    ),
    ColorTheme.monochrome: ColorSettings(
      boardLineColor: Colors.black,
      darkBackgroundColor: Colors.white,
      boardBackgroundColor: Colors.white,
      whitePieceColor: Colors.white,
      blackPieceColor: Colors.black,
      pieceHighlightColor: Colors.black,
      messageColor: Colors.black,
      drawerColor: Colors.black,
      drawerTextColor: Colors.white,
      drawerHighlightItemColor: Color(0xFFA4A293),
      mainToolbarBackgroundColor: Colors.white,
      mainToolbarIconColor: Colors.black,
      navigationToolbarBackgroundColor: Colors.white,
      navigationToolbarIconColor: Colors.black,
      analysisToolbarBackgroundColor: Colors.white,
      analysisToolbarIconColor: Colors.black,
    ),
    ColorTheme.transparentCanvas: ColorSettings(
      boardLineColor: Colors.black,
      // Background color with minimal opacity (1/255) to prevent saved images
      // from being completely black
      darkBackgroundColor: Color.fromARGB(1, 255, 255, 255),
      boardBackgroundColor: Color.fromARGB(1, 255, 255, 255),
      messageColor: Colors.black,
      mainToolbarBackgroundColor: Color.fromARGB(0, 255, 255, 255),
      mainToolbarIconColor: Colors.black,
      navigationToolbarBackgroundColor: Color.fromARGB(0, 255, 255, 255),
      navigationToolbarIconColor: Colors.black,
      analysisToolbarBackgroundColor: Color.fromARGB(0, 255, 255, 255),
      analysisToolbarIconColor: Colors.black,
    ),
    ColorTheme.goldenJade: ColorSettings(
      boardBackgroundColor: Color(0xFFC89B42), // golden
      darkBackgroundColor: Color(0xFFE9E7D7), // light beige
      boardLineColor: Color(0xFF496D88), // steel blue
      whitePieceColor: Color(0xFFF8F3F6), // off-white
      blackPieceColor: Color(0xFF7FE3AF), // jade green
      pieceHighlightColor: Color(0xB3009600), // semi-transparent deep green
      messageColor: Color(0x62000000), // semi-transparent black
      drawerColor: Color(0xFF1C352D), // dark green
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x331BFC06), // semi-transparent bright green
      mainToolbarBackgroundColor: Color(0xFFE9E7D7), // light beige
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFFE9E7D7), // light beige
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFFE9E7D7), // light beige
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.forestWood: ColorSettings(
      boardBackgroundColor: Color(0xFFC19A6B), // wood brown
      darkBackgroundColor: Color(0xFF8B5A2B), // dark wood brown
      boardLineColor: Color(0xFF4B5320), // army green
      whitePieceColor: Color(0xFFEAE6C1), // light beige
      blackPieceColor: Color(0xFF3C3B3F), // dark gray
      pieceHighlightColor: Color(0x88F08080), // semi-transparent light coral
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFF8B5A2B), // dark wood brown
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x33FFB6C1), // semi-transparent light pink
      mainToolbarBackgroundColor: Color(0xFF8B5A2B), // dark wood brown
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF8B5A2B), // dark wood brown
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF8B5A2B), // dark wood brown
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.greenMeadow: ColorSettings(
      boardBackgroundColor: Color(0xFF9ACD32), // yellow-green
      darkBackgroundColor: Color(0xFF006400), // dark green
      boardLineColor: Color(0xFF6B8E23), // olive green
      whitePieceColor: Color(0xFFF8F8FF), // ghost white
      blackPieceColor: Color(0xFF2F4F4F), // dark slate gray
      pieceHighlightColor: Color(0xFF70C1B3), // sea green
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF006400), // dark green
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x33B0C4DE), // semi-transparent light steel blue
      mainToolbarBackgroundColor: Color(0xFF006400), // dark green
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF006400), // dark green
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF006400), // dark green
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.stonyPath: ColorSettings(
      boardBackgroundColor: Color(0xFFC0C0C0), // silver
      darkBackgroundColor: Color(0xFF808080), // gray
      boardLineColor: Color(0xFF696969), // dim gray
      whitePieceColor: Color(0xFFF5F5F5), // white smoke
      blackPieceColor: Color(0xFF2F4F4F), // dark slate gray
      pieceHighlightColor: Color(0x88FFA07A), // semi-transparent light salmon
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFF808080), // gray
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x3399CCFF), // semi-transparent sky blue
      mainToolbarBackgroundColor: Color(0xFF808080), // gray
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF808080), // gray
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF808080), // gray
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.midnightBlue: ColorSettings(
      boardBackgroundColor: Color(0xFF162447), // midnight blue
      darkBackgroundColor: Color(0xFF1f4068), // deep blue
      boardLineColor: Color(0xFFe43f5a), // reddish-pink
      whitePieceColor: Color(0xFFf9f7f7), // off-white
      blackPieceColor: Color(0xFF8338ec), // purple
      pieceHighlightColor: Color(0xFF0000FF), // blue
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF1f4068), // deep blue
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x33D3FF00), // semi-transparent bright green
      mainToolbarBackgroundColor: Color(0xFF1f4068), // deep blue
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF1f4068), // deep blue
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF1f4068), // deep blue
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.greenForest: ColorSettings(
      boardBackgroundColor: Color(0xFFa9eec2), // light green
      darkBackgroundColor: Color(0xFF4DAA4C), // forest green
      boardLineColor: Color(0xFF7a9e9f), // greenish gray
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFF0a2239), // dark blue
      pieceHighlightColor: Color(0x88FF0000), // semi-transparent red
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFF4DAA4C), // forest green
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x33FFB800), // semi-transparent orange
      mainToolbarBackgroundColor: Color(0xFF4DAA4C), // forest green
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF4DAA4C), // forest green
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF4DAA4C), // forest green
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.pastelPink: ColorSettings(
      boardBackgroundColor: Color(0xFFf7bacf), // pastel pink
      darkBackgroundColor: Color(0xFFefc3e6), // light pink
      boardLineColor: Color(0xFFa95c5c), // brownish pink
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFF000000), // black
      pieceHighlightColor: Colors.red,
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFFa95c5c), // brownish pink
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x33FFA500), // semi-transparent orange
      mainToolbarBackgroundColor: Color(0xFFefc3e6), // light pink
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFFefc3e6), // light pink
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFFefc3e6), // light pink
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.turquoiseSea: ColorSettings(
      boardBackgroundColor: Color(0xFFc9ada1), // beige
      darkBackgroundColor: Color(0xFF1f7a8c), // dark turquoise
      boardLineColor: Color(0xFFeae2b7), // off-white
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFFd9b08c), // light brown
      pieceHighlightColor: Color(0xFFADFF2F), // green-yellow
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF1f7a8c), // dark turquoise
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x66DC143C), // semi-transparent crimson
      mainToolbarBackgroundColor: Color(0xFF1f7a8c), // dark turquoise
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF1f7a8c), // dark turquoise
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF1f7a8c), // dark turquoise
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.violetDream: ColorSettings(
      boardBackgroundColor: Color(0xFF8b77a9), // violet
      darkBackgroundColor: Color(0xFF583d72), // dark violet
      boardLineColor: Color(0xFFC5A3B5), // lavender
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFF000000), // black
      pieceHighlightColor: Color(0x88FFD700), // semi-transparent gold
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF583d72), // dark violet
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x3393C47D), // semi-transparent dark sea green
      mainToolbarBackgroundColor: Color(0xFF583d72), // dark violet
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF583d72), // dark violet
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF583d72), // dark violet
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.mintChocolate: ColorSettings(
      boardBackgroundColor: Color(0xFFA1E8AF), // mint
      darkBackgroundColor: Color(0xFF0B3D0B), // dark green
      boardLineColor: Color(0xFF8B4513), // saddle brown
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFF000000), // black
      pieceHighlightColor: Color(0xEEFF69B4), // semi-transparent hot pink
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF0B3D0B), // dark green
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x33F08080), // semi-transparent light coral
      mainToolbarBackgroundColor: Color(0xFF0B3D0B), // dark green
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF0B3D0B), // dark green
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF0B3D0B), // dark green
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.skyBlue: ColorSettings(
      boardBackgroundColor: Color(0xFFD0E1F9), // light sky blue
      darkBackgroundColor: Color(0xFF4B89AC), // steel blue
      boardLineColor: Color(0xFF1C1C1C), // dark gray
      whitePieceColor: Color(0xFFffffff), // white
      blackPieceColor: Color(0xFF000000), // black
      pieceHighlightColor: Color(0x88FFFF00), // semi-transparent yellow
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFF4B89AC), // steel blue
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x33FFC0CB), // semi-transparent pink
      mainToolbarBackgroundColor: Color(0xFF4B89AC), // steel blue
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF4B89AC), // steel blue
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF4B89AC), // steel blue
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.playfulGarden: ColorSettings(
      boardBackgroundColor: Color(0xFFFBE9A6), // light yellow
      darkBackgroundColor: Color(0xFF8AC926), // bright green
      boardLineColor: Color(0xFF90BE6D), // green
      whitePieceColor: Color(0xFFFFFFFF), // white
      blackPieceColor: Color(0xFF222831), // dark gray
      pieceHighlightColor: Color(0xFFF08080), // light coral
      messageColor: Color(0x88000000), // semi-transparent black
      drawerColor: Color(0xFF90BE6D), // green
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor: Color(0x33FFD700), // semi-transparent gold
      mainToolbarBackgroundColor: Color(0xFFB8DCAC), // light green
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFFB8DCAC), // light green
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFFB8DCAC), // light green
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
    ColorTheme.darkMystery: ColorSettings(
      boardBackgroundColor: Color(0xFF5C5C5C), // dark silver
      darkBackgroundColor: Color(0xFF0F0F0F), // almost black
      boardLineColor: Color(0xFF404040), // gray
      whitePieceColor: Color(0xFFE0E0E0), // very light gray
      blackPieceColor: Color(0xFF1A1A1A), // very dark gray
      pieceHighlightColor:
          Color(0x88C71585), // semi-transparent medium violet red
      messageColor: Color(0xFFA4A293), // warm gray
      drawerColor: Color(0xFF0F0F0F), // almost black
      drawerTextColor: Color(0xFFFFFFFF), // white
      drawerHighlightItemColor:
          Color(0x33F08080), // semi-transparent light coral
      mainToolbarBackgroundColor: Color(0xFF0F0F0F), // almost black
      mainToolbarIconColor: Color(0xFFA4A293), // warm gray
      navigationToolbarBackgroundColor: Color(0xFF0F0F0F), // almost black
      navigationToolbarIconColor: Color(0xFFA4A293), // warm gray
      analysisToolbarBackgroundColor: Color(0xFF0F0F0F), // almost black
      analysisToolbarIconColor: Color(0xFFA4A293), // warm gray
    ),
  };
}
