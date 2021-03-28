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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/common/settings.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';

import 'list_item_divider.dart';

class GameSettingsPage extends StatefulWidget {
  @override
  _GameSettingsPageState createState() => _GameSettingsPageState();
}

class _GameSettingsPageState extends State<GameSettingsPage> {
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

  showBoardColorDialog() async {
    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + S.of(context).boardColor),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(Config.boardBackgroundColor),
          onColorChanged: changeColor,
          showLabel: true,
          //pickerAreaHeightPercent: 0.8,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);
            Config.boardBackgroundColor = pickerColor.value;
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

  showBackgroundColorDialog() async {
    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + S.of(context).backgroudColor),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(Config.darkBackgroundColor),
          onColorChanged: changeColor,
          showLabel: true,
          //pickerAreaHeightPercent: 0.8,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);
            Config.darkBackgroundColor = pickerColor.value;
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

  showBoardLineColorDialog() async {
    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + S.of(context).lineColor),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(Config.boardLineColor),
          onColorChanged: changeColor,
          showLabel: true,
          //pickerAreaHeightPercent: 0.8,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);
            Config.boardLineColor = pickerColor.value;
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

  showBlackPieceColorDialog() async {
    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + S.of(context).blackPieceColor),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(Config.blackPieceColor),
          onColorChanged: changeColor,
          showLabel: true,
          //pickerAreaHeightPercent: 0.8,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);
            Config.blackPieceColor = pickerColor.value;
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

