import 'package:flutter/material.dart';
import 'package:sanmill/style/colors.dart';

class AppTheme {
  AppTheme._();

  // Color

  static var appPrimaryColor = Colors.green; // Appbar & Dialog button
  static var dialogTitleColor = appPrimaryColor;

  /// Game page
  static var gamePageHeaderIconColor = Colors.white;
  static var tipTextColor = Colors.white;
  static var boardBackgroundColor = UIColors.burlyWood;
  static var boardLineColor = Color(0x996D000D);
  static var blackPieceColor = Color.fromARGB(0xFF, 0x00, 0x00, 0x00);
  static var blackPieceBorderColor = Color.fromARGB(0xFF, 0x22, 0x22, 0x22);
  static var whitePieceColor = Color.fromARGB(0xFF, 0xFF, 0xFF, 0xFF);
  static var whitePieceBorderColor = Color.fromARGB(0xFF, 0x66, 0x00, 0x00);
  static var banColor = Color.fromARGB(0xFF, 0xFF, 0x00, 0x00); // unused
  static var banBorderColor = Color.fromARGB(0x80, 0xFF, 0x00, 0x00); // unused
  static var toolbarIconColor = listTileSubtitleColor;
  static var toolbarTextColor = toolbarIconColor;
  static var moveHistoryTextColor = Colors.yellow;
  static var moveHistoryDialogBackgroundColor = Colors.transparent;
  static var hintDialogackgroundColor = moveHistoryDialogBackgroundColor;
  static var hintTextColor = moveHistoryTextColor;

  /// Settings page
  static var darkBackgroundColor = UIColors.crusoe;
  static var lightBackgroundColor = UIColors.papayaWhip;
  static var listTileSubtitleColor = Color(0x99461220);
  static var listItemDividerColor = Color(0x336D000D);

  /// Help page
  static var helpBackgroundColor = boardBackgroundColor;
  static var helpTextColor = boardBackgroundColor;

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
  static var drawerHightlightColor = Colors.transparent; // TODO: no use?
  static var navigationHomeScreenBackgroundColor =
      UIColors.nearlyWhite; // TODO: no use?

  static const animatedTextsColors = [
    Colors.black,
    Colors.blue,
    Colors.yellow,
    Colors.red,
  ];

  // Style

  static var gamePageTipStyle = TextStyle(fontSize: 16, color: tipTextColor);

  static const cardColor = UIColors.floralWhite;
  static const cardMargin =
      const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0);

  static const settingsHeaderStyle =
      TextStyle(color: UIColors.crusoe, fontSize: 20.0);

  static var switchListTileActiveColor = dialogTitleColor;
  static var switchListTileTitleStyle = TextStyle(color: UIColors.crusoe);

  static var moveHistoryTextStyle =
      TextStyle(fontSize: 18, height: 1.5, color: moveHistoryTextColor);

  static var aboutPageBackgroundColor = lightBackgroundColor;

  static double copyrightFontSize = 12;
  static var versionDialogAppNameTextStyle = TextStyle(color: dialogTitleColor);
  static var versionDialogCopyrightTextStyle = TextStyle(
    fontSize: AppTheme.copyrightFontSize,
  );

  static double boardBorderRadius = 5;
  static var boardPadding = 5.0;

  static const double drawerWidth = 250;

  static double boardMargin = 10.0;
  static var boardScreenPaddingH = 10.0;

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

  // Misc
  static const SizedBox sizedBox = SizedBox(height: 16);
}
