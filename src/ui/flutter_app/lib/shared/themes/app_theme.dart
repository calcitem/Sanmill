// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// app_theme.dart

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../../appearance_settings/models/color_settings.dart';
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
    primary: _appPrimaryColor,
    // Primary color, which has been defined as green in the code
    onPrimary: Colors.white,
    // A color that contrasts significantly with the main color, usually used for text or icons
    primaryContainer: Colors.green.shade700,
    // Dark variant of the main color, used for containers, etc.
    onPrimaryContainer: Colors.white,
    // Color that contrasts with primaryContainer
    secondary: UIColors.spruce,
    // Secondary colors, selectable from your color theme
    onSecondary: Colors.black,
    // A color that contrasts significantly with the secondary color
    secondaryContainer: UIColors.spruce,
    // Dark variant of secondary color
    onSecondaryContainer: Colors.white,
    // Color that contrasts significantly with secondaryContainer
    surface: Colors.white,
    // Surface color, used for cards, backgrounds, etc.
    onSurface: Colors.black,
    // Text or icon color on the background
    error: Colors.red,
    // Error color
    onError: Colors.white, // Text or icon color in error state
    // Other required colors can continue to be defined
  );

  ///Light theme
  static final ThemeData lightThemeData = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _colorScheme,
    // use ColorScheme
    sliderTheme: _sliderThemeData.copyWith(
      activeTrackColor: _colorScheme.primary, // Use colors in ColorScheme
      inactiveTrackColor: _colorScheme.onSurface.withValues(alpha: 0.5),
      thumbColor: _colorScheme.primary,
      // Other slider-related color and style adjustments
    ),
    cardTheme: _cardTheme,
    appBarTheme: appBarTheme.copyWith(
      backgroundColor: _colorScheme.primary, // Use colors from ColorScheme
      titleTextStyle: TextStyle(color: _colorScheme.onPrimary),
      // Other style adjustments related to AppBar
    ),
    textTheme: _textTheme,
    // Adjust the text theme to fit the light background if necessary
    dividerTheme: _dividerTheme,
    switchTheme: _lightSwitchTheme,
    checkboxTheme: _buildCheckboxTheme(_colorScheme),
    radioTheme: _buildRadioTheme(_colorScheme),
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
    colorScheme: _darkColorScheme,
    // Use dark ColorScheme
    sliderTheme: _sliderThemeData.copyWith(
      activeTrackColor: _darkColorScheme.primary,
      inactiveTrackColor: _darkColorScheme.onSurface.withValues(alpha: 0.5),
      thumbColor: _colorScheme.primary,
      // Other slider-related color and style adjustments
    ),
    cardTheme: _cardTheme,
    appBarTheme: appBarTheme.copyWith(
      backgroundColor: _darkColorScheme.primary,
      titleTextStyle: TextStyle(color: _darkColorScheme.onPrimary),
      // Other style adjustments related to AppBar
    ),
    textTheme: _textTheme,
    // Adjust the text theme to fit the dark background if necessary
    dividerTheme: _dividerTheme,
    switchTheme: _darkSwitchTheme,
    checkboxTheme: _buildCheckboxTheme(_darkColorScheme),
    radioTheme: _buildRadioTheme(_darkColorScheme),
    // Other theme settings...
  );

  // Color
  static const MaterialColor _appPrimaryColor =
      Colors.green; // App bar & Dialog button

  // Theme
  static final SliderThemeData _sliderThemeData = SliderThemeData(
    trackHeight: 20,
    // Track
    activeTrackColor: _colorScheme.primary,
    // Use the primary color of ColorScheme
    inactiveTrackColor: _colorScheme.onSurface.withValues(alpha: 0.5),
    // More transparent inactive track color
    thumbColor: _colorScheme.primary,
    // Use Color type color directly
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 1.0),
    // Adjust the slider size
    overlayColor: _colorScheme.primary.withValues(alpha: 0.12),
    // Overlay color during slider operation
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 1.0),
    // Radius of the overlay shape
    valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
    // Shape of the numerical indicator
    valueIndicatorColor: _colorScheme.primary,
    // Color of the numerical indicator
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
    color: _colorScheme.onSurface.withValues(
        alpha:
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
        WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        return _colorScheme.primary; // Use primary color when enabled
      }
      return _colorScheme.onSurface
          .withValues(alpha: 0.5); // Use softer colors in off state
    }),
    trackColor:
        WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        return _colorScheme.primary.withValues(
            alpha: 0.5); // Use translucent primary color in on state
      }
      return _colorScheme.onSurface.withValues(
          alpha: 0.3); // Use a more transparent color in the closed state
    }),
    trackOutlineColor:
        WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return _colorScheme.onSurface
            .withValues(alpha: 0.5); // Use soft colors in disabled state
      }
      return Colors.transparent; // No outer edges in other states
    }),
  );

  static final SwitchThemeData _darkSwitchTheme = SwitchThemeData(
    thumbColor:
        WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return _darkColorScheme.onSurface
            .withValues(alpha: 0.5); // Color in disabled state
      }
      if (states.contains(WidgetState.selected)) {
        return _darkColorScheme
            .primary; // Use the primary color in the on state
      }
      return _darkColorScheme.onSurface
          .withValues(alpha: 0.5); // Closed state color
    }),
    trackColor:
        WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return _darkColorScheme.onSurface
            .withValues(alpha: 0.3); // Track color in disabled state
      }
      if (states.contains(WidgetState.selected)) {
        return _darkColorScheme.primary
            .withValues(alpha: 0.5); // On track color
      }
      return _darkColorScheme.onSurface
          .withValues(alpha: 0.1); // Track color in off state
    }),
    trackOutlineColor:
        WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return _darkColorScheme.onSurface
            .withValues(alpha: 0.5); // Outer line color in disabled state
      }
      return Colors
          .transparent; // Usually there is no need to set the outer edge color
    }),
  );

  static CheckboxThemeData _buildCheckboxTheme(ColorScheme colorScheme) {
    return CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      side: WidgetStateProperty.resolveWith<BorderSide?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.38),
          );
        }
        return BorderSide(
          color: colorScheme.primary,
          width: 2,
        );
      }),
      fillColor:
          WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return Colors.transparent;
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all<Color>(colorScheme.onPrimary),
    );
  }

  static RadioThemeData _buildRadioTheme(ColorScheme colorScheme) {
    return RadioThemeData(
      fillColor:
          WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.38);
        }
        return colorScheme.primary;
      }),
    );
  }

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
  static double boardCornerRadius = DB().displaySettings.boardCornerRadius;
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
      Colors.deepPurple.withValues(alpha: 0.8);

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
  static final Map<ColorTheme, ColorSettings> colorThemes =
      <ColorTheme, ColorSettings>{
    ColorTheme.light: const ColorSettings(),
    ColorTheme.dark: const ColorSettings(
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
      annotationToolbarBackgroundColor: Colors.black,
      annotationToolbarIconColor: UIColors.tahitiGold60,
    ),
    ColorTheme.monochrome: const ColorSettings(
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
      annotationToolbarBackgroundColor: Colors.white,
      annotationToolbarIconColor: Colors.black,
    ),
    ColorTheme.transparentCanvas: const ColorSettings(
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
      annotationToolbarBackgroundColor: Color.fromARGB(0, 255, 255, 255),
      annotationToolbarIconColor: Colors.black,
    ),
    ColorTheme.autumnLeaves: const ColorSettings(
      boardLineColor: Color(0xFF000000),
      // Black
      darkBackgroundColor: Color(0xFF284B3A),
      // Dark Green
      boardBackgroundColor: Color(0xD78B5A3C),
      // Semi-transparent Burnt Sienna
      whitePieceColor: Color(0xFFEAE6C1),
      // Pale Beige
      blackPieceColor: Color(0xFF3C3B3F),
      // Dark Charcoal
      pieceHighlightColor: Color(0x88F08080),
      // Semi-transparent Light Coral
      messageColor: Color(0xFF000000),
      // Black
      drawerColor: Color(0xFF000000),
      // Black
      drawerTextColor: Color(0xFFFFFFFF),
      // White
      drawerHighlightItemColor: Color(0x33FFB6C1),
      // Semi-transparent Light Pink
      mainToolbarBackgroundColor: Color(0xD88B5A3C),
      // Semi-transparent Burnt Sienna
      mainToolbarIconColor: Color(0xFF000000),
      // Black
      navigationToolbarBackgroundColor: Color(0xD58B5A3C),
      // Semi-transparent Burnt Sienna
      navigationToolbarIconColor: Color(0xFF000000),
      // Black
      analysisToolbarBackgroundColor: Color(0xFF8B5A2B),
      // Russet Brown
      analysisToolbarIconColor: Color(0xFFA4A293),
      // Pale Taupe
      annotationToolbarBackgroundColor: Color(0xFF8B5A2B),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.legendaryLand: const ColorSettings(
      boardLineColor: Color(0xFF8FBC8F),
      // Dark Sea Green
      darkBackgroundColor: Color(0xFF8B7355),
      // Cinnamon
      boardBackgroundColor: Color(0xFF8B5A2B),
      // Russet Brown
      whitePieceColor: Color(0xFFB2D8B2),
      // Mint Green
      blackPieceColor: Color(0xFF1A4D6E),
      // Indigo Dye
      pieceHighlightColor: Color(0xFFCD853F),
      // Peru
      messageColor: Color(0xFFF0FFF0),
      // Honeydew
      drawerColor: Color(0xFF2E4D40),
      // Dartmouth Green
      drawerTextColor: Color(0xFFE0EEE0),
      // Nyanza
      drawerHighlightItemColor: Color(0x88355E3B),
      // Semi-transparent Olive Drab
      mainToolbarBackgroundColor: Color(0xFF8B7355),
      // Cinnamon
      mainToolbarIconColor: Color(0xFFF0FFF0),
      // Honeydew
      navigationToolbarBackgroundColor: Color(0xFF8B7355),
      // Cinnamon
      navigationToolbarIconColor: Color(0xFFF0FFF0),
      // Honeydew
      analysisToolbarBackgroundColor: Color(0xFF8B7355),
      // Cinnamon
      analysisToolbarIconColor: Color(0xFFF0FFF0),
      // Honeydew
      annotationToolbarBackgroundColor: Color(0xFF8B7355),
      annotationToolbarIconColor: Color(0xFFF0FFF0),
    ),
    ColorTheme.goldenJade: const ColorSettings(
      boardBackgroundColor: Color(0xFFC89B42),
      // golden
      darkBackgroundColor: Color(0xFFE9E7D7),
      // light beige
      boardLineColor: Color(0xFF496D88),
      // steel blue
      whitePieceColor: Color(0xFFF8F3F6),
      // off-white
      blackPieceColor: Color(0xFF7FE3AF),
      // jade green
      pieceHighlightColor: Color(0xB3009600),
      // semi-transparent deep green
      messageColor: Color(0x62000000),
      // semi-transparent black
      drawerColor: Color(0xFF1C352D),
      // dark green
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x331BFC06),
      // semi-transparent bright green
      mainToolbarBackgroundColor: Color(0xFFE9E7D7),
      // light beige
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFFE9E7D7),
      // light beige
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFFE9E7D7),
      // light beige
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFFE9E7D7),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.forestWood: const ColorSettings(
      boardBackgroundColor: Color(0xFFC19A6B),
      // wood brown
      darkBackgroundColor: Color(0xFF8B5A2B),
      // dark wood brown
      boardLineColor: Color(0xFF4B5320),
      // army green
      whitePieceColor: Color(0xFFEAE6C1),
      // light beige
      blackPieceColor: Color(0xFF3C3B3F),
      // dark gray
      pieceHighlightColor: Color(0x88F08080),
      // semi-transparent light coral
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFF8B5A2B),
      // dark wood brown
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33FFB6C1),
      // semi-transparent light pink
      mainToolbarBackgroundColor: Color(0xFF8B5A2B),
      // dark wood brown
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF8B5A2B),
      // dark wood brown
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF8B5A2B),
      // dark wood brown
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF8B5A2B),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.greenMeadow: const ColorSettings(
      boardBackgroundColor: Color(0xFF9ACD32),
      // yellow-green
      darkBackgroundColor: Color(0xFF006400),
      // dark green
      boardLineColor: Color(0xFF6B8E23),
      // olive green
      whitePieceColor: Color(0xFFF8F8FF),
      // ghost white
      blackPieceColor: Color(0xFF2F4F4F),
      // dark slate gray
      pieceHighlightColor: Color(0xFF70C1B3),
      // sea green
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF006400),
      // dark green
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33B0C4DE),
      // semi-transparent light steel blue
      mainToolbarBackgroundColor: Color(0xFF006400),
      // dark green
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF006400),
      // dark green
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF006400),
      // dark green
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF006400),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.stonyPath: const ColorSettings(
      boardBackgroundColor: Color(0xFFC0C0C0),
      // silver
      darkBackgroundColor: Color(0xFF808080),
      // gray
      boardLineColor: Color(0xFF696969),
      // dim gray
      whitePieceColor: Color(0xFFF5F5F5),
      // white smoke
      blackPieceColor: Color(0xFF2F4F4F),
      // dark slate gray
      pieceHighlightColor: Color(0x88FFA07A),
      // semi-transparent light salmon
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFF808080),
      // gray
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x3399CCFF),
      // semi-transparent sky blue
      mainToolbarBackgroundColor: Color(0xFF808080),
      // gray
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF808080),
      // gray
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF808080),
      // gray
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF808080),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.midnightBlue: const ColorSettings(
      boardBackgroundColor: Color(0xFF162447),
      // midnight blue
      darkBackgroundColor: Color(0xFF1f4068),
      // deep blue
      boardLineColor: Color(0xFFe43f5a),
      // reddish-pink
      whitePieceColor: Color(0xFFf9f7f7),
      // off-white
      blackPieceColor: Color(0xFF8338ec),
      // purple
      pieceHighlightColor: Color(0xFF0000FF),
      // blue
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF1f4068),
      // deep blue
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33D3FF00),
      // semi-transparent bright green
      mainToolbarBackgroundColor: Color(0xFF1f4068),
      // deep blue
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF1f4068),
      // deep blue
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF1f4068),
      // deep blue
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF1f4068),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.greenForest: const ColorSettings(
      boardBackgroundColor: Color(0xFFa9eec2),
      // light green
      darkBackgroundColor: Color(0xFF4DAA4C),
      // forest green
      boardLineColor: Color(0xFF7a9e9f),
      // greenish gray
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFF0a2239),
      // dark blue
      pieceHighlightColor: Color(0x88FF0000),
      // semi-transparent red
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFF4DAA4C),
      // forest green
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33FFB800),
      // semi-transparent orange
      mainToolbarBackgroundColor: Color(0xFF4DAA4C),
      // forest green
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF4DAA4C),
      // forest green
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF4DAA4C),
      // forest green
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF4DAA4C),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.pastelPink: const ColorSettings(
      boardBackgroundColor: Color(0xFFf7bacf),
      // pastel pink
      darkBackgroundColor: Color(0xFFefc3e6),
      // light pink
      boardLineColor: Color(0xFFa95c5c),
      // brownish pink
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFF000000),
      // black
      pieceHighlightColor: Colors.red,
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFFa95c5c),
      // brownish pink
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33FFA500),
      // semi-transparent orange
      mainToolbarBackgroundColor: Color(0xFFefc3e6),
      // light pink
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFFefc3e6),
      // light pink
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFFefc3e6),
      // light pink
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFFefc3e6),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.turquoiseSea: const ColorSettings(
      boardBackgroundColor: Color(0xFFc9ada1),
      // beige
      darkBackgroundColor: Color(0xFF1f7a8c),
      // dark turquoise
      boardLineColor: Color(0xFFeae2b7),
      // off-white
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFFd9b08c),
      // light brown
      pieceHighlightColor: Color(0xFFADFF2F),
      // green-yellow
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF1f7a8c),
      // dark turquoise
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x66DC143C),
      // semi-transparent crimson
      mainToolbarBackgroundColor: Color(0xFF1f7a8c),
      // dark turquoise
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF1f7a8c),
      // dark turquoise
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF1f7a8c),
      // dark turquoise
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF1f7a8c),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.violetDream: const ColorSettings(
      boardBackgroundColor: Color(0xFF8b77a9),
      // violet
      darkBackgroundColor: Color(0xFF583d72),
      // dark violet
      boardLineColor: Color(0xFFC5A3B5),
      // lavender
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFF000000),
      // black
      pieceHighlightColor: Color(0x88FFD700),
      // semi-transparent gold
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF583d72),
      // dark violet
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x3393C47D),
      // semi-transparent dark sea green
      mainToolbarBackgroundColor: Color(0xFF583d72),
      // dark violet
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF583d72),
      // dark violet
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF583d72),
      // dark violet
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF583d72),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.mintChocolate: const ColorSettings(
      boardBackgroundColor: Color(0xFFA1E8AF),
      // mint
      darkBackgroundColor: Color(0xFF0B3D0B),
      // dark green
      boardLineColor: Color(0xFF8B4513),
      // saddle brown
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFF000000),
      // black
      pieceHighlightColor: Color(0xEEFF69B4),
      // semi-transparent hot pink
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF0B3D0B),
      // dark green
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33F08080),
      // semi-transparent light coral
      mainToolbarBackgroundColor: Color(0xFF0B3D0B),
      // dark green
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF0B3D0B),
      // dark green
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF0B3D0B),
      // dark green
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray

      annotationToolbarBackgroundColor: Color(0xFF0B3D0B),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.skyBlue: const ColorSettings(
      boardBackgroundColor: Color(0xFFD0E1F9),
      // light sky blue
      darkBackgroundColor: Color(0xFF4B89AC),
      // steel blue
      boardLineColor: Color(0xFF1C1C1C),
      // dark gray
      whitePieceColor: Color(0xFFffffff),
      // white
      blackPieceColor: Color(0xFF000000),
      // black
      pieceHighlightColor: Color(0x88FFFF00),
      // semi-transparent yellow
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFF4B89AC),
      // steel blue
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33FFC0CB),
      // semi-transparent pink
      mainToolbarBackgroundColor: Color(0xFF4B89AC),
      // steel blue
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF4B89AC),
      // steel blue
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF4B89AC),
      // steel blue
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF4B89AC),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.playfulGarden: const ColorSettings(
      boardBackgroundColor: Color(0xFFFBE9A6),
      // light yellow
      darkBackgroundColor: Color(0xFF8AC926),
      // bright green
      boardLineColor: Color(0xFF90BE6D),
      // green
      whitePieceColor: Color(0xFFFFFFFF),
      // white
      blackPieceColor: Color(0xFF222831),
      // dark gray
      pieceHighlightColor: Color(0xFFF08080),
      // light coral
      messageColor: Color(0x88000000),
      // semi-transparent black
      drawerColor: Color(0xFF90BE6D),
      // green
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33FFD700),
      // semi-transparent gold
      mainToolbarBackgroundColor: Color(0xFFB8DCAC),
      // light green
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFFB8DCAC),
      // light green
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFFB8DCAC),
      // light green
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFFB8DCAC),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.darkMystery: const ColorSettings(
      boardBackgroundColor: Color(0xFF5C5C5C),
      // dark silver
      darkBackgroundColor: Color(0xFF0F0F0F),
      // almost black
      boardLineColor: Color(0xFF404040),
      // gray
      whitePieceColor: Color(0xFFE0E0E0),
      // very light gray
      blackPieceColor: Color(0xFF1A1A1A),
      // very dark gray
      pieceHighlightColor: Color(0x88C71585),
      // semi-transparent medium violet red
      messageColor: Color(0xFFA4A293),
      // warm gray
      drawerColor: Color(0xFF0F0F0F),
      // almost black
      drawerTextColor: Color(0xFFFFFFFF),
      // white
      drawerHighlightItemColor: Color(0x33F08080),
      // semi-transparent light coral
      mainToolbarBackgroundColor: Color(0xFF0F0F0F),
      // almost black
      mainToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      navigationToolbarBackgroundColor: Color(0xFF0F0F0F),
      // almost black
      navigationToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      analysisToolbarBackgroundColor: Color(0xFF0F0F0F),
      // almost black
      analysisToolbarIconColor: Color(0xFFA4A293),
      // warm gray
      annotationToolbarBackgroundColor: Color(0xFF0F0F0F),
      annotationToolbarIconColor: Color(0xFFA4A293),
    ),
    ColorTheme.ancientEgypt: const ColorSettings(
      boardBackgroundColor: Color(0xFFE8D0AA),
      // Sandy background resembling papyrus
      darkBackgroundColor: Color(0xFF7E5C31),
      // Deep brown like ancient tombs
      boardLineColor: Color(0xFF3D2A18),
      // Dark brown for hieroglyphic-like lines
      whitePieceColor: Color(0xFFFCF4D9),
      // Off-white like ancient limestone
      blackPieceColor: Color(0xFF2D4150),
      // Deep blue like lapis lazuli
      pieceHighlightColor: Color(0xFFD4AF37),
      // Gold highlight for royal pieces
      messageColor: Color(0xFF3D2A18),
      // Match boardLineColor for readability
      drawerColor: Color(0xFF7E5C31),
      // Match dark background
      drawerTextColor: Color(0xFFFCF4D9),
      // Match whitePieceColor
      drawerHighlightItemColor: Color(0x33D4AF37),
      // Semi-transparent gold
      mainToolbarBackgroundColor: Color(0xFF7E5C31),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFCF4D9),
      // Match white piece color
      navigationToolbarBackgroundColor: Color(0xFF7E5C31),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFCF4D9),
      // Match white piece color
      analysisToolbarBackgroundColor: Color(0xFF7E5C31),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFCF4D9),
      // Match white piece color
      annotationToolbarBackgroundColor: Color(0xFF7E5C31),
      annotationToolbarIconColor: Color(0xFFFCF4D9),
    ),
    ColorTheme.gothicIce: const ColorSettings(
      boardBackgroundColor: Color(0xFFE8F4FC),
      // Icy light blue background
      darkBackgroundColor: Color(0xFF1A2C42),
      // Dark blue, almost black like night sky
      boardLineColor: Color(0xFF264D73),
      // Deep blue lines
      whitePieceColor: Color(0xFFF0F7FF),
      // Snow white
      blackPieceColor: Color(0xFF0D1F2D),
      // Dark night blue
      pieceHighlightColor: Color(0xFFA1D6E6),
      // Match dark background
      messageColor: Color(0xFFA1D6E6),
      // Match board line color
      drawerColor: Color(0xFF1A2C42),
      // Match dark background
      drawerTextColor: Color(0xFFF0F7FF),
      // Match white piece
      drawerHighlightItemColor: Color(0x33A1D6E6),
      // Semi-transparent highlight
      mainToolbarBackgroundColor: Color(0xFF1A2C42),
      // Match dark background
      mainToolbarIconColor: Color(0xFFA1D6E6),
      // Cyan icons
      navigationToolbarBackgroundColor: Color(0xFF1A2C42),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFA1D6E6),
      // Cyan icons
      analysisToolbarBackgroundColor: Color(0xFF1A2C42),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFA1D6E6),
      // Cyan icons
      annotationToolbarBackgroundColor: Color(0xFF1A2C42),
      annotationToolbarIconColor: Color(0xFFA1D6E6),
    ),
    ColorTheme.riceField: const ColorSettings(
      boardBackgroundColor: Color(0xFFF0E9D2),
      // Light wheat color like dry rice
      darkBackgroundColor: Color(0xFF678D58),
      // Green like rice paddies
      boardLineColor: Color(0xFF4A593D),
      // Darker green for field divisions
      whitePieceColor: Color(0xFFF7F3E8),
      // White like polished rice
      blackPieceColor: Color(0xFF33290A),
      // Dark brown like fertile soil
      pieceHighlightColor: Color(0xFFEACC62),
      // Gold like ripe rice
      messageColor: Color(0xFF4A593D),
      // Match board line color
      drawerColor: Color(0xFF678D58),
      // Match dark background
      drawerTextColor: Color(0xFFF7F3E8),
      // Match white piece
      drawerHighlightItemColor: Color(0x33EACC62),
      // Semi-transparent gold
      mainToolbarBackgroundColor: Color(0xFF678D58),
      // Match dark background
      mainToolbarIconColor: Color(0xFFF7F3E8),
      // White icons
      navigationToolbarBackgroundColor: Color(0xFF678D58),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFF7F3E8),
      // White icons
      analysisToolbarBackgroundColor: Color(0xFF678D58),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFF7F3E8),
      // White icons
      annotationToolbarBackgroundColor: Color(0xFF678D58),
      annotationToolbarIconColor: Color(0xFFF7F3E8),
    ),
    ColorTheme.chinesePorcelain: const ColorSettings(
      boardBackgroundColor: Color(0xFFF6FEFF),
      // White porcelain background
      darkBackgroundColor: Color(0xFF0F5E87),
      // Deep blue like traditional porcelain
      boardLineColor: Color(0xFF13426B),
      // Slightly darker blue for definition
      whitePieceColor: Color(0xFFFCFCFC),
      // Bright white
      blackPieceColor: Color(0xFF003366),
      // Deep cobalt blue
      pieceHighlightColor: Color(0xFF52B2BF),
      // Match dark background
      messageColor: Color(0xFFFCFCFC),
      // Match board line color
      drawerColor: Color(0xFF0F5E87),
      // Match dark background
      drawerTextColor: Color(0xFFFCFCFC),
      // Match white piece
      drawerHighlightItemColor: Color(0x3352B2BF),
      // Semi-transparent turquoise
      mainToolbarBackgroundColor: Color(0xFF0F5E87),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFCFCFC),
      // White icons
      navigationToolbarBackgroundColor: Color(0xFF0F5E87),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFCFCFC),
      // White icons
      analysisToolbarBackgroundColor: Color(0xFF0F5E87),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFCFCFC),
      // White icons
      annotationToolbarBackgroundColor: Color(0xFF0F5E87),
      annotationToolbarIconColor: Color(0xFFFCFCFC),
    ),
    ColorTheme.desertDusk: const ColorSettings(
      boardBackgroundColor: Color(0xFFF0C18B),
      // Sandy orange background
      darkBackgroundColor: Color(0xFF6A3E35),
      // Deep brown like desert mountains at dusk
      boardLineColor: Color(0xFF4A2C28),
      // Darker brown for definition
      whitePieceColor: Color(0xFFFEEBC1),
      // Cream like desert sand
      blackPieceColor: Color(0xFF42283D),
      // Deep purple like dusk sky
      pieceHighlightColor: Color(0xFFE36161),
      // Match dark background
      messageColor: Color(0xFFFEEBC1),
      // Match board line color
      drawerColor: Color(0xFF6A3E35),
      // Match dark background
      drawerTextColor: Color(0xFFFEEBC1),
      // Match white piece
      drawerHighlightItemColor: Color(0x33E36161),
      // Semi-transparent sunset
      mainToolbarBackgroundColor: Color(0xFF6A3E35),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFEEBC1),
      // Light sand colored icons
      navigationToolbarBackgroundColor: Color(0xFF6A3E35),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFEEBC1),
      // Light sand colored icons
      analysisToolbarBackgroundColor: Color(0xFF6A3E35),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFEEBC1),
      // Light sand colored icons
      annotationToolbarBackgroundColor: Color(0xFF6A3E35),
      annotationToolbarIconColor: Color(0xFFFEEBC1),
    ),
    ColorTheme.precisionCraft: const ColorSettings(
      boardBackgroundColor: Color(0xFFEEEEEE),
      // Clean light gray background representing precision
      darkBackgroundColor: Color(0xFF333333),
      // Dark anthracite representing industrial efficiency
      boardLineColor: Color(0xFF222222),
      // Strong black lines for clarity and structure
      whitePieceColor: Color(0xFFF8F8F8),
      // Pure white for contrast and cleanliness
      blackPieceColor: Color(0xFF1A1A1A),
      // Deep black for maximum contrast
      pieceHighlightColor: Color(0xFFDD0000),
      // Match dark background
      messageColor: Color(0xFFF8F8F8),
      // Dark text for readability
      drawerColor: Color(0xFF333333),
      // Match dark background
      drawerTextColor: Color(0xFFF8F8F8),
      // Match white piece
      drawerHighlightItemColor: Color(0x33FFCC00),
      // Semi-transparent gold (from German flag)
      mainToolbarBackgroundColor: Color(0xFF333333),
      // Match dark background
      mainToolbarIconColor: Color(0xFFF8F8F8),
      // Light icons on dark background
      navigationToolbarBackgroundColor: Color(0xFF333333),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFF8F8F8),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF333333),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFF8F8F8),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF333333),
      annotationToolbarIconColor: Color(0xFFF8F8F8),
    ),
    ColorTheme.folkEmbroidery: const ColorSettings(
      boardBackgroundColor: Color(0xFFF5F2E9),
      // Natural linen color like traditional fabric
      darkBackgroundColor: Color(0xFF7E4E3B),
      // Rich brown like wooden furniture
      boardLineColor: Color(0xFF6B3E26),
      // Darker brown for embroidery outlines
      whitePieceColor: Color(0xFFFFFCF0),
      // Cream like natural fabric
      blackPieceColor: Color(0xFF2B0F06),
      // Deep brown almost black
      pieceHighlightColor: Color(0xFFD92121),
      // Match dark background
      messageColor: Color(0xFFFFFCF0),
      // Match board line color
      drawerColor: Color(0xFF7E4E3B),
      // Match dark background
      drawerTextColor: Color(0xFFFFFCF0),
      // Match white piece
      drawerHighlightItemColor: Color(0x3345A145),
      // Semi-transparent green (from Hungarian folklore)
      mainToolbarBackgroundColor: Color(0xFF7E4E3B),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFFFCF0),
      // Light icons for contrast
      navigationToolbarBackgroundColor: Color(0xFF7E4E3B),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFFFCF0),
      // Light icons for contrast
      analysisToolbarBackgroundColor: Color(0xFF7E4E3B),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFFFCF0),
      // Light icons for contrast
      annotationToolbarBackgroundColor: Color(0xFF7E4E3B),
      annotationToolbarIconColor: Color(0xFFFFFCF0),
    ),
    ColorTheme.carpathianHeritage: const ColorSettings(
      boardBackgroundColor: Color(0xFFF2E8D5),
      // Natural wool color
      darkBackgroundColor: Color(0xFF2C4770),
      // Deep blue like Carpathian night sky
      boardLineColor: Color(0xFF1F3356),
      // Darker blue for definition
      whitePieceColor: Color(0xFFF9F0DD),
      // Cream like sheep's wool
      blackPieceColor: Color(0xFF231F20),
      // Deep charcoal
      pieceHighlightColor: Color(0xFFCE1126),
      // Match dark background
      messageColor: Color(0xFFF9F0DD),
      // Match board line color
      drawerColor: Color(0xFF2C4770),
      // Match dark background
      drawerTextColor: Color(0xFFF9F0DD),
      // Match white piece
      drawerHighlightItemColor: Color(0x33FCD116),
      // Semi-transparent yellow (from Romanian flag)
      mainToolbarBackgroundColor: Color(0xFF2C4770),
      // Match dark background
      mainToolbarIconColor: Color(0xFFF9F0DD),
      // Light colored icons
      navigationToolbarBackgroundColor: Color(0xFF2C4770),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFF9F0DD),
      // Light colored icons
      analysisToolbarBackgroundColor: Color(0xFF2C4770),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFF9F0DD),
      // Light colored icons
      annotationToolbarBackgroundColor: Color(0xFF2C4770),
      annotationToolbarIconColor: Color(0xFFF9F0DD),
    ),
    ColorTheme.imperialGrandeur: const ColorSettings(
      boardBackgroundColor: Color(0xFFF5E7C1),
      // Golden beige like imperial parchment
      darkBackgroundColor: Color(0xFF2A1E5C),
      // Deep imperial purple
      boardLineColor: Color(0xFF1A1240),
      // Darker purple for definition
      whitePieceColor: Color(0xFFF8F3E3),
      // Ivory like imperial marble
      blackPieceColor: Color(0xFF0F0A26),
      // Deep blue-black
      pieceHighlightColor: Color(0xFFD4AF37),
      // Match dark background
      messageColor: Color(0xFFD4AF37),
      // Match board line color
      drawerColor: Color(0xFF2A1E5C),
      // Match dark background
      drawerTextColor: Color(0xFFF8F3E3),
      // Match white piece
      drawerHighlightItemColor: Color(0x33CC0000),
      // Semi-transparent red
      mainToolbarBackgroundColor: Color(0xFF2A1E5C),
      // Match dark background
      mainToolbarIconColor: Color(0xFFD4AF37),
      // Gold icons for imperial feel
      navigationToolbarBackgroundColor: Color(0xFF2A1E5C),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFD4AF37),
      // Gold icons
      analysisToolbarBackgroundColor: Color(0xFF2A1E5C),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFD4AF37),
      // Gold icons
      annotationToolbarBackgroundColor: Color(0xFF2A1E5C),
      annotationToolbarIconColor: Color(0xFFD4AF37),
    ),
    ColorTheme.bohemianCrystal: const ColorSettings(
      boardBackgroundColor: Color(0xFFE6F2FF),
      // Light blue like crystal reflection
      darkBackgroundColor: Color(0xFF16456D),
      // Deep blue like traditional glassware
      boardLineColor: Color(0xFF0F2F4C),
      // Darker blue like crystal facets
      whitePieceColor: Color(0xFFF7FBFF),
      // Icy white like polished crystal
      blackPieceColor: Color(0xFF05172A),
      // Deep navy
      pieceHighlightColor: Color(0xFF9E0812),
      // Match dark background
      messageColor: Color(0xFFF7FBFF),
      // Match board line color
      drawerColor: Color(0xFF16456D),
      // Match dark background
      drawerTextColor: Color(0xFFF7FBFF),
      // Match white piece
      drawerHighlightItemColor: Color(0x3311457E),
      // Semi-transparent blue
      mainToolbarBackgroundColor: Color(0xFF16456D),
      // Match dark background
      mainToolbarIconColor: Color(0xFFF7FBFF),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF16456D),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFF7FBFF),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF16456D),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFF7FBFF),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF16456D),
      annotationToolbarIconColor: Color(0xFFF7FBFF),
    ),
    ColorTheme.savannaSunrise: const ColorSettings(
      boardBackgroundColor: Color(0xFFF2E4C0),
      // Savanna sand color
      darkBackgroundColor: Color(0xFF4A5E2F),
      // Deep grass green
      boardLineColor: Color(0xFF374825),
      // Darker green like shadows in tall grass
      whitePieceColor: Color(0xFFFFF8E1),
      // Cream like animal bone
      blackPieceColor: Color(0xFF24281A),
      // Deep dark green almost black
      pieceHighlightColor: Color(0xFFE05D00),
      // Match dark background
      messageColor: Color(0xFFFFF8E1),
      // Match board line color
      drawerColor: Color(0xFF4A5E2F),
      // Match dark background
      drawerTextColor: Color(0xFFFFF8E1),
      // Match white piece
      drawerHighlightItemColor: Color(0x33F1C40F),
      // Semi-transparent yellow like African sun
      mainToolbarBackgroundColor: Color(0xFF4A5E2F),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFFF8E1),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF4A5E2F),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFFF8E1),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF4A5E2F),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFFF8E1),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF4A5E2F),
      annotationToolbarIconColor: Color(0xFFFFF8E1),
    ),
    ColorTheme.harmonyBalance: const ColorSettings(
      boardBackgroundColor: Color(0xFFF3F0E9),
      // Natural paper color
      darkBackgroundColor: Color(0xFF263959),
      // Deep indigo blue like traditional pottery
      boardLineColor: Color(0xFF17263B),
      // Darker blue for definition
      whitePieceColor: Color(0xFFFAF9F5),
      // Off-white like rice paper
      blackPieceColor: Color(0xFF0C1525),
      // Deep navy almost black
      pieceHighlightColor: Color(0xFFE63946),
      // Match dark background
      messageColor: Color(0xFFFAF9F5),
      // Match board line color
      drawerColor: Color(0xFF263959),
      // Match dark background
      drawerTextColor: Color(0xFFFAF9F5),
      // Match white piece
      drawerHighlightItemColor: Color(0x33F9B42D),
      // Semi-transparent gold
      mainToolbarBackgroundColor: Color(0xFF263959),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFAF9F5),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF263959),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFAF9F5),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF263959),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFAF9F5),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF263959),
      annotationToolbarIconColor: Color(0xFFFAF9F5),
    ),
    ColorTheme.cinnamonSpice: const ColorSettings(
      boardBackgroundColor: Color(0xFFE8D0B8),
      // Light cinnamon color
      darkBackgroundColor: Color(0xFF5B4B3B),
      // Deep brown like cinnamon bark
      boardLineColor: Color(0xFF3C2F23),
      // Darker brown for definition
      whitePieceColor: Color(0xFFFBF5EB),
      // Cream white like coconut
      blackPieceColor: Color(0xFF231C14),
      // Deep brown almost black
      pieceHighlightColor: Color(0xFF6AA168),
      // Match dark background
      messageColor: Color(0xFFFBF5EB),
      // Match board line color
      drawerColor: Color(0xFF5B4B3B),
      // Match dark background
      drawerTextColor: Color(0xFFFBF5EB),
      // Match white piece
      drawerHighlightItemColor: Color(0x33FF9800),
      // Semi-transparent saffron orange
      mainToolbarBackgroundColor: Color(0xFF5B4B3B),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFBF5EB),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF5B4B3B),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFBF5EB),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF5B4B3B),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFBF5EB),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF5B4B3B),
      annotationToolbarIconColor: Color(0xFFFBF5EB),
    ),
    ColorTheme.anatolianMosaic: const ColorSettings(
      boardBackgroundColor: Color(0xFFF1EEEA),
      // Marble white like traditional stone
      darkBackgroundColor: Color(0xFF1E5F8C),
      // Turkish blue like Iznik pottery
      boardLineColor: Color(0xFF1A4A6E),
      // Darker blue for definition
      whitePieceColor: Color(0xFFFAF6F0),
      // Cream white like limestone
      blackPieceColor: Color(0xFF0A2638),
      // Deep blue-black
      pieceHighlightColor: Color(0xFFD81B60),
      // Match dark background
      messageColor: Color(0xFFFAF6F0),
      // Match board line color
      drawerColor: Color(0xFF1E5F8C),
      // Match dark background
      drawerTextColor: Color(0xFFFAF6F0),
      // Match white piece
      drawerHighlightItemColor: Color(0x33E5A836),
      // Semi-transparent gold like mosaic inlays
      mainToolbarBackgroundColor: Color(0xFF1E5F8C),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFAF6F0),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF1E5F8C),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFAF6F0),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF1E5F8C),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFAF6F0),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF1E5F8C),
      annotationToolbarIconColor: Color(0xFFFAF6F0),
    ),
    ColorTheme.carnivalSpirit: const ColorSettings(
      boardBackgroundColor: Color(0xFFFFF59B),
      // Bright yellow like carnival costumes
      darkBackgroundColor: Color(0xFF026873),
      // Tropical teal blue
      boardLineColor: Color(0xFF01535E),
      // Darker teal for definition
      whitePieceColor: Color(0xFFFFFDEC),
      // Cream white
      blackPieceColor: Color(0xFF012E34),
      // Deep teal almost black
      pieceHighlightColor: Color(0xFFFF5757),
      // Match dark background
      messageColor: Color(0xFFFFFDEC),
      // Match board line color
      drawerColor: Color(0xFF026873),
      // Match dark background
      drawerTextColor: Color(0xFFFFFDEC),
      // Match white piece
      drawerHighlightItemColor: Color(0x3376FF03),
      // Semi-transparent lime green
      mainToolbarBackgroundColor: Color(0xFF026873),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFFFDEC),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF026873),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFFFDEC),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF026873),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFFFDEC),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF026873),
      annotationToolbarIconColor: Color(0xFFFFFDEC),
    ),
    ColorTheme.spiceMarket: const ColorSettings(
      boardBackgroundColor: Color(0xFFF9E2B8),
      // Warm turmeric yellow board
      darkBackgroundColor: Color(0xFF9B2335),
      // Deep burgundy background like dried chili
      boardLineColor: Color(0xFF6F1D1B),
      // Dark maroon lines
      whitePieceColor: Color(0xFFFFFFEB),
      // Ivory pieces like coconut flesh
      blackPieceColor: Color(0xFF2E0E02),
      // Deep brown like cloves
      pieceHighlightColor: Color(0xFF00A550),
      // Bright green like fresh curry leaves
      messageColor: Color(0xFFFFEDBD),
      // Light cream like ghee
      drawerColor: Color(0xFF9B2335),
      // Match dark background
      drawerTextColor: Color(0xFFFFEDBD),
      // Match message color
      drawerHighlightItemColor: Color(0x33F9B529),
      // Semi-transparent saffron gold
      mainToolbarBackgroundColor: Color(0xFF9B2335),
      // Match dark background
      mainToolbarIconColor: Color(0xFFFFEDBD),
      // Light icons
      navigationToolbarBackgroundColor: Color(0xFF9B2335),
      // Match dark background
      navigationToolbarIconColor: Color(0xFFFFEDBD),
      // Light icons
      analysisToolbarBackgroundColor: Color(0xFF9B2335),
      // Match dark background
      analysisToolbarIconColor: Color(0xFFFFEDBD),
      // Light icons
      annotationToolbarBackgroundColor: Color(0xFF9B2335),
      annotationToolbarIconColor: Color(0xFFFFEDBD),
    ),
    ColorTheme.custom: const ColorSettings(),
  };

  /// Updates the custom theme in the colorThemes map
  static void updateCustomTheme(ColorSettings settings) {
    // Since colorThemes is a final map, we need to use runtime support to modify it
    colorThemes[ColorTheme.custom] = settings;
  }
}

enum ColorTheme {
  current,
  light,
  dark,
  monochrome,
  transparentCanvas,
  autumnLeaves,
  legendaryLand,
  goldenJade,
  forestWood,
  greenMeadow,
  stonyPath,
  midnightBlue,
  greenForest,
  pastelPink,
  turquoiseSea,
  violetDream,
  mintChocolate,
  skyBlue,
  playfulGarden,
  darkMystery,
  ancientEgypt,
  gothicIce,
  riceField,
  chinesePorcelain,
  desertDusk,
  precisionCraft,
  folkEmbroidery,
  carpathianHeritage,
  imperialGrandeur,
  bohemianCrystal,
  savannaSunrise,
  harmonyBalance,
  cinnamonSpice,
  anatolianMosaic,
  carnivalSpirit,
  spiceMarket,
  custom,
}
