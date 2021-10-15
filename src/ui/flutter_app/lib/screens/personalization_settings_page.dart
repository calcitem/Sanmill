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
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
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
    final Map<String, Color> colorStrToVal = {
      S.of(context).boardColor:
          LocalDatabaseService.colorSettings.boardBackgroundColor,
      S.of(context).backgroundColor:
          LocalDatabaseService.colorSettings.darkBackgroundColor,
      S.of(context).lineColor:
          LocalDatabaseService.colorSettings.boardLineColor,
      S.of(context).whitePieceColor:
          LocalDatabaseService.colorSettings.whitePieceColor,
      S.of(context).blackPieceColor:
          LocalDatabaseService.colorSettings.blackPieceColor,
      S.of(context).pieceHighlightColor:
          LocalDatabaseService.colorSettings.pieceHighlightColor,
      S.of(context).messageColor:
          LocalDatabaseService.colorSettings.messageColor,
      S.of(context).drawerColor: LocalDatabaseService.colorSettings.drawerColor,
      S.of(context).drawerBackgroundColor:
          LocalDatabaseService.colorSettings.drawerBackgroundColor,
      S.of(context).drawerTextColor:
          LocalDatabaseService.colorSettings.drawerTextColor,
      S.of(context).drawerHighlightItemColor:
          LocalDatabaseService.colorSettings.drawerHighlightItemColor,
      S.of(context).mainToolbarBackgroundColor:
          LocalDatabaseService.colorSettings.mainToolbarBackgroundColor,
      S.of(context).mainToolbarIconColor:
          LocalDatabaseService.colorSettings.mainToolbarIconColor,
      S.of(context).navigationToolbarBackgroundColor:
          LocalDatabaseService.colorSettings.navigationToolbarBackgroundColor,
      S.of(context).navigationToolbarIconColor:
          LocalDatabaseService.colorSettings.navigationToolbarIconColor,
    };

    final AlertDialog alert = AlertDialog(
      title: Text(
        "${S.of(context).pick} $colorString",
        style: TextStyle(
          fontSize: LocalDatabaseService.display.fontSize + 4,
        ),
      ),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: colorStrToVal[colorString]!,
          onColorChanged: changeColor,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).confirm,
            style: TextStyle(
              fontSize: LocalDatabaseService.display.fontSize,
            ),
          ),
          onPressed: () {
            setState(() => currentColor = pickerColor);

            debugPrint("[config] pickerColor.value: ${pickerColor.value}");

            if (colorString == S.of(context).boardColor) {
              LocalDatabaseService.colorSettings.boardBackgroundColor =
                  pickerColor;
            } else if (colorString == S.of(context).backgroundColor) {
              LocalDatabaseService.colorSettings.darkBackgroundColor =
                  pickerColor;
            } else if (colorString == S.of(context).lineColor) {
              LocalDatabaseService.colorSettings.boardLineColor = pickerColor;
            } else if (colorString == S.of(context).whitePieceColor) {
              LocalDatabaseService.colorSettings.whitePieceColor = pickerColor;
            } else if (colorString == S.of(context).blackPieceColor) {
              LocalDatabaseService.colorSettings.blackPieceColor = pickerColor;
            } else if (colorString == S.of(context).pieceHighlightColor) {
              LocalDatabaseService.colorSettings.pieceHighlightColor =
                  pickerColor;
            } else if (colorString == S.of(context).messageColor) {
              LocalDatabaseService.colorSettings.messageColor = pickerColor;
            } else if (colorString == S.of(context).drawerColor) {
              LocalDatabaseService.colorSettings.drawerColor = pickerColor;
            } else if (colorString == S.of(context).drawerBackgroundColor) {
              LocalDatabaseService.colorSettings.drawerBackgroundColor =
                  pickerColor;
            } else if (colorString == S.of(context).drawerTextColor) {
              LocalDatabaseService.colorSettings.drawerTextColor = pickerColor;
            } else if (colorString == S.of(context).drawerHighlightItemColor) {
              LocalDatabaseService.colorSettings.drawerHighlightItemColor =
                  pickerColor;
            } else if (colorString ==
                S.of(context).mainToolbarBackgroundColor) {
              LocalDatabaseService.colorSettings.mainToolbarBackgroundColor =
                  pickerColor;
            } else if (colorString == S.of(context).mainToolbarIconColor) {
              LocalDatabaseService.colorSettings.mainToolbarIconColor =
                  pickerColor;
            } else if (colorString ==
                S.of(context).navigationToolbarBackgroundColor) {
              LocalDatabaseService
                  .colorSettings.navigationToolbarBackgroundColor = pickerColor;
            } else if (colorString ==
                S.of(context).navigationToolbarIconColor) {
              LocalDatabaseService.colorSettings.navigationToolbarIconColor =
                  pickerColor;
            }

            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
              fontSize: LocalDatabaseService.display.fontSize,
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

  SliderTheme _boardBorderLineWidthSliderTheme(
    BuildContext context,
    Function setState,
  ) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardBorderLineWidth,
        child: Slider(
          value: LocalDatabaseService.display.boardBorderLineWidth,
          max: 20.0,
          divisions: 200,
          label: LocalDatabaseService.display.boardBorderLineWidth
              .toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardBorderLineWidth value: $value");
              LocalDatabaseService.display.boardBorderLineWidth = value;
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
        builder: _boardBorderLineWidthSliderTheme,
      ),
    );
  }

  SliderTheme _boardInnerLineWidthSliderTheme(
    BuildContext context,
    Function setState,
  ) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardInnerLineWidth,
        child: Slider(
          value: LocalDatabaseService.display.boardInnerLineWidth,
          max: 20.0,
          divisions: 200,
          label: LocalDatabaseService.display.boardInnerLineWidth
              .toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardInnerLineWidth value: $value");
              LocalDatabaseService.display.boardInnerLineWidth = value;
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
        builder: _boardInnerLineWidthSliderTheme,
      ),
    );
  }

  void setPointStyle() {
    Future<void> callback(int? pointStyle) async {
      Navigator.pop(context);

      setState(
        () => LocalDatabaseService.display.pointStyle = pointStyle ?? 0,
      );

      debugPrint("[config] pointStyle: $pointStyle");
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).pointStyle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: Text(S.of(context).none),
              groupValue: LocalDatabaseService.display.pointStyle,
              value: 0,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: Text(S.of(context).solid),
              groupValue: LocalDatabaseService.display.pointStyle,
              value: 1,
              onChanged: callback,
            ),
            /*
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text(S.of(context).hollow),
              groupValue: LocalDatabaseService.display.pointStyle,
              value: 2,
              onChanged: callback,
            ),
            */
          ],
        ),
      ),
    );
  }

  SliderTheme _pointWidthSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).pointWidth,
        child: Slider(
          value: LocalDatabaseService.display.pointWidth,
          max: 30.0,
          divisions: 30,
          label: LocalDatabaseService.display.pointWidth.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] pointWidth value: $value");
              LocalDatabaseService.display.pointWidth = value;
            });
          },
        ),
      ),
    );
  }

  Future<void> setPointWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: _pointWidthSliderTheme,
      ),
    );
  }

  SliderTheme _pieceWidthSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).pieceWidth,
        child: Slider(
          value: LocalDatabaseService.display.pieceWidth,
          min: 0.5,
          divisions: 50,
          label: LocalDatabaseService.display.pieceWidth.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] pieceWidth value: $value");
              LocalDatabaseService.display.pieceWidth = value;
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
        builder: _pieceWidthSliderTheme,
      ),
    );
  }

  SliderTheme _fontSizeSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).fontSize,
        child: Slider(
          value: LocalDatabaseService.display.fontSize,
          min: 16,
          max: 32,
          divisions: 16,
          label: LocalDatabaseService.display.fontSize.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] fontSize value: $value");
              LocalDatabaseService.display.fontSize = value;
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
        builder: _fontSizeSliderTheme,
      ),
    );
  }

  SliderTheme _boardTopSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).boardTop,
        child: Slider(
          value: LocalDatabaseService.display.boardTop,
          max: 288.0,
          divisions: 288,
          label: LocalDatabaseService.display.boardTop.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] BoardTop value: $value");
              LocalDatabaseService.display.boardTop = value;
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
        builder: _boardTopSliderTheme,
      ),
    );
  }

  SliderTheme _animationDurationSliderTheme(
    BuildContext context,
    Function setState,
  ) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).animationDuration,
        child: Slider(
          value: LocalDatabaseService.display.animationDuration,
          max: 5.0,
          divisions: 50,
          label:
              LocalDatabaseService.display.animationDuration.toStringAsFixed(1),
          onChanged: (value) {
            setState(() {
              debugPrint("[config] AnimationDuration value: $value");
              LocalDatabaseService.display.animationDuration = value;
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
        builder: _animationDurationSliderTheme,
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
    Future<void> langCallback([Locale? locale]) async {
      debugPrint("[config] languageCode = $locale");

      Navigator.pop(context);

      setState(() {
        LocalDatabaseService.display.languageCode =
            locale ?? Constants.defaultLocale;
        S.load(Locale(Resources.of().languageCode));
      });

      debugPrint(
        "[config] LocalDatabaseService.display.languageCode: ${LocalDatabaseService.display.languageCode}",
      );
    }

    return <Widget>[
      Text(S.of(context).display, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).language,
            trailingString: LocalDatabaseService.display.languageCode !=
                    Constants.defaultLocale
                ? languageCodeToStrings[
                        LocalDatabaseService.display.languageCode]!
                    .languageName
                : "",
            onTap: () => setLanguage(context, langCallback),
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.display.isPieceCountInHandShown,
            onChanged: setIsPieceCountInHandShown,
            titleString: S.of(context).isPieceCountInHandShown,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.display.isNotationsShown,
            onChanged: setIsNotationsShown,
            titleString: S.of(context).isNotationsShown,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.display.isHistoryNavigationToolbarShown,
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
            titleString: S.of(context).pointStyle,
            onTap: setPointStyle,
          ),
          SettingsListTile(
            titleString: S.of(context).pointWidth,
            onTap: setPointWidth,
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
            value: LocalDatabaseService.display.standardNotationEnabled,
            onChanged: setStandardNotationEnabled,
            titleString: S.of(context).standardNotation,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).color, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).boardColor,
            trailingColor:
                LocalDatabaseService.colorSettings.boardBackgroundColor,
            onTap: () => showColorDialog(S.of(context).boardColor),
          ),
          SettingsListTile(
            titleString: S.of(context).backgroundColor,
            trailingColor:
                LocalDatabaseService.colorSettings.darkBackgroundColor,
            onTap: () => showColorDialog(S.of(context).backgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).lineColor,
            trailingColor: LocalDatabaseService.colorSettings.boardLineColor,
            onTap: () => showColorDialog(S.of(context).lineColor),
          ),
          SettingsListTile(
            titleString: S.of(context).whitePieceColor,
            trailingColor: LocalDatabaseService.colorSettings.whitePieceColor,
            onTap: () => showColorDialog(S.of(context).whitePieceColor),
          ),
          SettingsListTile(
            titleString: S.of(context).blackPieceColor,
            trailingColor: LocalDatabaseService.colorSettings.blackPieceColor,
            onTap: () => showColorDialog(S.of(context).blackPieceColor),
          ),
          SettingsListTile(
            titleString: S.of(context).pieceHighlightColor,
            trailingColor:
                LocalDatabaseService.colorSettings.pieceHighlightColor,
            onTap: () => showColorDialog(S.of(context).pieceHighlightColor),
          ),
          SettingsListTile(
            titleString: S.of(context).messageColor,
            trailingColor: LocalDatabaseService.colorSettings.messageColor,
            onTap: () => showColorDialog(S.of(context).messageColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerColor,
            trailingColor: LocalDatabaseService.colorSettings.drawerColor,
            onTap: () => showColorDialog(S.of(context).drawerColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerBackgroundColor,
            trailingColor:
                LocalDatabaseService.colorSettings.drawerBackgroundColor,
            onTap: () => showColorDialog(S.of(context).drawerBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerTextColor,
            trailingColor: LocalDatabaseService.colorSettings.drawerTextColor,
            onTap: () => showColorDialog(S.of(context).drawerTextColor),
          ),
          SettingsListTile(
            titleString: S.of(context).drawerHighlightItemColor,
            trailingColor:
                LocalDatabaseService.colorSettings.drawerHighlightItemColor,
            onTap: () =>
                showColorDialog(S.of(context).drawerHighlightItemColor),
          ),
          SettingsListTile(
            titleString: S.of(context).mainToolbarBackgroundColor,
            trailingColor:
                LocalDatabaseService.colorSettings.mainToolbarBackgroundColor,
            onTap: () =>
                showColorDialog(S.of(context).mainToolbarBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).mainToolbarIconColor,
            trailingColor:
                LocalDatabaseService.colorSettings.mainToolbarIconColor,
            onTap: () => showColorDialog(S.of(context).mainToolbarIconColor),
          ),
          SettingsListTile(
            titleString: S.of(context).navigationToolbarBackgroundColor,
            trailingColor: LocalDatabaseService
                .colorSettings.navigationToolbarBackgroundColor,
            onTap: () =>
                showColorDialog(S.of(context).navigationToolbarBackgroundColor),
          ),
          SettingsListTile(
            titleString: S.of(context).navigationToolbarIconColor,
            trailingColor:
                LocalDatabaseService.colorSettings.navigationToolbarIconColor,
            onTap: () =>
                showColorDialog(S.of(context).navigationToolbarIconColor),
          ),
        ],
      ),
    ];
  }

  // Display

  Future<void> setIsPieceCountInHandShown(bool value) async {
    setState(
      () => LocalDatabaseService.display.isPieceCountInHandShown = value,
    );
  }

  Future<void> setIsNotationsShown(bool value) async {
    setState(() => LocalDatabaseService.display.isNotationsShown = value);
  }

  Future<void> setIsHistoryNavigationToolbarShown(bool value) async {
    setState(
      () =>
          LocalDatabaseService.display.isHistoryNavigationToolbarShown = value,
    );
  }

  Future<void> setStandardNotationEnabled(bool value) async {
    setState(
      () => LocalDatabaseService.display.standardNotationEnabled = value,
    );

    debugPrint("[config] standardNotationEnabled: $value");
  }
}
