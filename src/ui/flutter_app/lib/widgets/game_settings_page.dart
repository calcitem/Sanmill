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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/common/settings.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/settings_card.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:sanmill/widgets/settings_switch_list_tile.dart';

import 'dialog.dart';
import 'env_page.dart';
import 'list_item_divider.dart';

class Developer {
  static bool developerModeEnabled = false;
}

class GameSettingsPage extends StatefulWidget {
  @override
  _GameSettingsPageState createState() => _GameSettingsPageState();
}

class _GameSettingsPageState extends State<GameSettingsPage> {
  Color pickerColor = Color(0xFF808080);
  Color currentColor = Color(0xFF808080);

  late StreamController<int> _events;

  final String tag = "[game_settings_page]";

  @override
  void initState() {
    super.initState();
    _events = StreamController<int>.broadcast();
    _events.add(10);
  }

  void _restore() async {
    final settings = await Settings.instance();
    await settings.restore();
  }

  SliderTheme _skillLevelSliderTheme(context, setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Slider(
        value: Config.skillLevel.toDouble(),
        min: 1,
        max: 20,
        divisions: 19,
        label: Config.skillLevel.round().toString(),
        onChanged: (value) {
          setState(() {
            print("[config] Slider value: $value");
            Config.skillLevel = value.toInt();
            Config.save();
          });
        },
      ),
    );
  }

  SliderTheme _moveTimeSliderTheme(context, setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Slider(
        value: Config.moveTime.toDouble(),
        min: 0,
        max: 60,
        divisions: 60,
        label: Config.moveTime.round().toString(),
        onChanged: (value) {
          setState(() {
            print("[config] Slider value: $value");
            Config.moveTime = value.toInt();
            Config.save();
          });
        },
      ),
    );
  }

  // Restore

  restoreFactoryDefaultSettings() async {
    confirm() async {
      Navigator.of(context).pop();
      if (Platform.isAndroid) {
        showCountdownDialog(context, 10, _events, _restore);
      } else {
        _restore();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).exitAppManually)));
      }
    }

    cancel() => Navigator.of(context).pop();

    var prompt = "";

    if (Platform.isAndroid) {
      prompt = S.of(context).exitApp;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).restore,
              style: TextStyle(
                color: AppTheme.dialogTitleColor,
                fontSize: Config.fontSize + 4,
              )),
          content: SingleChildScrollView(
            child: Text(
              S.of(context).restoreDefaultSettings + "?\n" + prompt,
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
                child: Text(
                  S.of(context).ok,
                  style: TextStyle(
                    fontSize: Config.fontSize,
                  ),
                ),
                onPressed: confirm),
            TextButton(
                child: Text(
                  S.of(context).cancel,
                  style: TextStyle(
                    fontSize: Config.fontSize,
                  ),
                ),
                onPressed: cancel),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(S.of(context).preferences),
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
      Text(S.of(context).difficulty, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            context: context,
            titleString: S.of(context).skillLevel,
            onTap: setSkillLevel,
          ),
          ListItemDivider(),
          SettingsListTile(
            context: context,
            titleString: S.of(context).moveTime,
            onTap: setMoveTime,
          ),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.drawOnHumanExperience,
            onChanged: setDrawOnHumanExperience,
            titleString: S.of(context).drawOnHumanExperience,
          ),
          ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.aiIsLazy,
            onChanged: setAiIsLazy,
            titleString: S.of(context).passive,
          ),
          ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.shufflingEnabled,
            onChanged: setShufflingEnabled,
            titleString: S.of(context).shufflingEnabled,
          ),
        ],
      ),
      !Platform.isWindows
          ? SizedBox(height: AppTheme.sizedBoxHeight)
          : Container(height: 0.0, width: 0.0),
      !Platform.isWindows
          ? Text(S.of(context).playSounds, style: AppTheme.settingsHeaderStyle)
          : Container(height: 0.0, width: 0.0),
      !Platform.isWindows
          ? SettingsCard(
              context: context,
              children: <Widget>[
                SettingsSwitchListTile(
                  context: context,
                  value: Config.toneEnabled,
                  onChanged: setTone,
                  titleString: S.of(context).playSoundsInTheGame,
                ),
                ListItemDivider(),
                SettingsSwitchListTile(
                  context: context,
                  value: Config.keepMuteWhenTakingBack,
                  onChanged: setKeepMuteWhenTakingBack,
                  titleString: S.of(context).keepMuteWhenTakingBack,
                ),
              ],
            )
          : Container(height: 0.0, width: 0.0),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).whoMovesFirst, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: !Config.aiMovesFirst,
            onChanged: setWhoMovesFirst,
            titleString:
                Config.aiMovesFirst ? S.of(context).ai : S.of(context).human,
          ),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).experiments, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.experimentsEnabled,
            onChanged: setExperimentsEnabled,
            titleString: S.of(context).experiments,
          ),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).restore, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            context: context,
            titleString: S.of(context).restoreDefaultSettings,
            onTap: restoreFactoryDefaultSettings,
          ),
          ListItemDivider(),
        ],
      ),
      SizedBox(height: AppTheme.sizedBoxHeight),
      Developer.developerModeEnabled
          ? Text(S.of(context).forDevelopers,
              style: AppTheme.settingsHeaderStyle)
          : SizedBox(height: 1),
      Developer.developerModeEnabled
          ? SettingsCard(
              context: context,
              children: <Widget>[
                SettingsSwitchListTile(
                  context: context,
                  value: Config.developerMode,
                  onChanged: setDeveloperMode,
                  titleString: S.of(context).developerMode,
                ),
                ListItemDivider(),
                SettingsSwitchListTile(
                  context: context,
                  value: Config.isAutoRestart,
                  onChanged: setIsAutoRestart,
                  titleString: S.of(context).isAutoRestart,
                ),
                ListItemDivider(),
                SettingsListTile(
                  context: context,
                  titleString: S.of(context).environmentVariables,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EnvironmentVariablesPage(),
                      ),
                    );
                  },
                ),
              ],
            )
          : SizedBox(height: 1),
    ];
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

  setMoveTime() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          return _moveTimeSliderTheme(context, setState);
        },
      ),
    );
  }

  setWhoMovesFirst(bool value) async {
    setState(() {
      Config.aiMovesFirst = !value;
    });

    print("[config] aiMovesFirst: ${Config.aiMovesFirst}");

    Config.save();
  }

  setAiIsLazy(bool value) async {
    setState(() {
      Config.aiIsLazy = value;
    });

    print("[config] aiMovesFirst: $value");

    Config.save();
  }

  setDrawOnHumanExperience(bool value) async {
    setState(() {
      Config.drawOnHumanExperience = value;
    });

    print("[config] drawOnHumanExperience: $value");

    Config.save();
  }

  setIsAutoRestart(bool value) async {
    setState(() {
      Config.isAutoRestart = value;
    });

    print("[config] isAutoRestart: $value");

    Config.save();
  }

  setIsAutoChangeFirstMove(bool value) async {
    setState(() {
      Config.isAutoChangeFirstMove = value;
    });

    print("[config] isAutoChangeFirstMove: $value");

    Config.save();
  }

  setResignIfMostLose(bool value) async {
    setState(() {
      Config.resignIfMostLose = value;
    });

    print("[config] resignIfMostLose: $value");

    Config.save();
  }

  setShufflingEnabled(bool value) async {
    setState(() {
      Config.shufflingEnabled = value;
    });

    print("[config] shufflingEnabled: $value");

    Config.save();
  }

  setLearnEndgame(bool value) async {
    setState(() {
      Config.learnEndgame = value;
    });

    print("[config] learnEndgame: $value");

    Config.save();
  }

  setIdsEnabled(bool value) async {
    setState(() {
      Config.idsEnabled = value;
    });

    print("[config] idsEnabled: $value");

    Config.save();
  }

  setDepthExtension(bool value) async {
    setState(() {
      Config.depthExtension = value;
    });

    print("[config] depthExtension: $value");

    Config.save();
  }

  setOpeningBook(bool value) async {
    setState(() {
      Config.openingBook = value;
    });

    print("[config] openingBook: $value");

    Config.save();
  }

  setTone(bool value) async {
    setState(() {
      Config.toneEnabled = value;
    });

    print("[config] toneEnabled: $value");

    Config.save();
  }

  setKeepMuteWhenTakingBack(bool value) async {
    setState(() {
      Config.keepMuteWhenTakingBack = value;
    });

    print("[config] keepMuteWhenTakingBack: $value");

    Config.save();
  }

  setDeveloperMode(bool value) async {
    setState(() {
      Config.developerMode = value;
    });

    print("[config] developerMode: $value");

    Config.save();
  }

  setExperimentsEnabled(bool value) async {
    setState(() {
      Config.experimentsEnabled = value;
    });

    print("[config] experimentsEnabled: $value");

    Config.save();
  }

  // Display

  setIsPieceCountInHandShown(bool value) async {
    setState(() {
      Config.isPieceCountInHandShown = value;
    });

    print("[config] isPieceCountInHandShown: $value");

    Config.save();
  }

  setIsNotationsShown(bool value) async {
    setState(() {
      Config.isNotationsShown = value;
    });

    print("[config] isNotationsShown: $value");

    Config.save();
  }

  setIsHistoryNavigationToolbarShown(bool value) async {
    setState(() {
      Config.isHistoryNavigationToolbarShown = value;
    });

    print("[config] isHistoryNavigationToolbarShown: $value");

    Config.save();
  }

  setStandardNotationEnabled(bool value) async {
    setState(() {
      Config.standardNotationEnabled = value;
    });

    print("[config] standardNotationEnabled: $value");

    Config.save();
  }
}
