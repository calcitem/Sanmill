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
import 'package:sanmill/screens/env_page.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/services/storage/storage_v1.dart';
import 'package:sanmill/shared/dialog.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

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

  SliderTheme _skillLevelSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).skillLevel,
        child: Slider(
          value: LocalDatabaseService.preferences.skillLevel.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: LocalDatabaseService.preferences.skillLevel.toString(),
          onChanged: (value) => setState(() {
            debugPrint("[config] Slider value: $value");
            LocalDatabaseService.preferences.skillLevel = value.toInt();
          }),
        ),
      ),
    );
  }

  SliderTheme _moveTimeSliderTheme(BuildContext context, Function setState) {
    return SliderTheme(
      data: AppTheme.sliderThemeData,
      child: Semantics(
        label: S.of(context).moveTime,
        child: Slider(
          value: LocalDatabaseService.preferences.moveTime.toDouble(),
          max: 60,
          divisions: 60,
          label: LocalDatabaseService.preferences.moveTime.toString(),
          onChanged: (value) => setState(() {
            debugPrint("[config] Slider value: $value");
            LocalDatabaseService.preferences.moveTime = value.toInt();
          }),
        ),
      ),
    );
  }

  // Restore

  Future<void> restoreFactoryDefaultSettings() async {
    Future<void> confirm() async {
      Navigator.pop(context);
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

    void cancel() => Navigator.pop(context);

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
              fontSize: LocalDatabaseService.display.fontSize + 4,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              "${S.of(context).restoreDefaultSettings}?\n$prompt",
              style: TextStyle(
                fontSize: LocalDatabaseService.display.fontSize,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: confirm,
              child: Text(
                S.of(context).ok,
                style: TextStyle(
                  fontSize: LocalDatabaseService.display.fontSize,
                ),
              ),
            ),
            TextButton(
              onPressed: cancel,
              child: Text(
                S.of(context).cancel,
                style: TextStyle(
                  fontSize: LocalDatabaseService.display.fontSize,
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
        children: <Widget>[
          SettingsSwitchListTile(
            value: !LocalDatabaseService.preferences.aiMovesFirst,
            onChanged: setWhoMovesFirst,
            titleString: LocalDatabaseService.preferences.aiMovesFirst
                ? S.of(context).ai
                : S.of(context).human,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).difficulty, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).skillLevel,
            //trailingString: "L" + LocalDatabaseService.preferences.skillLevel.toString(),
            onTap: setSkillLevel,
          ),
          SettingsListTile(
            titleString: S.of(context).moveTime,
            onTap: setMoveTime,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).algorithm,
            trailingString:
                algorithmNames[LocalDatabaseService.preferences.algorithm],
            onTap: setAlgorithm,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.preferences.drawOnHumanExperience,
            onChanged: setDrawOnHumanExperience,
            titleString: S.of(context).drawOnHumanExperience,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.preferences.considerMobility,
            onChanged: setConsiderMobility,
            titleString: S.of(context).considerMobility,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.preferences.aiIsLazy,
            onChanged: setAiIsLazy,
            titleString: S.of(context).passive,
          ),
          SettingsSwitchListTile(
            value: LocalDatabaseService.preferences.shufflingEnabled,
            onChanged: setShufflingEnabled,
            titleString: S.of(context).shufflingEnabled,
          ),
        ],
      ),
      if (!Platform.isWindows) const SizedBox(height: AppTheme.sizedBoxHeight),
      if (!Platform.isWindows)
        Text(S.of(context).playSounds, style: AppTheme.settingsHeaderStyle),
      if (!Platform.isWindows)
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: LocalDatabaseService.preferences.toneEnabled,
              onChanged: setTone,
              titleString: S.of(context).playSoundsInTheGame,
            ),
            SettingsSwitchListTile(
              value: LocalDatabaseService.preferences.keepMuteWhenTakingBack,
              onChanged: setKeepMuteWhenTakingBack,
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
          ],
        ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).accessibility, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsSwitchListTile(
            value: LocalDatabaseService.preferences.screenReaderSupport,
            onChanged: setScreenReaderSupport,
            titleString: S.of(context).screenReaderSupport,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      Text(S.of(context).restore, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile(
            titleString: S.of(context).restoreDefaultSettings,
            onTap: restoreFactoryDefaultSettings,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.sizedBoxHeight),
      if (Developer.developerModeEnabled)
        Text(
          S.of(context).forDevelopers,
          style: AppTheme.settingsHeaderStyle,
        ),
      if (Developer.developerModeEnabled)
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: LocalDatabaseService.preferences.developerMode,
              onChanged: setDeveloperMode,
              titleString: S.of(context).developerMode,
            ),
            SettingsSwitchListTile(
              value: LocalDatabaseService.preferences.experimentsEnabled,
              onChanged: setExperimentsEnabled,
              titleString: S.of(context).experiments,
            ),
            SettingsSwitchListTile(
              value: LocalDatabaseService.preferences.isAutoRestart,
              onChanged: setIsAutoRestart,
              titleString: S.of(context).isAutoRestart,
            ),
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
        ),
    ];
  }

  Future<void> setSkillLevel() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: _skillLevelSliderTheme,
      ),
    );
  }

  Future<void> setMoveTime() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: _moveTimeSliderTheme,
      ),
    );
  }

  Future<void> setWhoMovesFirst(bool value) async {
    setState(() => LocalDatabaseService.preferences.aiMovesFirst = !value);

    debugPrint(
      "[config] aiMovesFirst: ${LocalDatabaseService.preferences.aiMovesFirst}",
    );
  }

  Future<void> setAiIsLazy(bool value) async {
    setState(() => LocalDatabaseService.preferences.aiIsLazy = value);

    debugPrint("[config] aiMovesFirst: $value");
  }

  void setAlgorithm() {
    Future<void> callback(int? algorithm) async {
      debugPrint("[config] algorithm = $algorithm");

      Navigator.pop(context);

      setState(
        () => LocalDatabaseService.preferences.algorithm = algorithm ?? 2,
      );

      debugPrint(
        "[config] LocalDatabaseService.preferences.algorithm: ${LocalDatabaseService.preferences.algorithm}",
      );
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
              groupValue: LocalDatabaseService.preferences.algorithm,
              value: 0,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('PVS'),
              groupValue: LocalDatabaseService.preferences.algorithm,
              value: 1,
              onChanged: callback,
            ),
            RadioListTile(
              activeColor: AppTheme.switchListTileActiveColor,
              title: const Text('MTD(f)'),
              groupValue: LocalDatabaseService.preferences.algorithm,
              value: 2,
              onChanged: callback,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> setDrawOnHumanExperience(bool value) async {
    setState(
      () => LocalDatabaseService.preferences.drawOnHumanExperience = value,
    );

    debugPrint("[config] drawOnHumanExperience: $value");
  }

  Future<void> setConsiderMobility(bool value) async {
    setState(() => LocalDatabaseService.preferences.considerMobility = value);

    debugPrint("[config] considerMobility: $value");
  }

  Future<void> setIsAutoRestart(bool value) async {
    setState(() => LocalDatabaseService.preferences.isAutoRestart = value);

    debugPrint("[config] isAutoRestart: $value");
  }

  Future<void> setIsAutoChangeFirstMove(bool value) async {
    setState(
      () => LocalDatabaseService.preferences.isAutoChangeFirstMove = value,
    );

    debugPrint("[config] isAutoChangeFirstMove: $value");
  }

  Future<void> setResignIfMostLose(bool value) async {
    setState(() => LocalDatabaseService.preferences.resignIfMostLose = value);

    debugPrint("[config] resignIfMostLose: $value");
  }

  Future<void> setShufflingEnabled(bool value) async {
    setState(() => LocalDatabaseService.preferences.shufflingEnabled = value);

    debugPrint("[config] shufflingEnabled: $value");
  }

  Future<void> setLearnEndgame(bool value) async {
    setState(() => LocalDatabaseService.preferences.learnEndgame = value);

    debugPrint("[config] learnEndgame: $value");
  }

  Future<void> setOpeningBook(bool value) async {
    setState(() => LocalDatabaseService.preferences.openingBook = value);

    debugPrint("[config] openingBook: $value");
  }

  Future<void> setTone(bool value) async {
    setState(() => LocalDatabaseService.preferences.toneEnabled = value);

    debugPrint("[config] toneEnabled: $value");
  }

  Future<void> setKeepMuteWhenTakingBack(bool value) async {
    setState(
      () => LocalDatabaseService.preferences.keepMuteWhenTakingBack = value,
    );

    debugPrint("[config] keepMuteWhenTakingBack: $value");
  }

  Future<void> setScreenReaderSupport(bool value) async {
    setState(
      () => LocalDatabaseService.preferences.screenReaderSupport = value,
    );

    debugPrint("[config] screenReaderSupport: $value");
  }

  Future<void> setDeveloperMode(bool value) async {
    setState(() => LocalDatabaseService.preferences.developerMode = value);

    debugPrint("[config] developerMode: $value");
  }

  Future<void> setExperimentsEnabled(bool value) async {
    setState(() => LocalDatabaseService.preferences.experimentsEnabled = value);

    debugPrint("[config] experimentsEnabled: $value");
  }

  // Display

  Future<void> setLanguage(Locale value) async {
    setState(() => LocalDatabaseService.display.languageCode = value);

    debugPrint("[config] languageCode: $value");
  }

  Future<void> setIsPieceCountInHandShown(bool value) async {
    setState(
      () => LocalDatabaseService.display.isPieceCountInHandShown = value,
    );

    debugPrint("[config] isPieceCountInHandShown: $value");
  }

  Future<void> setIsNotationsShown(bool value) async {
    setState(() => LocalDatabaseService.display.isNotationsShown = value);

    debugPrint("[config] isNotationsShown: $value");
  }

  Future<void> setIsHistoryNavigationToolbarShown(bool value) async {
    setState(
      () =>
          LocalDatabaseService.display.isHistoryNavigationToolbarShown = value,
    );

    debugPrint("[config] isHistoryNavigationToolbarShown: $value");
  }

  Future<void> setStandardNotationEnabled(bool value) async {
    setState(
      () => LocalDatabaseService.display.standardNotationEnabled = value,
    );

    debugPrint("[config] standardNotationEnabled: $value");
  }
}
