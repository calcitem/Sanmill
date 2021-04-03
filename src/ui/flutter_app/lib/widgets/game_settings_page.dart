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
import 'package:sanmill/common/config.dart';
import 'package:sanmill/common/settings.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/widgets/settings_card.dart';
import 'package:sanmill/widgets/settings_list_tile.dart';
import 'package:sanmill/widgets/settings_switch_list_tile.dart';

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
            print("Slider value: $value");
            Config.skillLevel = value.toInt();
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
    return Scaffold(
      backgroundColor: UIColors.lightBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(S.of(context).settings),
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
        ],
      ),
      AppTheme.sizedBox,
      Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
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
      AppTheme.sizedBox,
      Text(S.of(context).playSounds, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.toneEnabled,
            onChanged: setTone,
            titleString: S.of(context).playSoundsInTheGame,
          ),
        ],
      ),
      AppTheme.sizedBox,
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
      AppTheme.sizedBox,
      Text(S.of(context).automaticBehavior,
          style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.isAutoRestart,
            onChanged: setIsAutoRestart,
            titleString: S.of(context).isAutoRestart,
          ),
        ],
      ),
      AppTheme.sizedBox,
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
}
