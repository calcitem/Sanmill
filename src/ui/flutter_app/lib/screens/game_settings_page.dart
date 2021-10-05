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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/screens/settings/settings_card.dart';
import 'package:sanmill/screens/settings/settings_list_tile.dart';
import 'package:sanmill/screens/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/common/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

import '../shared/dialog.dart';
import 'env_page.dart';
import 'list_item_divider.dart';

class Developer {
  const Developer._();
  static bool developerModeEnabled = false;
}

class GameSettingsPage extends StatefulWidget {
  @override
  _GameSettingsPageState createState() => _GameSettingsPageState();
}

class _GameSettingsPageState extends State<GameSettingsPage> {
  Color pickerColor = const Color(0xFF808080);
  Color currentColor = const Color(0xFF808080);

  late StreamController<int> _events;

  List<String> algorithmNames = ['Alpha-Beta', 'PVS', 'MTD(f)'];

  final String tag = "[game_settings_page]";

  @override
  void initState() {
    super.initState();
    _events = StreamController<int>.broadcast();
    _events.add(10);
  }

  Future<void> _restore() async {
    final settings = await Settings.instance();
    await settings.restore();
  }

  SliderTheme _skillLevelSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).skillLevel,
        child: Slider(
          value: Config.skillLevel.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: Config.skillLevel.toString(),
          onChanged: (value) => setState(() {
           debugPrint("[config] Slider value: $value");
            Config.skillLevel = value.toInt();
            Config.save();
          }),
        ),
      ),
    );
  }

  SliderTheme _moveTimeSliderTheme() {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).moveTime,
        child: Slider(
          value: Config.moveTime.toDouble(),
          max: 60,
          divisions: 60,
          label: Config.moveTime.toString(),
          onChanged: (value) => setState(() {
           debugPrint("[config] Slider value: $value");
            Config.moveTime = value.toInt();
            Config.save();
          }),
        ),
      ),
    );
  }

  // Restore

  Future<void> restoreFactoryDefaultSettings() async {
    Future<void> confirm() async {
      Navigator.of(context).pop();
      if (Platform.isAndroid) {
        showCountdownDialog(context, 10, _events, _restore);
      } else {
        _restore();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).exitAppManually)),
        );
      }
    }

    void cancel() => Navigator.of(context).pop();

    var prompt = "";

    if (Platform.isAndroid) {
      prompt = S.of(context).exitApp;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            S.of(context).restore,
            style: TextStyle(
              color: AppTheme.dialogTitleColor,
              fontSize: Config.fontSize + 4,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              "${S.of(context).restoreDefaultSettings}?\n$prompt",
              style: TextStyle(
                fontSize: Config.fontSize,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: confirm,
              child: Text(
                S.of(context).ok,
                style: TextStyle(
                  fontSize: Config.fontSize,
                ),
              ),
            ),
            TextButton(
              onPressed: cancel,
              child: Text(
                S.of(context).cancel,
                style: TextStyle(
                  fontSize: Config.fontSize,
                ),
              ),
            ),
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
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).difficulty, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).skillLevel,
            //trailingString: "L" + Config.skillLevel.toString(),
            onTap: setSkillLevel,
          ),
          const ListItemDivider(),
          SettingsListTile(
            titleString: S.of(context).moveTime,
            onTap: setMoveTime,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).algorithm,
            trailingString: algorithmNames[Config.algorithm],
            onTap: setAlgorithm,
          ),
          const ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.drawOnHumanExperience,
            onChanged: setDrawOnHumanExperience,
            titleString: S.of(context).drawOnHumanExperience,
          ),
          const ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.considerMobility,
            onChanged: setConsiderMobility,
            titleString: S.of(context).considerMobility,
          ),
          const ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.aiIsLazy,
            onChanged: setAiIsLazy,
            titleString: S.of(context).passive,
          ),
          const ListItemDivider(),
          SettingsSwitchListTile(
            context: context,
            value: Config.shufflingEnabled,
            onChanged: setShufflingEnabled,
            titleString: S.of(context).shufflingEnabled,
          ),
        ],
      ),
      if (!Platform.isWindows)
        const SizedBox(height: AppTheme.sizedBoxHeight)
      else
        const SizedBox(height: 0.0, width: 0.0),
      if (!Platform.isWindows)
        Text(S.of(context).playSounds, style: AppTheme.settingsHeaderStyle)
      else
        const SizedBox(height: 0.0, width: 0.0),
      if (!Platform.isWindows)
        SettingsCard(
          context: context,
          children: <Widget>[
            SettingsSwitchListTile(
              context: context,
              value: Config.toneEnabled,
              onChanged: setTone,
              titleString: S.of(context).playSoundsInTheGame,
            ),
            const ListItemDivider(),
            SettingsSwitchListTile(
              context: context,
              value: Config.keepMuteWhenTakingBack,
              onChanged: setKeepMuteWhenTakingBack,
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
          ],
        )
      else
        const SizedBox(height: 0.0, width: 0.0),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).accessibility, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsSwitchListTile(
            context: context,
            value: Config.screenReaderSupport,
            onChanged: setScreenReaderSupport,
            titleString: S.of(context).screenReaderSupport,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).restore, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        context: context,
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).restoreDefaultSettings,
            onTap: restoreFactoryDefaultSettings,
          ),
          const ListItemDivider(),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      if (Developer.developerModeEnabled)
        Text(
          S.of(context).forDevelopers,
          style: AppTheme.settingsHeaderStyle,
        )
      else
        const SizedBox(height: 1),
      if (Developer.developerModeEnabled)
        SettingsCard(
          context: context,
          children: <Widget>[
            SettingsSwitchListTile(
              context: context,
              value: Config.developerMode,
              onChanged: setDeveloperMode,
              titleString: S.of(context).developerMode,
            ),
            const ListItemDivider(),
            SettingsSwitchListTile(
              context: context,
              value: Config.experimentsEnabled,
              onChanged: setExperimentsEnabled,
              titleString: S.of(context).experiments,
            ),
            const ListItemDivider(),
            SettingsSwitchListTile(
              context: context,
              value: Config.isAutoRestart,
              onChanged: setIsAutoRestart,
              titleString: S.of(context).isAutoRestart,
            ),
            const ListItemDivider(),
            SettingsListTile(
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
      else
        const SizedBox(height: 1),
    ];
  }

  Future<void> setSkillLevel() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _skillLevelSliderTheme(),
      ),
    );
  }

  Future<void> setMoveTime() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, __) => _moveTimeSliderTheme(),
      ),
    );
  }

  Future<void> setWhoMovesFirst(bool value) async {
    setState(() {
      Config.aiMovesFirst = !value;
    });

   debugPrint("[config] aiMovesFirst: ${Config.aiMovesFirst}");

    Config.save();
  }

  Future<void> setAiIsLazy(bool value) async {
    setState(() {
      Config.aiIsLazy = value;
    });

   debugPrint("[config] aiMovesFirst: $value");

    Config.save();
  }

  void setAlgorithm() {
    Future<void> callback(int? algorithm) async {
     debugPrint("[config] algorithm = $algorithm");

      Navigator.of(context).pop();

      setState(() {
        Config.algorithm = algorithm ?? 2;
      });

     debugPrint("[config] Config.algorithm: ${Config.algorithm}");

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Semantics(
        label: S.of(context).algorithm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('Alpha-Beta'),
              groupValue: Config.algorithm,
              value: 0,
              onChanged: callback,
            ),
            const ListItemDivider(),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('PVS'),
              groupValue: Config.algorithm,
              value: 1,
              onChanged: callback,
            ),
            const ListItemDivider(),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('MTD(f)'),
              groupValue: Config.algorithm,
              value: 2,
              onChanged: callback,
            ),
            const ListItemDivider(),
          ],
        ),
      ),
    );
  }

  Future<void> setDrawOnHumanExperience(bool value) async {
    setState(() {
      Config.drawOnHumanExperience = value;
    });

   debugPrint("[config] drawOnHumanExperience: $value");

    Config.save();
  }

  Future<void> setConsiderMobility(bool value) async {
    setState(() {
      Config.considerMobility = value;
    });

   debugPrint("[config] considerMobility: $value");

    Config.save();
  }

  Future<void> setIsAutoRestart(bool value) async {
    setState(() {
      Config.isAutoRestart = value;
    });

   debugPrint("[config] isAutoRestart: $value");

    Config.save();
  }

  Future<void> setIsAutoChangeFirstMove(bool value) async {
    setState(() {
      Config.isAutoChangeFirstMove = value;
    });

   debugPrint("[config] isAutoChangeFirstMove: $value");

    Config.save();
  }

  Future<void> setResignIfMostLose(bool value) async {
    setState(() {
      Config.resignIfMostLose = value;
    });

   debugPrint("[config] resignIfMostLose: $value");

    Config.save();
  }

  Future<void> setShufflingEnabled(bool value) async {
    setState(() {
      Config.shufflingEnabled = value;
    });

   debugPrint("[config] shufflingEnabled: $value");

    Config.save();
  }

  Future<void> setLearnEndgame(bool value) async {
    setState(() {
      Config.learnEndgame = value;
    });

   debugPrint("[config] learnEndgame: $value");

    Config.save();
  }

  Future<void> setOpeningBook(bool value) async {
    setState(() {
      Config.openingBook = value;
    });

   debugPrint("[config] openingBook: $value");

    Config.save();
  }

  Future<void> setTone(bool value) async {
    setState(() {
      Config.toneEnabled = value;
    });

   debugPrint("[config] toneEnabled: $value");

    Config.save();
  }

  Future<void> setKeepMuteWhenTakingBack(bool value) async {
    setState(() {
      Config.keepMuteWhenTakingBack = value;
    });

   debugPrint("[config] keepMuteWhenTakingBack: $value");

    Config.save();
  }

  Future<void> setScreenReaderSupport(bool value) async {
    setState(() {
      Config.screenReaderSupport = value;
    });

   debugPrint("[config] screenReaderSupport: $value");

    Config.save();
  }

  Future<void> setDeveloperMode(bool value) async {
    setState(() {
      Config.developerMode = value;
    });

   debugPrint("[config] developerMode: $value");

    Config.save();
  }

  Future<void> setExperimentsEnabled(bool value) async {
    setState(() {
      Config.experimentsEnabled = value;
    });

   debugPrint("[config] experimentsEnabled: $value");

    Config.save();
  }

  // Display

  Future<void> setLanguage(String value) async {
    setState(() {
      Config.languageCode = value;
    });

   debugPrint("[config] languageCode: $value");

    Config.save();
  }

  Future<void> setIsPieceCountInHandShown(bool value) async {
    setState(() {
      Config.isPieceCountInHandShown = value;
    });

   debugPrint("[config] isPieceCountInHandShown: $value");

    Config.save();
  }

  Future<void> setIsNotationsShown(bool value) async {
    setState(() {
      Config.isNotationsShown = value;
    });

   debugPrint("[config] isNotationsShown: $value");

    Config.save();
  }

  Future<void> setIsHistoryNavigationToolbarShown(bool value) async {
    setState(() {
      Config.isHistoryNavigationToolbarShown = value;
    });

   debugPrint("[config] isHistoryNavigationToolbarShown: $value");

    Config.save();
  }

  Future<void> setStandardNotationEnabled(bool value) async {
    setState(() {
      Config.standardNotationEnabled = value;
    });

   debugPrint("[config] standardNotationEnabled: $value");

    Config.save();
  }
}
