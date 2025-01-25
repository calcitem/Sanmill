// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;

import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/perfect_database_service.dart';
import '../../shared/services/url.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/general_settings.dart';

part 'dialogs/reset_settings_alert_dialog.dart';
part 'dialogs/use_perfect_database_dialog.dart';
part 'modals/algorithm_modal.dart';
part 'modals/duration_modal.dart';
part 'modals/ratio_modal.dart';
part 'modals/sound_theme_modal.dart';
part 'pickers/skill_level_picker.dart';
part 'sliders/move_time_slider.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});
  static const String _logTag = "[general_settings_page]";

  // Restore
  void _restoreFactoryDefaultSettings(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const _ResetSettingsAlertDialog(),
      );

  void _setSkillLevel(BuildContext context) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _SkillLevelPicker(),
      );

  void _setMoveTime(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _MoveTimeSlider(),
      );

  void _setWhoMovesFirst(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(aiMovesFirst: value);

    if (GameController().position.isEmpty()) {
      GameController().position.changeSideToMove();
      GameController().reset(force: true);
    }

    Position.resetScore();

    logger.t("$_logTag aiMovesFirst: $value");
  }

  void _setAiIsLazy(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(aiIsLazy: value);

    logger.t("$_logTag aiIsLazy: $value");
  }

  void _setAlgorithm(BuildContext context, GeneralSettings generalSettings) {
    void callback(SearchAlgorithm? searchAlgorithm) {
      DB().generalSettings =
          generalSettings.copyWith(searchAlgorithm: searchAlgorithm);

      switch (searchAlgorithm) {
        case SearchAlgorithm.alphaBeta:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).whatIsAlphaBeta);
          break;
        case SearchAlgorithm.pvs:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).whatIsPvs);
          break;
        case SearchAlgorithm.mtdf:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).whatIsMtdf);
          break;
        case SearchAlgorithm.mcts:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).whatIsMcts);
          break;
        // TODO: Add whatIsRandom
        case SearchAlgorithm.random:
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear(S.of(context).whatIsRandom);
          break;
        case null:
          break;
      }

      logger.t("$_logTag algorithm = $searchAlgorithm");

      Navigator.pop(context);
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _AlgorithmModal(
        algorithm: generalSettings.searchAlgorithm!,
        onChanged: callback,
      ),
    );
  }

  void _setUseOpeningBook(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(useOpeningBook: value);

    logger.t("$_logTag useOpeningBook: $value");
  }

  void _setUsePerfectDatabase(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(usePerfectDatabase: value);

    logger.t("$_logTag usePerfectDatabase: $value");

    if (value == true) {
      copyPerfectDatabaseFiles();
    }
  }

  void _showUsePerfectDatabaseDialog(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const _UsePerfectDatabaseDialog(),
      );

  void _setDrawOnHumanExperience(GeneralSettings generalSettings, bool value) {
    DB().generalSettings =
        generalSettings.copyWith(drawOnHumanExperience: value);

    logger.t("$_logTag drawOnHumanExperience: $value");
  }

  void _setConsiderMobility(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(considerMobility: value);

    logger.t("$_logTag considerMobility: $value");
  }

  void _setFocusOnBlockingPaths(GeneralSettings generalSettings, bool value) {
    DB().generalSettings =
        generalSettings.copyWith(focusOnBlockingPaths: value);

    logger.t("$_logTag focusOnBlockingPaths: $value");
  }

  void _setIsAutoRestart(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(isAutoRestart: value);

    logger.t("$_logTag isAutoRestart: $value");
  }

  void _setShufflingEnabled(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(shufflingEnabled: value);

    logger.t("$_logTag shufflingEnabled: $value");
  }

  void _setTone(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(toneEnabled: value);

    logger.t("$_logTag toneEnabled: $value");
  }

  void _setKeepMuteWhenTakingBack(
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings =
        generalSettings.copyWith(keepMuteWhenTakingBack: value);

    logger.t("$_logTag keepMuteWhenTakingBack: $value");
  }

  void _setSoundTheme(BuildContext context, GeneralSettings generalSettings) {
    void callback(SoundTheme? soundTheme) {
      DB().generalSettings = generalSettings.copyWith(soundTheme: soundTheme);

      logger.t("$_logTag soundTheme = $soundTheme");

      // TODO: Take effect on iOS
      if (Platform.isIOS) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear(S.of(context).reopenToTakeEffect);
      } else {
        SoundManager().loadSounds();
      }

      Navigator.pop(context);
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _SoundThemeModal(
        soundTheme: generalSettings.soundTheme!,
        onChanged: callback,
      ),
    );
  }

  void _setVibration(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(vibrationEnabled: value);

    logger.t("$_logTag vibrationEnabled: $value");
  }

  void _setScreenReaderSupport(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(screenReaderSupport: value);

    logger.t("$_logTag screenReaderSupport: $value");
  }

  void _setGameScreenRecorderSupport(
      GeneralSettings generalSettings, bool value) {
    DB().generalSettings =
        generalSettings.copyWith(gameScreenRecorderSupport: value);

    logger.t("$_logTag gameScreenRecorderSupport: $value");
  }

  void _setGameScreenRecorderDuration(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    void callback(int? duration) {
      Navigator.pop(context);

      DB().generalSettings =
          generalSettings.copyWith(gameScreenRecorderDuration: duration ?? 2);

      logger.t("[config] gameScreenRecorderDuration = ${duration ?? 2}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _DurationModal(
        duration: generalSettings.gameScreenRecorderDuration,
        onChanged: callback,
      ),
    );
  }

  void _setGameScreenRecorderPixelRatio(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    void callback(int? ratio) {
      // TODO: Take effect when start new game
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).reopenToTakeEffect);

      Navigator.pop(context);

      DB().generalSettings =
          generalSettings.copyWith(gameScreenRecorderPixelRatio: ratio ?? 50);

      logger.t("[config] gameScreenRecorderPixelRatio = ${ratio ?? 50}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _RatioModal(
        ratio: generalSettings.gameScreenRecorderPixelRatio,
        onChanged: callback,
      ),
    );
  }

  SettingsList _buildGeneralSettingsList(
    BuildContext context,
    Box<GeneralSettings> box,
    _,
  ) {
    final GeneralSettings generalSettings = box.get(
      DB.generalSettingsKey,
      defaultValue: const GeneralSettings(),
    )!;

    final String perfectDatabaseDescription =
        S.of(context).perfectDatabaseDescription;
    final String perfectDatabaseDescriptionFistLine =
        perfectDatabaseDescription.contains('\n')
            ? perfectDatabaseDescription.substring(
                0, perfectDatabaseDescription.indexOf('\n'))
            : perfectDatabaseDescription;

    return SettingsList(
      children: <Widget>[
        SettingsCard(
          title: Text(S.of(context).whoMovesFirst),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: !generalSettings.aiMovesFirst,
              onChanged: (bool val) {
                _setWhoMovesFirst(generalSettings, !val);
                if (val == false &&
                    DB().ruleSettings.isLikelyNineMensMorris()) {
                  rootScaffoldMessengerKey.currentState!
                      .showSnackBarClear(S.of(context).firstMoveDetail);
                }
              },
              titleString: generalSettings.aiMovesFirst
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
              trailingString: DB().generalSettings.skillLevel.toString(),
              onTap: () {
                if (EnvironmentConfig.test == false) {
                  _setSkillLevel(context);
                }
              },
            ),
            SettingsListTile(
              titleString: S.of(context).moveTime,
              trailingString: DB().generalSettings.moveTime.toString(),
              onTap: () => _setMoveTime(context),
            ),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).aisPlayStyle),
          children: <Widget>[
            SettingsListTile(
              titleString: S.of(context).algorithm,
              trailingString: generalSettings.searchAlgorithm!.name,
              onTap: () => _setAlgorithm(context, generalSettings),
            ),
            if (DB().ruleSettings.isLikelyNineMensMorris() ||
                DB().ruleSettings.isLikelyElFilja())
              SettingsListTile.switchTile(
                value: generalSettings.useOpeningBook,
                onChanged: (bool val) {
                  if (val == true) {
                    _setUseOpeningBook(generalSettings, true);
                  } else {
                    _setUseOpeningBook(generalSettings, false);
                  }
                },
                titleString: S.of(context).useOpeningBook,
                subtitleString: S.of(context).useOpeningBook_Detail,
              ),
            if (!kIsWeb)
              SettingsListTile.switchTile(
                value: generalSettings.usePerfectDatabase,
                onChanged: (bool val) {
                  if (val == true) {
                    _showUsePerfectDatabaseDialog(context);
                    if (Engine.isRuleSupportingPerfectDatabase() == true) {
                      _setUsePerfectDatabase(generalSettings, true);
                    }
                  } else {
                    _setUsePerfectDatabase(generalSettings, false);
                  }
                },
                titleString: S.of(context).usePerfectDatabase,
                subtitleString: perfectDatabaseDescriptionFistLine,
              ),
            SettingsListTile.switchTile(
              value: generalSettings.drawOnHumanExperience,
              onChanged: (bool val) {
                _setDrawOnHumanExperience(generalSettings, val);
              },
              titleString: S.of(context).drawOnHumanExperience,
              subtitleString: S.of(context).drawOnTheHumanExperienceDetail,
            ),
            SettingsListTile.switchTile(
              value: generalSettings.considerMobility,
              onChanged: (bool val) {
                _setConsiderMobility(generalSettings, val);
              },
              titleString: S.of(context).considerMobility,
              subtitleString: S.of(context).considerMobilityOfPiecesDetail,
            ),
            SettingsListTile.switchTile(
              value: generalSettings.focusOnBlockingPaths,
              onChanged: (bool val) {
                _setFocusOnBlockingPaths(generalSettings, val);
              },
              titleString: S.of(context).focusOnBlockingPaths,
              subtitleString: S.of(context).focusOnBlockingPaths_Detail,
            ),
            SettingsListTile.switchTile(
              value: generalSettings.aiIsLazy,
              onChanged: (bool val) {
                _setAiIsLazy(generalSettings, val);
              },
              titleString: S.of(context).passive,
              subtitleString: S.of(context).passiveDetail,
            ),
            SettingsListTile.switchTile(
                value: generalSettings.shufflingEnabled,
                onChanged: (bool val) {
                  _setShufflingEnabled(generalSettings, val);
                },
                titleString: S.of(context).shufflingEnabled,
                subtitleString: S.of(context).moveRandomlyDetail),
          ],
        ),
        SettingsCard(
          title: Text(S.of(context).playSounds),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: generalSettings.toneEnabled,
              onChanged: (bool val) => _setTone(generalSettings, val),
              titleString: S.of(context).playSoundsInTheGame,
            ),
            SettingsListTile.switchTile(
              value: generalSettings.keepMuteWhenTakingBack,
              onChanged: (bool val) =>
                  _setKeepMuteWhenTakingBack(generalSettings, val),
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
            SettingsListTile(
              titleString: S.of(context).soundTheme,
              trailingString: generalSettings.soundTheme!.localeName(context),
              onTap: () => _setSoundTheme(context, generalSettings),
            ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              SettingsListTile.switchTile(
                value: generalSettings.vibrationEnabled,
                onChanged: (bool val) => _setVibration(generalSettings, val),
                titleString: S.of(context).vibration,
              ),
          ],
        ),
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
          SettingsCard(
            title: Text(S.of(context).accessibility),
            children: <Widget>[
              SettingsListTile.switchTile(
                value: generalSettings.screenReaderSupport,
                onChanged: (bool val) {
                  _setScreenReaderSupport(generalSettings, val);
                  rootScaffoldMessengerKey.currentState!
                      .showSnackBarClear(S.of(context).reopenToTakeEffect);
                },
                titleString: S.of(context).screenReaderSupport,
              ),
            ],
          ),
        // TODO: Fix iOS bug
        if (!kIsWeb && (Platform.isAndroid))
          SettingsCard(
            title: Text(S.of(context).gameScreenRecorder),
            children: <Widget>[
              SettingsListTile.switchTile(
                value: generalSettings.gameScreenRecorderSupport,
                onChanged: (bool val) {
                  _setGameScreenRecorderSupport(generalSettings, val);
                  if (val == true) {
                    rootScaffoldMessengerKey.currentState!
                        .showSnackBarClear(S.of(context).experimental);
                  }
                },
                titleString: S.of(context).shareGIF,
              ),
              SettingsListTile(
                titleString: S.of(context).duration,
                trailingString:
                    generalSettings.gameScreenRecorderDuration.toString(),
                onTap: () =>
                    _setGameScreenRecorderDuration(context, generalSettings),
              ),
              SettingsListTile(
                titleString: S.of(context).pixelRatio,
                trailingString:
                    "${generalSettings.gameScreenRecorderPixelRatio}%",
                onTap: () =>
                    _setGameScreenRecorderPixelRatio(context, generalSettings),
              ),
            ],
          ),
        SettingsCard(
          title: Text(S.of(context).misc),
          children: <Widget>[
            SettingsListTile.switchTile(
              value: generalSettings.isAutoRestart,
              onChanged: (bool val) => _setIsAutoRestart(generalSettings, val),
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
    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.lightBackgroundColor,
        appBar: AppBar(
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).generalSettings,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: ValueListenableBuilder<Box<GeneralSettings>>(
          valueListenable: DB().listenGeneralSettings,
          builder: _buildGeneralSettingsList,
        ),
      ),
    );
  }
}
