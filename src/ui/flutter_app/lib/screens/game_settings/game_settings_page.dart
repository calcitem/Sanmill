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
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/preferences.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/custom_spacer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/game_settings/algorithm_modal.dart';
part 'package:sanmill/screens/game_settings/move_time_slider.dart';
part 'package:sanmill/screens/game_settings/reset_settings_alert.dart';
part 'package:sanmill/screens/game_settings/skill_level_slider.dart';

class GameSettingsPage extends StatelessWidget {
  const GameSettingsPage({Key? key}) : super(key: key);
  static const String _tag = "[game_settings_page]";

  // Restore
  void _restoreFactoryDefaultSettings(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const _ResetSettingsAlert(),
      );

  void _setSkillLevel(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _SkillLevelSlider(),
      );

  void _setMoveTime(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _MoveTimeSlider(),
      );

  void _setWhoMovesFirst(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(aiMovesFirst: value);

    logger.v("$_tag aiMovesFirst: $value");
  }

  void _setAiIsLazy(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences = _preferences.copyWith(aiIsLazy: value);

    logger.v("$_tag aiIsLazy: $value");
  }

  void _setAlgorithm(BuildContext context, Preferences _preferences) {
    void _callback(Algorithms? algorithm) {
      Navigator.pop(context);

      LocalDatabaseService.preferences =
          _preferences.copyWith(algorithm: algorithm);

      logger.v("$_tag algorithm = $algorithm");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _AlgorithmModal(
        algorithm: _preferences.algorithm!,
        onChanged: _callback,
      ),
    );
  }

  void _setDrawOnHumanExperience(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(drawOnHumanExperience: value);

    logger.v("$_tag drawOnHumanExperience: $value");
  }

  void _setConsiderMobility(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(considerMobility: value);

    logger.v("$_tag considerMobility: $value");
  }

  void _setIsAutoRestart(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(isAutoRestart: value);

    logger.v("$_tag isAutoRestart: $value");
  }

  void _setShufflingEnabled(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(shufflingEnabled: value);

    logger.v("$_tag shufflingEnabled: $value");
  }

  void _setTone(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(toneEnabled: value);

    logger.v("$_tag toneEnabled: $value");
  }

  void _setKeepMuteWhenTakingBack(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(keepMuteWhenTakingBack: value);

    logger.v("$_tag keepMuteWhenTakingBack: $value");
  }

  void _setScreenReaderSupport(Preferences _preferences, bool value) {
    LocalDatabaseService.preferences =
        _preferences.copyWith(screenReaderSupport: value);

    logger.v("$_tag screenReaderSupport: $value");
  }

  Column _buildPrefs(BuildContext context, Box<Preferences> prefBox, _) {
    final Preferences _preferences = prefBox.get(
      LocalDatabaseService.preferencesKey,
      defaultValue: const Preferences(),
    )!;

    final _widowsSettings = [
      const CustomSpacer(),
      Text(S.of(context).gameSettings, style: AppTheme.settingsHeaderStyle),
      SettingsCard(
        children: <Widget>[
          SettingsListTile.switchTile(
            value: _preferences.isAutoRestart,
            onChanged: (val) => _setIsAutoRestart(_preferences, val),
            titleString: S.of(context).isAutoRestart,
          ),
          SettingsListTile.switchTile(
            value: _preferences.toneEnabled,
            onChanged: (val) => _setTone(_preferences, val),
            titleString: S.of(context).playSoundsInTheGame,
          ),
          SettingsListTile.switchTile(
            value: _preferences.keepMuteWhenTakingBack,
            onChanged: (val) => _setKeepMuteWhenTakingBack(_preferences, val),
            titleString: S.of(context).keepMuteWhenTakingBack,
          ),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).whoMovesFirst, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile.switchTile(
              value: !_preferences.aiMovesFirst,
              onChanged: (val) => _setWhoMovesFirst(_preferences, !val),
              titleString: _preferences.aiMovesFirst
                  ? S.of(context).ai
                  : S.of(context).human,
            ),
          ],
        ),
        const CustomSpacer(),
        Text(S.of(context).difficulty, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).skillLevel,
              //trailingString: "L" + LocalDatabaseService.preferences.skillLevel.toString(),
              onTap: () => _setSkillLevel(context),
            ),
            SettingsListTile(
              titleString: S.of(context).moveTime,
              onTap: () => _setMoveTime(context),
            ),
          ],
        ),
        const CustomSpacer(),
        Text(S.of(context).aisPlayStyle, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).algorithm,
              trailingString: _preferences.algorithm!.name,
              onTap: () => _setAlgorithm(context, _preferences),
            ),
            SettingsListTile.switchTile(
              value: _preferences.drawOnHumanExperience,
              onChanged: (val) => _setDrawOnHumanExperience(_preferences, val),
              titleString: S.of(context).drawOnHumanExperience,
            ),
            SettingsListTile.switchTile(
              value: _preferences.considerMobility,
              onChanged: (val) => _setConsiderMobility(_preferences, val),
              titleString: S.of(context).considerMobility,
            ),
            SettingsListTile.switchTile(
              value: _preferences.aiIsLazy,
              onChanged: (val) => _setAiIsLazy(_preferences, val),
              titleString: S.of(context).passive,
            ),
            SettingsListTile.switchTile(
              value: _preferences.shufflingEnabled,
              onChanged: (val) => _setShufflingEnabled(_preferences, val),
              titleString: S.of(context).shufflingEnabled,
            ),
          ],
        ),
        if (!Platform.isWindows) ..._widowsSettings,
        const CustomSpacer(),
        Text(S.of(context).accessibility, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _preferences.screenReaderSupport,
              onChanged: (val) => _setScreenReaderSupport(_preferences, val),
              titleString: S.of(context).screenReaderSupport,
            ),
          ],
        ),
        const CustomSpacer(),
        Text(S.of(context).restore, style: AppTheme.settingsHeaderStyle),
        SettingsCard(
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).restoreDefaultSettings,
              onTap: () => _restoreFactoryDefaultSettings(context),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackgroundColor,
      appBar: AppBar(
        leading: DrawerIcon.of(context)?.icon,
        title: Text(S.of(context).preferences),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder(
          valueListenable: LocalDatabaseService.listenPreferences,
          builder: _buildPrefs,
        ),
      ),
    );
  }
}