  showWhitePieceColorDialog() async {
    AlertDialog alert = AlertDialog(
      title: Text(S.of(context).pick + S.of(context).whitePieceColor),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: Color(Config.whitePieceColor),
          onColorChanged: changeColor,
          showLabel: true,
          //pickerAreaHeightPercent: 0.8,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(S.of(context).confirm),
          onPressed: () {
            setState(() => currentColor = pickerColor);
            Config.whitePieceColor = pickerColor.value;
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

  SliderTheme _skillLevelSliderTheme(context, setState) {
    return SliderTheme(
      data: SliderThemeData(
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
      ),
      child: Slider(
        value: Config.skillLevel.toDouble(),
        min: 1,
        max: 20,
        divisions: 19,
        label: Config.skillLevel.round().toString(),
        onChanged: (value) {
          setState(() {
            print("Slider value: $value");
            Config.skillLevel = value.toInt();
            Config.save();
          });
        },
      ),
    );
  }

  setSkillLevel() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          return _skillLevelSliderTheme(context, setState);
        },
      ),
    );
  }

  setWhoMovesFirst(bool value) async {
    setState(() {
      Config.aiMovesFirst = !value;
    });

    Config.save();
  }

  setAiIsLazy(bool value) async {
    setState(() {
      Config.aiIsLazy = value;
    });

    Config.save();
  }

  setIsAutoRestart(bool value) async {
    setState(() {
      Config.isAutoRestart = value;
    });

    Config.save();
  }

  setIsAutoChangeFirstMove(bool value) async {
    setState(() {
      Config.isAutoChangeFirstMove = value;
    });

    Config.save();
  }

  setResignIfMostLose(bool value) async {
    setState(() {
      Config.resignIfMostLose = value;
    });

    Config.save();
  }

  setShufflingEnabled(bool value) async {
    setState(() {
      Config.shufflingEnabled = value;
    });

    Config.save();
  }

  setLearnEndgame(bool value) async {
    setState(() {
      Config.learnEndgame = value;
    });

    Config.save();
  }

  setIdsEnabled(bool value) async {
    setState(() {
      Config.idsEnabled = value;
    });

    Config.save();
  }

  setDepthExtension(bool value) async {
    setState(() {
      Config.depthExtension = value;
    });

    Config.save();
  }

  setOpeningBook(bool value) async {
    setState(() {
      Config.openingBook = value;
    });

    Config.save();
  }

  setTone(bool value) async {
    //
    setState(() {
      Config.toneEnabled = value;
    });

    Config.save();
  }

  // Display

  setIsPieceCountInHandShown(bool value) async {
    setState(() {
      Config.isPieceCountInHandShown = value;
    });

    Config.save();
  }

  SliderTheme _boardBorderLineWidthSliderTheme(context, setState) {
    return SliderTheme(
      data: SliderThemeData(
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
      ),
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
      data: SliderThemeData(
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
      ),
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

  // Restore

  restoreFactoryDefaultSettings() async {
    confirm() async {
      Navigator.of(context).pop();
      final profile = await Settings.instance();
      await profile.restore();
      exit(0);
    }

    cancel() => Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).restore,
              style: TextStyle(color: UIColors.primaryColor)),
          content: SingleChildScrollView(
            child: Text(S.of(context).restoreDefaultSettings +
                "?\n" +
                S.of(context).exitApp),
          ),
          actions: <Widget>[
            TextButton(child: Text(S.of(context).ok), onPressed: confirm),
            TextButton(child: Text(S.of(context).cancel), onPressed: cancel),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle headerStyle =
        TextStyle(color: UIColors.crusoeColor, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: UIColors.crusoeColor);

    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar: AppBar(
          centerTitle: true,
          title: Text(S.of(context).settings),
          backgroundColor: UIColors.primaryColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(S.of(context).difficulty, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              elevation: 0.5,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).skillLevel, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(""), // TODO
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: setSkillLevel,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).aisPlayStyle, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: Config.aiIsLazy,
                    title: Text(S.of(context).passive, style: itemStyle),
                    onChanged: setAiIsLazy,
                  ),
                  ListItemDivider(),
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: Config.shufflingEnabled,
                    title:
                        Text(S.of(context).shufflingEnabled, style: itemStyle),
                    onChanged: setShufflingEnabled,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).playSounds, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: Config.toneEnabled,
                    title: Text(S.of(context).playSoundsInTheGame,
                        style: itemStyle),
                    onChanged: setTone,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).whoMovesFirst, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: !Config.aiMovesFirst,
                    title: Text(
                        Config.aiMovesFirst
                            ? S.of(context).ai
                            : S.of(context).human,
                        style: itemStyle),
                    onChanged: setWhoMovesFirst,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).automaticBehavior, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: Config.isAutoRestart,
                    title: Text(S.of(context).isAutoRestart, style: itemStyle),
                    onChanged: setIsAutoRestart,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).display, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: AppTheme.switchListTileActiveColor,
                    value: Config.isPieceCountInHandShown,
                    title: Text(S.of(context).isPieceCountInHandShown,
                        style: itemStyle),
                    onChanged: setIsPieceCountInHandShown,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title: Text(S.of(context).boardBorderLineWidth,
                        style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(""), // TODO
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: setBoardBorderLineWidth,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title: Text(S.of(context).boardInnerLineWidth,
                        style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(""), // TODO
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: setBoardInnerLineWidth,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).color, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).boardColor, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.boardBackgroundColor.toRadixString(16),
                          style: TextStyle(
                              backgroundColor:
                                  Color(Config.boardBackgroundColor))),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showBoardColorDialog,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title: Text(S.of(context).backgroudColor, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.darkBackgroundColor.toRadixString(16),
                          style: TextStyle(
                              backgroundColor:
                                  Color(Config.darkBackgroundColor))),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showBackgroundColorDialog,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title: Text(S.of(context).lineColor, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.boardLineColor.toRadixString(16),
                          style: TextStyle(
                              backgroundColor: Color(Config.boardLineColor))),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showBoardLineColorDialog,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title:
                        Text(S.of(context).blackPieceColor, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.blackPieceColor.toRadixString(16),
                          style: TextStyle(
                              backgroundColor: Color(Config.blackPieceColor))),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showBlackPieceColorDialog,
                  ),
                  ListItemDivider(),
                  ListTile(
                    title:
                        Text(S.of(context).whitePieceColor, style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.whitePieceColor.toRadixString(16),
                          style: TextStyle(
                              backgroundColor: Color(Config.whitePieceColor))),
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: showWhitePieceColorDialog,
                  ),
                ],
              ),
            ),
            AppTheme.sizedBox,
            Text(S.of(context).restore, style: headerStyle),
            Card(
              color: AppTheme.cardColor,
              margin: AppTheme.cardMargin,
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text(S.of(context).restoreDefaultSettings,
                        style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(Icons.keyboard_arrow_right,
                          color: UIColors.secondaryColor),
                    ]),
                    onTap: restoreFactoryDefaultSettings,
                  ),
                  ListItemDivider(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
