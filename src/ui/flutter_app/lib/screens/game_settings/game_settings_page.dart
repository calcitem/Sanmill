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
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/screens/env_page.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/settings/settings_card.dart';
import 'package:sanmill/shared/settings/settings_list_tile.dart';
import 'package:sanmill/shared/settings/settings_switch_list_tile.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/game_settings/algorithm_modal.dart';
part 'package:sanmill/screens/game_settings/reset_settings_alert.dart';
part 'package:sanmill/screens/game_settings/skill_level_slider.dart';
part 'package:sanmill/screens/game_settings/move_time_slider.dart';

class GameSettingsPage extends StatelessWidget {
  static const List<String> _algorithmNames = ['Alpha-Beta', 'PVS', 'MTD(f)'];

  static const String _tag = "[game_settings_page]";

  // Restore
  void restoreFactoryDefaultSettings(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const _ResetSettingsAlert(),
      );

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
        child: ValueListenableBuilder(
          valueListenable: LocalDatabaseService.listenPreferences,
          builder: (context, Box<Preferences> prefBox, _) {
            final Preferences _preferences = prefBox.get(
              LocalDatabaseService.preferencesKey,
              defaultValue: const Preferences(),
            )!;

            return _child(context, _preferences);
          },
        ),
      ),
    );
  }

  Column _child(BuildContext context, Preferences _preferences) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).whoMovesFirst, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: !_preferences.aiMovesFirst,
              onChanged: (val) => setWhoMovesFirst(_preferences, !val),
              titleString: _preferences.aiMovesFirst
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
              onTap: () => setSkillLevel(context),
            ),
            SettingsListTile(
              titleString: S.of(context).moveTime,
              onTap: () => setMoveTime(context),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).algorithm,
              trailingString: _algorithmNames[_preferences.algorithm],
              onTap: () => setAlgorithm(context, _preferences),
            ),
            SettingsSwitchListTile(
              value: _preferences.drawOnHumanExperience,
              onChanged: (val) => setDrawOnHumanExperience(_preferences, val),
              titleString: S.of(context).drawOnHumanExperience,
            ),
            SettingsSwitchListTile(
              value: _preferences.considerMobility,
              onChanged: (val) => setConsiderMobility(_preferences, val),
              titleString: S.of(context).considerMobility,
            ),
            SettingsSwitchListTile(
              value: _preferences.aiIsLazy,
              onChanged: (val) => setAiIsLazy(_preferences, val),
              titleString: S.of(context).passive,
            ),
            SettingsSwitchListTile(
              value: _preferences.shufflingEnabled,
              onChanged: (val) => setShufflingEnabled(_preferences, val),
              titleString: S.of(context).shufflingEnabled,
            ),
          ],
        ),
        if (!Platform.isWindows)
          const SizedBox(height: AppTheme.sizedBoxHeight),
        if (!Platform.isWindows)
          Text(S.of(context).playSounds, style: AppTheme.settingsHeaderStyle),
        if (!Platform.isWindows)
          SettingsCard(
            children: <Widget>[
              SettingsSwitchListTile(
                value: _preferences.toneEnabled,
                onChanged: (val) => setTone(_preferences, val),
                titleString: S.of(context).playSoundsInTheGame,
              ),
              SettingsSwitchListTile(
                value: _preferences.keepMuteWhenTakingBack,
                onChanged: (val) =>
                    setKeepMuteWhenTakingBack(_preferences, val),
                titleString: S.of(context).keepMuteWhenTakingBack,
              ),
            ],
          ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        Text(S.of(context).accessibility, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsSwitchListTile(
              value: _preferences.screenReaderSupport,
              onChanged: (val) => setScreenReaderSupport(_preferences, val),
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
              onTap: () => restoreFactoryDefaultSettings(context),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sizedBoxHeight),
        if (_preferences.developerMode)
          Text(
            S.of(context).forDevelopers,
            style: AppTheme.settingsHeaderStyle,
          ),
        if (_preferences.developerMode)
          SettingsCard(
            children: <Widget>[
              SettingsSwitchListTile(
                value: _preferences.developerMode,
                onChanged: (val) => setDeveloperMode(_preferences, val),
                titleString: S.of(context).developerMode,
              ),
              SettingsSwitchListTile(
                value: _preferences.experimentsEnabled,
                onChanged: (val) => setExperimentsEnabled(_preferences, val),
                titleString: S.of(context).experiments,
              ),
              SettingsSwitchListTile(
                value: _preferences.isAutoRestart,
                onChanged: (val) => setIsAutoRestart(_preferences, val),
                titleString: S.of(context).isAutoRestart,
              ),
              SettingsListTile(
                titleString: S.of(context).environmentVariables,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EnvironmentVariablesPage(),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void setSkillLevel(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _SkillLevelSlider(),
      );

  void setMoveTime(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _MoveTimeSlider(),
      );

  void setWhoMovesFirst(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(aiMovesFirst: value);

    debugPrint(
      "$_tag aiMovesFirst: $value",
    );
  }

  void setAiIsLazy(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences = _preferences.copyWith(aiIsLazy: value);

    debugPrint("$_tag aiMovesFirst: $value");
  }

  void setAlgorithm(BuildContext context, Preferences _preferences) {
    void callback(int? algorithm) {
      debugPrint("$_tag algorithm = $algorithm");

      Navigator.pop(context);
      LocalDatabaseService.preferences =
          _preferences.copyWith(algorithm: algorithm);

      debugPrint(
        "$_tag LocalDatabaseService.preferences.algorithm: ${_preferences.algorithm}",
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _AlgorithmModal(
        algorithm: _preferences.algorithm,
        onChanged: callback,
      ),
    );
  }

  void setDrawOnHumanExperience(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(drawOnHumanExperience: value);

    debugPrint("$_tag drawOnHumanExperience: $value");
  }

  void setConsiderMobility(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(considerMobility: value);

    debugPrint("$_tag considerMobility: $value");
  }

  void setIsAutoRestart(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(isAutoRestart: value);

    debugPrint("$_tag isAutoRestart: $value");
  }

  void setIsAutoChangeFirstMove(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(isAutoChangeFirstMove: value);

    debugPrint("$_tag isAutoChangeFirstMove: $value");
  }

  void setResignIfMostLose(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(resignIfMostLose: value);

    debugPrint("$_tag resignIfMostLose: $value");
  }

  void setShufflingEnabled(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(shufflingEnabled: value);

    debugPrint("$_tag shufflingEnabled: $value");
  }

  void setLearnEndgame(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(learnEndgame: value);

    debugPrint("$_tag learnEndgame: $value");
  }

  void setOpeningBook(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(openingBook: value);

    debugPrint("$_tag openingBook: $value");
  }

  void setTone(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(toneEnabled: value);

    debugPrint("$_tag toneEnabled: $value");
  }

  void setKeepMuteWhenTakingBack(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(keepMuteWhenTakingBack: value);

    debugPrint("$_tag keepMuteWhenTakingBack: $value");
  }

  void setScreenReaderSupport(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(screenReaderSupport: value);

    debugPrint("$_tag screenReaderSupport: $value");
  }

  void setDeveloperMode(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(developerMode: value);

    debugPrint("$_tag developerMode: $value");
  }

  void setExperimentsEnabled(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(experimentsEnabled: value);

    debugPrint("$_tag experimentsEnabled: $value");
  }

  // Display

  void setLanguage(Display _display, Locale value) {
    LocalDatabaseService.display = _display.copyWith(languageCode: value);

    debugPrint("$_tag languageCode: $value");
  }

  void setIsPieceCountInHandShown(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(isPieceCountInHandShown: value);

    debugPrint("$_tag isPieceCountInHandShown: $value");
  }

  void setIsNotationsShown(Display _display, bool value) {
    LocalDatabaseService.display = _display.copyWith(isNotationsShown: value);

    debugPrint("$_tag isNotationsShown: $value");
  }

  void setIsHistoryNavigationToolbarShown(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(isHistoryNavigationToolbarShown: value);

    debugPrint("$_tag isHistoryNavigationToolbarShown: $value");
  }

  void setStandardNotationEnabled(Display _display, bool value) {
    LocalDatabaseService.display =
        _display.copyWith(standardNotationEnabled: value);

    debugPrint("$_tag standardNotationEnabled: $value");
  }
}
