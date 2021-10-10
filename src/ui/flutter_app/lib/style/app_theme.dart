import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/common/constants.dart';
import 'package:sanmill/style/colors.dart';

class AppTheme {
  AppTheme._();

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
  static const boardBackgroundColor = UIColors.burlyWood;
  static const mainToolbarBackgroundColor = UIColors.burlyWood;
  static const navigationToolbarBackgroundColor = UIColors.burlyWood;
  static const boardLineColor = Color(0x996D000D);
  static const whitePieceColor = Color.fromARGB(0xFF, 0xFF, 0xFF, 0xFF);
  static const whitePieceBorderColor = Color.fromARGB(0xFF, 0x66, 0x00, 0x00);
  static const blackPieceColor = Color.fromARGB(0xFF, 0x00, 0x00, 0x00);
  static const blackPieceBorderColor = Color.fromARGB(0xFF, 0x22, 0x22, 0x22);
  static const pieceHighlightColor = Colors.red;
  static const messageColor = Colors.white;
  static const banColor = Color.fromARGB(0xFF, 0xFF, 0x00, 0x00); // unused
  static const banBorderColor =
      Color.fromARGB(0x80, 0xFF, 0x00, 0x00); // unused
  static const mainToolbarIconColor = listTileSubtitleColor;
  static const navigationToolbarIconColor = listTileSubtitleColor;
  static const toolbarTextColor = mainToolbarIconColor;
  static const moveHistoryTextColor = Colors.yellow;
  static const moveHistoryDialogBackgroundColor = Colors.transparent;
  static const infoDialogBackgroundColor = moveHistoryDialogBackgroundColor;
  static const infoTextColor = moveHistoryTextColor;
  static const simpleDialogOptionTextColor = Colors.yellow;

  /// Settings page
  static const darkBackgroundColor = UIColors.crusoe;
  static const lightBackgroundColor = UIColors.papayaWhip;
  static const listTileSubtitleColor = Color(0x99461220);
  static const listItemDividerColor = Color(0x336D000D);
  static const switchListTileActiveColor = dialogTitleColor;
  static const switchListTileTitleColor = UIColors.crusoe;
  static const cardColor = UIColors.floralWhite;
  static const settingsHeaderTextColor = UIColors.crusoe;

  /// Help page
  static const helpBackgroundColor = boardBackgroundColor;
  static const helpTextColor = boardBackgroundColor;

  /// About
  static const aboutPageBackgroundColor = lightBackgroundColor;

  /// Drawer
  static const drawerColor = Colors.white;
  static final drawerBackgroundColor =
      UIColors.notWhite.withOpacity(0.5); // TODO
  static final drawerHighlightItemColor =
      UIColors.freeSpeechGreen.withOpacity(0.2);
  static final drawerDividerColor = UIColors.grey.withOpacity(0.6);
  static final drawerBoxerShadowColor = UIColors.grey.withOpacity(0.6);
  static const drawerTextColor = UIColors.nearlyBlack;
  static const drawerHighlightTextColor = UIColors.nearlyBlack;
  static const exitTextColor = UIColors.nearlyBlack;
  static const drawerIconColor = drawerTextColor;
  static const drawerHighlightIconColor = drawerHighlightTextColor;
  static const drawerAnimationIconColor = Colors.white;
  static const exitIconColor = Colors.red;
  static final drawerSplashColor =
      Colors.grey.withOpacity(0.1); // TODO: no use?
  static const drawerHighlightColor = Colors.transparent; // TODO: no use?
  static const navigationHomeScreenBackgroundColor =
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

  static double boardTop = isLargeScreen() ? 75.0 : 36.0;
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
