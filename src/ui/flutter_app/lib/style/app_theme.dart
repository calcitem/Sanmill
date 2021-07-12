import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/style/colors.dart';

class AppTheme {
  AppTheme._();

  // Color

  static var appPrimaryColor = Colors.green; // Appbar & Dialog button
  static var dialogTitleColor = appPrimaryColor;

  /// Game page
  static var gamePageHeaderIconColor = Colors.white;
  static var boardBackgroundColor = UIColors.burlyWood;
  static var boardLineColor = Color(0x996D000D);
  static var blackPieceColor = Color.fromARGB(0xFF, 0x00, 0x00, 0x00);
  static var blackPieceBorderColor = Color.fromARGB(0xFF, 0x22, 0x22, 0x22);
  static var whitePieceColor = Color.fromARGB(0xFF, 0xFF, 0xFF, 0xFF);
  static var whitePieceBorderColor = Color.fromARGB(0xFF, 0x66, 0x00, 0x00);
  static var messageColor = Colors.white;
  static var banColor = Color.fromARGB(0xFF, 0xFF, 0x00, 0x00); // unused
  static var banBorderColor = Color.fromARGB(0x80, 0xFF, 0x00, 0x00); // unused
  static var toolbarIconColor = listTileSubtitleColor;
  static var toolbarTextColor = toolbarIconColor;
  static var moveHistoryTextColor = Colors.yellow;
  static var moveHistoryDialogBackgroundColor = Colors.transparent;
  static var infoDialogBackgroundColor = moveHistoryDialogBackgroundColor;
  static var infoTextColor = moveHistoryTextColor;
  static var simpleDialogOptionTextColor = Colors.yellow;

  /// Settings page
  static var darkBackgroundColor = UIColors.crusoe;
  static var lightBackgroundColor = UIColors.papayaWhip;
  static var listTileSubtitleColor = Color(0x99461220);
  static var listItemDividerColor = Color(0x336D000D);
  static var switchListTileActiveColor = dialogTitleColor;
  static var switchListTileTitleColor = UIColors.crusoe;
  static const cardColor = UIColors.floralWhite;
  static const settingsHeaderTextColor = UIColors.crusoe;

  /// Help page
  static var helpBackgroundColor = boardBackgroundColor;
  static var helpTextColor = boardBackgroundColor;

  /// About
  static var aboutPageBackgroundColor = lightBackgroundColor;

  /// Drawer
  static var drawerColor = Colors.white;
  static var drawerBackgroundColor = UIColors.notWhite.withOpacity(0.5); // TODO
  static var drawerHighlightItemColor =
      UIColors.freeSpeechGreen.withOpacity(0.2);
  static var drawerDividerColor = UIColors.grey.withOpacity(0.6);
  static var drawerBoxerShadowColor = UIColors.grey.withOpacity(0.6);
  static var drawerTextColor = UIColors.nearlyBlack;
  static var drawerHighlightTextColor = UIColors.nearlyBlack;
  static var exitTextColor = UIColors.nearlyBlack;
  static var drawerIconColor = drawerTextColor;
  static var drawerHighlightIconColor = drawerHighlightTextColor;
  static var drawerAnimationIconColor = Colors.white;
  static var exitIconColor = Colors.red;
  static var drawerSplashColor = Colors.grey.withOpacity(0.1); // TODO: no use?
  static var drawerHighlightColor = Colors.transparent; // TODO: no use?
  static var navigationHomeScreenBackgroundColor =
      UIColors.nearlyWhite; // TODO: no use?

  static const animatedTextsColors = [
    Colors.black,
    Colors.blue,
    Colors.yellow,
    Colors.red,
  ];

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
        enabledThumbRadius: 2.0, disabledThumbRadius: 1.0),
    rangeTrackShape: RoundedRectRangeSliderTrackShape(),
    tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 2.0),
    valueIndicatorTextStyle: TextStyle(fontSize: 24),
  );

  static var simpleDialogOptionTextStyle = TextStyle(
    fontSize: Config.fontSize + 4.0,
    color: AppTheme.simpleDialogOptionTextColor,
  );

  static var moveHistoryTextStyle = TextStyle(
      fontSize: Config.fontSize + 2.0,
      height: 1.5,
      color: moveHistoryTextColor);

  static double boardTop = 75.0;
  static double boardMargin = 10.0;
  static double boardScreenPaddingH = 10.0;
  static double boardBorderRadius = 5.0;
  static double boardPadding = 5.0;

  static var settingsHeaderStyle =
      TextStyle(color: settingsHeaderTextColor, fontSize: Config.fontSize + 4);

  static var settingsTextStyle = TextStyle(fontSize: Config.fontSize);

  static const cardMargin =
      const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0);

  static const double drawerWidth = 250.0;

  static const double sizedBoxHeight = 16.0;

  static double copyrightFontSize = 12;
}
