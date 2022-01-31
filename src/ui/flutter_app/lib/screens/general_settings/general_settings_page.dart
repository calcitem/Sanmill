// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/general_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/settings/settings.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/screens/general_settings/algorithm_modal.dart';
part 'package:sanmill/screens/general_settings/move_time_slider.dart';
part 'package:sanmill/screens/general_settings/reset_settings_alert.dart';
part 'package:sanmill/screens/general_settings/skill_level_slider.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({Key? key}) : super(key: key);
  static const String _tag = "[general_settings_page]";

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

  void _setWhoMovesFirst(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(aiMovesFirst: value);

    logger.v("$_tag aiMovesFirst: $value");
  }

  void _setAiIsLazy(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(aiIsLazy: value);

    logger.v("$_tag aiIsLazy: $value");
  }

  void _setAlgorithm(BuildContext context, GeneralSettings _generalSettings) {
    void _callback(Algorithms? algorithm) {
      Navigator.pop(context);

      DB().generalSettings = _generalSettings.copyWith(algorithm: algorithm);

      logger.v("$_tag algorithm = $algorithm");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _AlgorithmModal(
        algorithm: _generalSettings.algorithm!,
        onChanged: _callback,
      ),
    );
  }

  void _setDrawOnHumanExperience(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings =
        _generalSettings.copyWith(drawOnHumanExperience: value);

    logger.v("$_tag drawOnHumanExperience: $value");
  }

  void _setConsiderMobility(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(considerMobility: value);

    logger.v("$_tag considerMobility: $value");
  }

  void _setIsAutoRestart(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(isAutoRestart: value);

    logger.v("$_tag isAutoRestart: $value");
  }

  void _setShufflingEnabled(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(shufflingEnabled: value);

    logger.v("$_tag shufflingEnabled: $value");
  }

  void _setTone(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings = _generalSettings.copyWith(toneEnabled: value);

    logger.v("$_tag toneEnabled: $value");
  }

  void _setKeepMuteWhenTakingBack(
    GeneralSettings _generalSettings,
    bool value,
  ) {
    DB().generalSettings =
        _generalSettings.copyWith(keepMuteWhenTakingBack: value);

    logger.v("$_tag keepMuteWhenTakingBack: $value");
  }

  void _setScreenReaderSupport(GeneralSettings _generalSettings, bool value) {
    DB().generalSettings =
        _generalSettings.copyWith(screenReaderSupport: value);

    logger.v("$_tag screenReaderSupport: $value");
  }

  SettingsList _buildGeneralSettingsList(
    BuildContext context,
    Box<GeneralSettings> box,
    _,
  ) {
    final GeneralSettings _generalSettings = box.get(
      DB.generalSettingsKey,
      defaultValue: const GeneralSettings(),
    )!;

    return SettingsList(
      children: [
        SettingsCard(
          title: Text(S.of(context).whoMovesFirst),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: !_generalSettings.aiMovesFirst,
              onChanged: (val) => _setWhoMovesFirst(_generalSettings, !val),
              titleString: _generalSettings.aiMovesFirst
                  ? S.of(context).ai
                  : S.of(context).human,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).difficulty),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).skillLevel,
              //trailingString: "L" + DB().generalSettings.skillLevel.toString(),
              onTap: () => _setSkillLevel(context),
            ),
            SettingsListTile(
              titleString: S.of(context).moveTime,
              onTap: () => _setMoveTime(context),
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).aisPlayStyle),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).algorithm,
              trailingString: _generalSettings.algorithm!.name,
              onTap: () => _setAlgorithm(context, _generalSettings),
            ),
            SettingsListTile.switchTile(
              value: _generalSettings.drawOnHumanExperience,
              onChanged: (val) =>
                  _setDrawOnHumanExperience(_generalSettings, val),
              titleString: S.of(context).drawOnHumanExperience,
            ),
            SettingsListTile.switchTile(
              value: _generalSettings.considerMobility,
              onChanged: (val) => _setConsiderMobility(_generalSettings, val),
              titleString: S.of(context).considerMobility,
            ),
            SettingsListTile.switchTile(
              value: _generalSettings.aiIsLazy,
              onChanged: (val) => _setAiIsLazy(_generalSettings, val),
              titleString: S.of(context).passive,
            ),
            SettingsListTile.switchTile(
              value: _generalSettings.shufflingEnabled,
              onChanged: (val) => _setShufflingEnabled(_generalSettings, val),
              titleString: S.of(context).shufflingEnabled,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).playSounds),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _generalSettings.toneEnabled,
              onChanged: (val) => _setTone(_generalSettings, val),
              titleString: S.of(context).playSoundsInTheGame,
            ),
            SettingsListTile.switchTile(
              value: _generalSettings.keepMuteWhenTakingBack,
              onChanged: (val) =>
                  _setKeepMuteWhenTakingBack(_generalSettings, val),
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).accessibility),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _generalSettings.screenReaderSupport,
              onChanged: (val) =>
                  _setScreenReaderSupport(_generalSettings, val),
              titleString: S.of(context).screenReaderSupport,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).misc),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: _generalSettings.isAutoRestart,
              onChanged: (val) => _setIsAutoRestart(_generalSettings, val),
              titleString: S.of(context).isAutoRestart,
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).restore),
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
        title: Text(S.of(context).generalSettings),
      ),
      body: ValueListenableBuilder(
        valueListenable: DB().listenGeneralSettings,
        builder: _buildGeneralSettingsList,
      ),
    );
  }
}
