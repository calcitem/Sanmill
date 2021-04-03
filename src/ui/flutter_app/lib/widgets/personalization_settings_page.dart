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
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/settings_card.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:sanmill/widgets/settings_switch_list_tile.dart';

import 'list_item_divider.dart';

class PersonalizationSettingsPage extends StatefulWidget {
  @override
  _PersonalizationSettingsPageState createState() =>
      _PersonalizationSettingsPageState();
}

class _PersonalizationSettingsPageState
    extends State<PersonalizationSettingsPage> {
  // create some values
  Color pickerColor = Color(0xFF808080);
  Color currentColor = Color(0xFF808080);

  @override
  void initState() {
    super.initState();
  }

  // ValueChanged<Color> callback
  void changeColor(Color color) {
    setState(() => pickerColor = color);
  }

  showColorDialog(String colorString) async {
    Map<String, int> colorStrToVal = {
      S.of(context).boardColor: Config.boardBackgroundColor,
      S.of(context).backgroudColor: Config.darkBackgroundColor,
      S.of(context).lineColor: Config.boardLineColor,
      S.of(context).blackPieceColor: Config.blackPieceColor,
      S.of(context).whitePieceColor: Config.whitePieceColor,
    };

    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + colorString),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(colorStrToVal[colorString]!),
          onColorChanged: changeColor,
          showLabel: true,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);

            if (colorString == S.of(context).boardColor) {
              Config.boardBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).backgroudColor) {
              Config.darkBackgroundColor = pickerColor.value;
            } else if (colorString == S.of(context).lineColor) {
              Config.boardLineColor = pickerColor.value;
            } else if (colorString == S.of(context).blackPieceColor) {
              Config.blackPieceColor = pickerColor.value;
            } else if (colorString == S.of(context).whitePieceColor) {
              Config.whitePieceColor = pickerColor.value;
            }

            Config.save();
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text(S.of(context).cancel),
          onPressed: () {
            Navigator.of(context).pop();
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

  SliderTheme _boardBorderLineWidthSliderTheme(context, setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Slider(
        value: Config.boardBorderLineWidth.toDouble(),
        min: 0.0,
        max: 20.0,
        divisions: 200,
        label: Config.boardBorderLineWidth.toStringAsFixed(1),
        onChanged: (value) {
          setState(() {
            print("BoardBorderLineWidth value: $value");
            Config.boardBorderLineWidth = value;
            Config.save();
          });
        },
      ),
    );
  }

  setBoardBorderLineWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          return _boardBorderLineWidthSliderTheme(context, setState);
        },
      ),
    );
  }

  SliderTheme _boardInnerLineWidthSliderTheme(context, setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Slider(
        value: Config.boardInnerLineWidth.toDouble(),
        min: 0.0,
        max: 20.0,
        divisions: 200,
        label: Config.boardInnerLineWidth.toStringAsFixed(1),
        onChanged: (value) {
          setState(() {
            print("BoardInnerLineWidth value: $value");
            Config.boardInnerLineWidth = value;
            Config.save();
          });
        },
      ),
    );
  }

  setBoardInnerLineWidth() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          return _boardInnerLineWidthSliderTheme(context, setState);
        },
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
    return <Widget>[
      Text(S.of(context).display, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.isPieceCountInHandShown,
            onChanged: setIsPieceCountInHandShown,
            titleString: S.of(context).isPieceCountInHandShown,
          ),
          ListItemDivider(),
          SettingsListTile(
              context: context,
              titleString: S.of(context).boardBorderLineWidth,
              onTap: setBoardBorderLineWidth),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).boardInnerLineWidth,
            onTap: setBoardInnerLineWidth,
          ),
        ],
      ),
      AppTheme.sizedBox,
      Text(S.of(context).color, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            context: context,
            titleString: S.of(context).boardColor,
            trailingColor: Config.boardBackgroundColor,
            onTap: () => showColorDialog(S.of(context).boardColor),
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).backgroudColor,
            trailingColor: Config.darkBackgroundColor,
            onTap: () => showColorDialog(S.of(context).backgroudColor),
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).lineColor,
            trailingColor: Config.boardLineColor,
            onTap: () => showColorDialog(S.of(context).lineColor),
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).blackPieceColor,
            trailingColor: Config.blackPieceColor,
            onTap: () => showColorDialog(S.of(context).blackPieceColor),
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).whitePieceColor,
            trailingColor: Config.whitePieceColor,
            onTap: () => showColorDialog(S.of(context).whitePieceColor),
          ),
        ],
      ),
    ];
  }

  // Display

  setIsPieceCountInHandShown(bool value) async {
    setState(() {
      Config.isPieceCountInHandShown = value;
    });

    Config.save();
  }
}
