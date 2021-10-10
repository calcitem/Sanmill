import 'package:flutter/material.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/common/constants.dart';
import 'package:sanmill/shared/theme/colors.dart';

class AppTheme {
  const AppTheme._();
  // TODO: restructure theming. Some theme Elements should be accessed via Theme.of(context)

  // Theme data
  static final lightThemeData = ThemeData(
    primarySwatch: AppTheme.appPrimaryColor,
    brightness: Brightness.light,
  );

  static final darkThemeData = ThemeData(
    primarySwatch: AppTheme.appPrimaryColor,
    brightness: Brightness.dark,
  );

  // Color
  static const appPrimaryColor = Colors.green; // Appbar & Dialog button
  static const dialogTitleColor = appPrimaryColor;

  /// Game page
  static Color boardBackgroundColor = UIColors.burlyWood;
  static Color mainToolbarBackgroundColor = UIColors.burlyWood;
  static Color navigationToolbarBackgroundColor = UIColors.burlyWood;
  static Color boardLineColor = const Color(0x996D000D);
  static Color whitePieceColor = const Color.fromARGB(0xFF, 0xFF, 0xFF, 0xFF);
  static Color whitePieceBorderColor =
      const Color.fromARGB(0xFF, 0x66, 0x00, 0x00);
  static Color blackPieceColor = const Color.fromARGB(0xFF, 0x00, 0x00, 0x00);
  static Color blackPieceBorderColor =
      const Color.fromARGB(0xFF, 0x22, 0x22, 0x22);
  static Color pieceHighlightColor = Colors.red;
  static Color messageColor = Colors.white;
  static Color banColor =
      const Color.fromARGB(0xFF, 0xFF, 0x00, 0x00); // unused
  static Color banBorderColor =
      const Color.fromARGB(0x80, 0xFF, 0x00, 0x00); // unused
  static Color mainToolbarIconColor = listTileSubtitleColor;
  static Color navigationToolbarIconColor = listTileSubtitleColor;
  static Color toolbarTextColor = mainToolbarIconColor;
  static Color moveHistoryTextColor = Colors.yellow;
  static Color moveHistoryDialogBackgroundColor = Colors.transparent;
  static Color infoDialogBackgroundColor = moveHistoryDialogBackgroundColor;
  static Color infoTextColor = moveHistoryTextColor;
  static Color simpleDialogOptionTextColor = Colors.yellow;

  /// Settings page
  static Color darkBackgroundColor = UIColors.crusoe;
  static Color lightBackgroundColor = UIColors.papayaWhip;
  static Color listTileSubtitleColor = const Color(0x99461220);
  static Color listItemDividerColor = const Color(0x336D000D);
  static Color switchListTileActiveColor = dialogTitleColor;
  static Color switchListTileTitleColor = UIColors.crusoe;
  static Color cardColor = UIColors.floralWhite;
  static Color settingsHeaderTextColor = UIColors.crusoe;

  /// Help page
  static Color helpBackgroundColor = boardBackgroundColor;
  static Color helpTextColor = boardBackgroundColor;

  /// About
  static Color aboutPageBackgroundColor = lightBackgroundColor;

  /// Drawer
  static Color drawerColor = Colors.white;
  static Color drawerBackgroundColor =
      UIColors.notWhite.withOpacity(0.5); // TODO
  static Color drawerHighlightItemColor =
      UIColors.freeSpeechGreen.withOpacity(0.2);
  static Color drawerDividerColor = UIColors.grey.withOpacity(0.6);
  static Color drawerBoxerShadowColor = UIColors.grey.withOpacity(0.6);
  static Color drawerTextColor = UIColors.nearlyBlack;
  static Color drawerHighlightTextColor = UIColors.nearlyBlack;
  static Color exitTextColor = UIColors.nearlyBlack;
  static Color drawerIconColor = drawerTextColor;
  static Color drawerHighlightIconColor = drawerHighlightTextColor;
  static Color drawerAnimationIconColor = Colors.white;
  static Color exitIconColor = Colors.red;
  static Color drawerSplashColor =
      Colors.grey.withOpacity(0.1); // TODO: no use?
  static Color drawerHighlightColor = Colors.transparent; // TODO: no use?
  static Color navigationHomeScreenBackgroundColor =
      UIColors.nearlyWhite; // TODO: no use?

  // Theme

  static const sliderThemeData = SliderThemeData(
    trackHeight: 20,
    activeTrackColor: Colors.green,
    inactiveTrackColor: Colors.grey,
    disabledActiveTrackColor: Colors.yellow,
    disabledInactiveTrackColor: Colors.cyan,
    activeTickMarkColor: Colors.black,
    inactiveTickMarkColor: Colors.green,
    //overlayColor: Colors.yellow,
    overlappingShapeStrokeColor: Colors.black,
    //overlayShape: RoundSliderOverlayShape(),
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

  static TextStyle simpleDialogOptionTextStyle = TextStyle(
    fontSize: Config.fontSize + 4.0,
    color: AppTheme.simpleDialogOptionTextColor,
  );

  static TextStyle moveHistoryTextStyle = TextStyle(
    fontSize: Config.fontSize + 2.0,
    height: 1.5,
    color: moveHistoryTextColor,
  );

  static double boardTop = isLargeScreen ? 75.0 : 36.0;
  static double boardMargin = 10.0;
  static double boardScreenPaddingH = 10.0;
  static double boardBorderRadius = 5.0;
  static double boardPadding = 5.0;

  static TextStyle settingsHeaderStyle =
      TextStyle(color: settingsHeaderTextColor, fontSize: Config.fontSize + 4);

  static TextStyle settingsTextStyle = TextStyle(fontSize: Config.fontSize);

  static const cardMargin = EdgeInsets.symmetric(vertical: 4.0);

  static const double drawerWidth = 250.0;

  static const double sizedBoxHeight = 16.0;

  static double copyrightFontSize = 12;
}
