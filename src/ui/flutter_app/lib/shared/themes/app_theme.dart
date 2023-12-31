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

  static final ColorScheme _colorScheme = ColorScheme(
    //Color configuration of light theme
    brightness: Brightness.light,
    primary:
        _appPrimaryColor, // Primary color, which has been defined as green in the code
    onPrimary: Colors
        .white, // A color that contrasts significantly with the main color, usually used for text or icons
    primaryContainer: Colors.green
        .shade700, // Dark variant of the main color, used for containers, etc.
    onPrimaryContainer:
        Colors.white, // Color that contrasts with primaryContainer
    secondary:
        UIColors.spruce, // Secondary colors, selectable from your color theme
    onSecondary: Colors
        .black, // A color that contrasts significantly with the secondary color
    secondaryContainer: UIColors.spruce, // Dark variant of secondary color
    onSecondaryContainer: Colors
        .white, // Color that contrasts significantly with secondaryContainer
    surface: Colors.white, // Surface color, used for cards, backgrounds, etc.
    onSurface: Colors.black, // Text or icon color on the surface
    background: Colors.white, // background color
    onBackground: Colors.black, // Text or icon color on the background
    error: Colors.red, // Error color
    onError: Colors.white, // Text or icon color in error state
    // Other required colors can continue to be defined
  );

  ///Light theme
  static final ThemeData lightThemeData = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _colorScheme, // use ColorScheme
    sliderTheme: _sliderThemeData.copyWith(
      activeTrackColor: _colorScheme.primary, // Use colors in ColorScheme
      inactiveTrackColor: _colorScheme.onSurface.withOpacity(0.5),
      thumbColor: _colorScheme.primary,
      // Other slider-related color and style adjustments
    ),
    cardTheme: _cardTheme,
    appBarTheme: appBarTheme.copyWith(
      backgroundColor: _colorScheme.primary, // Use colors from ColorScheme
      titleTextStyle: TextStyle(color: _colorScheme.onPrimary),
      // Other style adjustments related to AppBar
    ),
    textTheme:
        _textTheme, // Adjust the text theme to fit the light background if necessary
    dividerTheme: _dividerTheme,
    switchTheme: _lightSwitchTheme,
    // Other theme settings...
  );

  /// Dark theme
  static final ColorScheme _darkColorScheme = _colorScheme.copyWith(
    brightness: Brightness.dark,
    //Adjust colors as needed to fit the dark theme
    // For example, use a darker or lighter color variant
  );

  static final ThemeData darkThemeData = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme, // Use dark ColorScheme
    sliderTheme: _sliderThemeData.copyWith(
      activeTrackColor: _darkColorScheme.primary,
      inactiveTrackColor: _darkColorScheme.onSurface.withOpacity(0.5),
      thumbColor: _colorScheme.primary,
      // Other slider-related color and style adjustments
    ),
    cardTheme: _cardTheme,
    appBarTheme: appBarTheme.copyWith(
      backgroundColor: _darkColorScheme.primary,
      titleTextStyle: TextStyle(color: _darkColorScheme.onPrimary),
      // Other style adjustments related to AppBar
    ),
    textTheme:
        _textTheme, // Adjust the text theme to fit the dark background if necessary
    dividerTheme: _dividerTheme,
    switchTheme: _darkSwitchTheme,
    // Other theme settings...
  );

  // Color
  static const MaterialColor _appPrimaryColor =
      Colors.green; // App bar & Dialog button

  // Theme
  static final SliderThemeData _sliderThemeData = SliderThemeData(
    trackHeight: 20, // Track
    activeTrackColor:
        _colorScheme.primary, // Use the primary color of ColorScheme
    inactiveTrackColor: _colorScheme.onSurface
        .withOpacity(0.5), // More transparent inactive track color
    thumbColor: _colorScheme.primary, // Use Color type color directly
    thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 1.0), // Adjust the slider size
    overlayColor: _colorScheme.primary
        .withOpacity(0.12), // Overlay color during slider operation
    overlayShape: const RoundSliderOverlayShape(
        overlayRadius: 1.0), // Radius of the overlay shape
    valueIndicatorShape:
        const PaddleSliderValueIndicatorShape(), // Shape of the numerical indicator
    valueIndicatorColor:
        _colorScheme.primary, // Color of the numerical indicator
    valueIndicatorTextStyle: const TextStyle(
      color: Colors.white, // Text color of numeric indicator
      fontSize: 24, // text size
    ),
  );

  static final DividerThemeData _dividerTheme = DividerThemeData(
    indent: 16,
    endIndent: 16,
    space: 1.0,
    thickness: 1.0,
    color: _colorScheme.onSurface.withOpacity(
        0.12), //Adjust color transparency according to theme surface color
  );

  static final CardTheme _cardTheme = CardTheme(
    margin: const EdgeInsets.symmetric(vertical: 4.0),
    color: cardColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12), // rounded corner design
    ),
    elevation: 1, // slight shadow effect
  );

  static final SwitchThemeData _lightSwitchTheme = SwitchThemeData(
    thumbColor:
        MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return _colorScheme.primary; // Use primary color when enabled
      }
      return _colorScheme.onSurface
          .withOpacity(0.5); // Use softer colors in off state
    }),
    trackColor:
        MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return _colorScheme.primary
            .withOpacity(0.5); // Use translucent primary color in on state
      }
      return _colorScheme.onSurface
          .withOpacity(0.3); // Use a more transparent color in the closed state
    }),
    trackOutlineColor:
        MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
      if (states.contains(MaterialState.disabled)) {
        return _colorScheme.onSurface
            .withOpacity(0.5); // Use soft colors in disabled state
      }
      return Colors.transparent; // No outer edges in other states
    }),
  );

  static final SwitchThemeData _darkSwitchTheme = SwitchThemeData(
    thumbColor:
        MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
      if (states.contains(MaterialState.disabled)) {
        return _darkColorScheme.onSurface
            .withOpacity(0.5); // Color in disabled state
      }
      if (states.contains(MaterialState.selected)) {
        return _darkColorScheme
            .primary; // Use the primary color in the on state
      }
      return _darkColorScheme.onSurface.withOpacity(0.5); // Closed state color
    }),
    trackColor:
        MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
      if (states.contains(MaterialState.disabled)) {
        return _darkColorScheme.onSurface
            .withOpacity(0.3); // Track color in disabled state
      }
      if (states.contains(MaterialState.selected)) {
        return _darkColorScheme.primary.withOpacity(0.5); // On track color
      }
      return _darkColorScheme.onSurface
          .withOpacity(0.1); // Track color in off state
    }),
    trackOutlineColor:
        MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
      if (states.contains(MaterialState.disabled)) {
        return _darkColorScheme.onSurface
            .withOpacity(0.5); // Outer line color in disabled state
      }
      return Colors
          .transparent; // Usually there is no need to set the outer edge color
    }),
  );

  static final AppBarTheme appBarTheme = AppBarTheme(
    backgroundColor:
        _colorScheme.primary, // Use the primary color of ColorScheme
    titleTextStyle: TextStyle(
      color: _colorScheme
          .onPrimary, // Select color based on primary color contrast
      fontSize: 20.0, // font size
      fontWeight: FontWeight.bold,
    ),
    elevation: 0, // Reduce or remove shadows for a flatter design
    iconTheme: IconThemeData(
      color: _colorScheme
          .onPrimary, // Make the icon the same color as the title text
    ),
    // You may also need to adjust other properties, such as the brightness of the system status bar, etc.
  );

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
    activeFeedbackModeColor: _appPrimaryColor,
  );

  static const BoxDecoration dialogDecoration = BoxDecoration(
    color: UIColors.semiTransparentBlack,
    borderRadius: BorderRadius.all(Radius.circular(28)), // Rounded corners
  );

  static const TextStyle dialogTitleTextStyle = TextStyle(
    color: _appPrimaryColor,
  );

  static final TextStyle notationTextStyle = TextStyle(
    color: DB().colorSettings.boardLineColor,
    fontSize: AppTheme.textScaler.scale(20),
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
    ),
  };
}
