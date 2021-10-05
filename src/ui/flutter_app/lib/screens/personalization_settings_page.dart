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

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/screens/settings/settings_card.dart';
import 'package:sanmill/screens/settings/settings_list_tile.dart';
import 'package:sanmill/screens/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/common/constants.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class PersonalizationSettingsPage extends StatefulWidget {
  @override
  _PersonalizationSettingsPageState createState() =>
      _PersonalizationSettingsPageState();
}

class _PersonalizationSettingsPageState
    extends State<PersonalizationSettingsPage> {
  // create some values
  Color pickerColor = const Color(0xFF808080);
  Color currentColor = const Color(0xFF808080);

  // ValueChanged<Color> callback
  void changeColor(Color color) {
    setState(() => pickerColor = color);
  }

  Future<void> showColorDialog(String colorString) async {
    final Map<String, int> colorStrToVal = {
      S.of(context).boardColor: Config.boardBackgroundColor,
      S.of(context).backgroundColor: Config.darkBackgroundColor,
      S.of(context).lineColor: Config.boardLineColor,
      S.of(context).whitePieceColor: Config.whitePieceColor,
      S.of(context).blackPieceColor: Config.blackPieceColor,
      S.of(context).pieceHighlightColor: Config.pieceHighlightColor,
      S.of(context).messageColor: Config.messageColor,
      S.of(context).drawerColor: Config.drawerColor,
      S.of(context).drawerBackgroundColor: Config.drawerBackgroundColor,
      S.of(context).drawerTextColor: Config.drawerTextColor,
      S.of(context).drawerHighlightItemColor: Config.drawerHighlightItemColor,
      S.of(context).mainToolbarBackgroundColor:
          Config.mainToolbarBackgroundColor,
      S.of(context).mainToolbarIconColor: Config.mainToolbarIconColor,
      S.of(context).navigationToolbarBackgroundColor:
          Config.navigationToolbarBackgroundColor,
      S.of(context).navigationToolbarIconColor:
          Config.navigationToolbarIconColor,
    };

    final AlertDialog alert = AlertDialog(
      title: Text(
        "${S.of(context).pick} $colorString",
        style: TextStyle(
          fontSize: Config.fontSize + 4,
        ),
      ),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(colorStrToVal[colorString]!),
          onColorChanged: changeColor,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).confirm,
            style: TextStyle(
              fontSize: Config.fontSize,
            ),
          ),
          onPressed: () {
            setState(() => currentColor = pickerColor);

            debugPrint("[config] pickerColor.value: ${pickerColor.value}");

            if (colorString == S.of(context).boardColor) {
              Config.boardBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).backgroundColor) {
              Config.darkBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).lineColor) {
              Config.boardLineColor = pickerColor.value;
            } else if (colorString == S.of(context).whitePieceColor) {
              Config.whitePieceColor = pickerColor.value;
            } else if (colorString == S.of(context).blackPieceColor) {
              Config.blackPieceColor = pickerColor.value;
            } else if (colorString == S.of(context).pieceHighlightColor) {
              Config.pieceHighlightColor = pickerColor.value;
            } else if (colorString == S.of(context).messageColor) {
              Config.messageColor = pickerColor.value;
            } else if (colorString == S.of(context).drawerColor) {
              Config.drawerColor = pickerColor.value;
            } else if (colorString == S.of(context).drawerBackgroundColor) {
              Config.drawerBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).drawerTextColor) {
              Config.drawerTextColor = pickerColor.value;
            } else if (colorString == S.of(context).drawerHighlightItemColor) {
              Config.drawerHighlightItemColor = pickerColor.value;
            } else if (colorString ==
                S.of(context).mainToolbarBackgroundColor) {
              Config.mainToolbarBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).mainToolbarIconColor) {
              Config.mainToolbarIconColor = pickerColor.value;
            } else if (colorString ==
                S.of(context).navigationToolbarBackgroundColor) {
              Config.navigationToolbarBackgroundColor = pickerColor.value;
            } else if (colorString ==
                S.of(context).navigationToolbarIconColor) {
              Config.navigationToolbarIconColor = pickerColor.value;
            }

            Config.save();
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
              fontSize: Config.fontSize,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  SliderTheme _boardBorderLineWidthSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardBorderLineWidth,
        child: Slider(
          value: Config.boardBorderLineWidth,
          max: 20.0,
          divisions: 200,
          label: Config.boardBorderLineWidth.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardBorderLineWidth value: $value");
              Config.boardBorderLineWidth = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setBoardBorderLineWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _boardBorderLineWidthSliderTheme(),
      ),
    );
  }

  SliderTheme _boardInnerLineWidthSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardInnerLineWidth,
        child: Slider(
          value: Config.boardInnerLineWidth,
          max: 20.0,
          divisions: 200,
          label: Config.boardInnerLineWidth.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardInnerLineWidth value: $value");
              Config.boardInnerLineWidth = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setBoardInnerLineWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _boardInnerLineWidthSliderTheme(),
      ),
    );
  }

  SliderTheme _pieceWidthSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).pieceWidth,
        child: Slider(
          value: Config.pieceWidth,
          min: 0.5,
          divisions: 50,
          label: Config.pieceWidth.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] pieceWidth value: $value");
              Config.pieceWidth = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setPieceWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _pieceWidthSliderTheme(),
      ),
    );
  }

  SliderTheme _fontSizeSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).fontSize,
        child: Slider(
          value: Config.fontSize,
          min: 16,
          max: 32,
          divisions: 16,
          label: Config.fontSize.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] fontSize value: $value");
              Config.fontSize = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setFontSize() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _fontSizeSliderTheme(),
      ),
    );
  }

  SliderTheme _boardTopSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardTop,
        child: Slider(
          value: Config.boardTop,
          max: 288.0,
          divisions: 288,
          label: Config.boardTop.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardTop value: $value");
              Config.boardTop = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setBoardTop() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _boardTopSliderTheme(),
      ),
    );
  }

  SliderTheme _animationDurationSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).animationDuration,
        child: Slider(
          value: Config.animationDuration,
          max: 5.0,
          divisions: 50,
          label: Config.animationDuration.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] AnimationDuration value: $value");
              Config.animationDuration = value;
              Config.save();
            });
          },
        ),
      ),
    );
  }

  Future<void> setAnimationDuration() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _animationDurationSliderTheme(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(S.of(context).personalization),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children(context),
        ),
      ),
    );
  }

  List<Widget> children(BuildContext context) {
    Future<void> langCallback([String? langCode]) async {
      debugPrint("[config] languageCode = $langCode");

      Navigator.pop(context);

      setState(() {
        Config.languageCode = langCode ?? Constants.defaultLanguageCodeName;
        S.load(Locale(Resources.of().languageCode));
      });

      debugPrint("[config] Config.languageCode: ${Config.languageCode}");

      Config.save();
    }

    return <Widget>[
      Text(S.of(context).display, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).language,
            trailingString:
                Config.languageCode != Constants.defaultLanguageCodeName
                    ? languageCodeToStrings[Config.languageCode]!.languageName
                    : "",
            onTap: () => setLanguage(context, langCallback),
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.isPieceCountInHandShown,
            onChanged: setIsPieceCountInHandShown,
            titleString: S.of(context).isPieceCountInHandShown,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.isNotationsShown,
            onChanged: setIsNotationsShown,
            titleString: S.of(context).isNotationsShown,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.isHistoryNavigationToolbarShown,
            onChanged: setIsHistoryNavigationToolbarShown,
            titleString: S.of(context).isHistoryNavigationToolbarShown,
          ),
          SettingsListTile(
            titleString: S.of(context).boardBorderLineWidth,
            onTap: setBoardBorderLineWidth,
          ),
          SettingsListTile(
            titleString: S.of(context).boardInnerLineWidth,
            onTap: setBoardInnerLineWidth,
          ),
          SettingsListTile(
            titleString: S.of(context).pieceWidth,
            onTap: setPieceWidth,
          ),
          SettingsListTile(
            titleString: S.of(context).fontSize,
            onTap: setFontSize,
          ),
          SettingsListTile(
            titleString: S.of(context).boardTop,
            onTap: setBoardTop,
          ),
          SettingsListTile(
            titleString: S.of(context).animationDuration,
            onTap: setAnimationDuration,
          ),
          SettingsSwitchListTile(
            context: context,
            value: Config.standardNotationEnabled,
            onChanged: setStandardNotationEnabled,
            titleString: S.of(context).standardNotation,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).color, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).boardColor,
            trailingColor: Config.boardBackgroundColor,
            onTap: () => showColorDialog(S.of(context).boardColor),
          ),
          SettingsListTile(
            titleString: S.of(context).backgroundColor,
            trailingColor: Config.darkBackgroundColor,
            onTap: () => showColorDialog(S.of(context).backgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).lineColor,
            trailingColor: Config.boardLineColor,
            onTap: () => showColorDialog(S.of(context).lineColor),
          ),
          SettingsListTile(
            titleString: S.of(context).whitePieceColor,
            trailingColor: Config.whitePieceColor,
            onTap: () => showColorDialog(S.of(context).whitePieceColor),
          ),
          SettingsListTile(
            titleString: S.of(context).blackPieceColor,
            trailingColor: Config.blackPieceColor,
            onTap: () => showColorDialog(S.of(context).blackPieceColor),
          ),
          SettingsListTile(
            titleString: S.of(context).pieceHighlightColor,
            trailingColor: Config.pieceHighlightColor,
            onTap: () => showColorDialog(S.of(context).pieceHighlightColor),
          ),
          SettingsListTile(
            titleString: S.of(context).messageColor,
            trailingColor: Config.messageColor,
            onTap: () => showColorDialog(S.of(context).messageColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerColor,
            trailingColor: Config.drawerColor,
            onTap: () => showColorDialog(S.of(context).drawerColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerBackgroundColor,
            trailingColor: Config.drawerBackgroundColor,
            onTap: () => showColorDialog(S.of(context).drawerBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerTextColor,
            trailingColor: Config.drawerTextColor,
            onTap: () => showColorDialog(S.of(context).drawerTextColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerHighlightItemColor,
            trailingColor: Config.drawerHighlightItemColor,
            onTap: () =>
                showColorDialog(S.of(context).drawerHighlightItemColor),
          ),
          SettingsListTile(
            titleString: S.of(context).mainToolbarBackgroundColor,
            trailingColor: Config.mainToolbarBackgroundColor,
            onTap: () =>
                showColorDialog(S.of(context).mainToolbarBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).mainToolbarIconColor,
            trailingColor: Config.mainToolbarIconColor,
            onTap: () => showColorDialog(S.of(context).mainToolbarIconColor),
          ),
          SettingsListTile(
            titleString: S.of(context).navigationToolbarBackgroundColor,
            trailingColor: Config.navigationToolbarBackgroundColor,
            onTap: () =>
                showColorDialog(S.of(context).navigationToolbarBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).navigationToolbarIconColor,
            trailingColor: Config.navigationToolbarIconColor,
            onTap: () =>
                showColorDialog(S.of(context).navigationToolbarIconColor),
          ),
        ],
      ),
    ];
  }

  // Display

  Future<void> setIsPieceCountInHandShown(bool value) async {
    setState(() => Config.isPieceCountInHandShown = value);

    Config.save();
  }

  Future<void> setIsNotationsShown(bool value) async {
    setState(() => Config.isNotationsShown = value);

    Config.save();
  }

  Future<void> setIsHistoryNavigationToolbarShown(bool value) async {
    setState(() => Config.isHistoryNavigationToolbarShown = value);

    Config.save();
  }

  Future<void> setStandardNotationEnabled(bool value) async {
    setState(() => Config.standardNotationEnabled = value);

    debugPrint("[config] standardNotationEnabled: $value");

    Config.save();
  }
}
