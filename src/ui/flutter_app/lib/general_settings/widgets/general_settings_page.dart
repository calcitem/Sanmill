// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// general_settings_page.dart

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
import 'dialogs/llm_config_dialog.dart';
import 'dialogs/llm_prompt_dialog.dart';

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

  void _setHumanMoveTime(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => const _HumanMoveTimeSlider(),
      );

  // Show LLM prompt configuration dialog
  void _configureLlmPrompt(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const LlmPromptDialog(),
      );

  // Show LLM provider configuration dialog
  void _configureLlmProvider(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const LlmConfigDialog(),
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
      key: const Key('general_settings_page_settings_list'),
      children: <Widget>[
        SettingsCard(
          key: const Key('general_settings_page_settings_card_who_moves_first'),
          title: Text(
            S.of(context).whoMovesFirst,
            key: const Key(
                'general_settings_page_settings_card_who_moves_first_title'),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_who_moves_first_switch_tile'),
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
          key: const Key('general_settings_page_settings_card_difficulty'),
          title: Text(
            S.of(context).difficulty,
            key: const Key(
                'general_settings_page_settings_card_difficulty_title'),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_difficulty_skill_level'),
              titleString: S.of(context).skillLevel,
              trailingString: DB().generalSettings.skillLevel.toString(),
              onTap: () {
                if (EnvironmentConfig.test == false) {
                  _setSkillLevel(context);
                }
              },
            ),
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_difficulty_move_time'),
              titleString: S.of(context).moveTime,
              trailingString: DB().generalSettings.moveTime.toString(),
              onTap: () => _setMoveTime(context),
            ),
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_difficulty_human_move_time'),
              titleString: S.of(context).humanMoveTime,
              trailingString: DB().generalSettings.humanMoveTime.toString(),
              onTap: () => _setHumanMoveTime(context),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_ais_play_style'),
          title: Text(
            S.of(context).aisPlayStyle,
            key: const Key(
                'general_settings_page_settings_card_ais_play_style_title'),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_ais_play_style_algorithm'),
              titleString: S.of(context).algorithm,
              trailingString: generalSettings.searchAlgorithm!.name,
              onTap: () => _setAlgorithm(context, generalSettings),
            ),
            if (DB().ruleSettings.isLikelyNineMensMorris() ||
                DB().ruleSettings.isLikelyElFilja())
              SettingsListTile.switchTile(
                key: const Key(
                    'general_settings_page_settings_card_ais_play_style_use_opening_book'),
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
                key: const Key(
                    'general_settings_page_settings_card_ais_play_style_use_perfect_database'),
                value: generalSettings.usePerfectDatabase,
                onChanged: (bool val) {
                  if (val == true) {
                    _showUsePerfectDatabaseDialog(context);
                    if (isRuleSupportingPerfectDatabase() == true) {
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
              key: const Key(
                  'general_settings_page_settings_card_ais_play_style_draw_on_human_experience'),
              value: generalSettings.drawOnHumanExperience,
              onChanged: (bool val) {
                _setDrawOnHumanExperience(generalSettings, val);
              },
              titleString: S.of(context).drawOnHumanExperience,
              subtitleString: S.of(context).drawOnTheHumanExperienceDetail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_ais_play_style_consider_mobility'),
              value: generalSettings.considerMobility,
              onChanged: (bool val) {
                _setConsiderMobility(generalSettings, val);
              },
              titleString: S.of(context).considerMobility,
              subtitleString: S.of(context).considerMobilityOfPiecesDetail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_ais_play_style_focus_on_blocking_paths'),
              value: generalSettings.focusOnBlockingPaths,
              onChanged: (bool val) {
                _setFocusOnBlockingPaths(generalSettings, val);
              },
              titleString: S.of(context).focusOnBlockingPaths,
              subtitleString: S.of(context).focusOnBlockingPaths_Detail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_ais_play_style_ai_is_lazy'),
              value: generalSettings.aiIsLazy,
              onChanged: (bool val) {
                _setAiIsLazy(generalSettings, val);
              },
              titleString: S.of(context).passive,
              subtitleString: S.of(context).passiveDetail,
            ),
            SettingsListTile.switchTile(
                key: const Key(
                    'general_settings_page_settings_card_ais_play_style_shuffling_enabled'),
                value: generalSettings.shufflingEnabled,
                onChanged: (bool val) {
                  _setShufflingEnabled(generalSettings, val);
                },
                titleString: S.of(context).shufflingEnabled,
                subtitleString: S.of(context).moveRandomlyDetail),
          ],
        ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_play_sounds'),
          title: Text(
            S.of(context).playSounds,
            key: const Key(
                'general_settings_page_settings_card_play_sounds_title'),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_play_sounds_tone_enabled'),
              value: generalSettings.toneEnabled,
              onChanged: (bool val) => _setTone(generalSettings, val),
              titleString: S.of(context).playSoundsInTheGame,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_play_sounds_keep_mute_when_taking_back'),
              value: generalSettings.keepMuteWhenTakingBack,
              onChanged: (bool val) =>
                  _setKeepMuteWhenTakingBack(generalSettings, val),
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_play_sounds_sound_theme'),
              titleString: S.of(context).soundTheme,
              trailingString: generalSettings.soundTheme!.localeName(context),
              onTap: () => _setSoundTheme(context, generalSettings),
            ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              SettingsListTile.switchTile(
                key: const Key(
                    'general_settings_page_settings_card_play_sounds_vibration_enabled'),
                value: generalSettings.vibrationEnabled,
                onChanged: (bool val) => _setVibration(generalSettings, val),
                titleString: S.of(context).vibration,
              ),
          ],
        ),
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
          SettingsCard(
            key: const Key('general_settings_page_settings_card_accessibility'),
            title: Text(
              S.of(context).accessibility,
              key: const Key(
                  'general_settings_page_settings_card_accessibility_title'),
            ),
            children: <Widget>[
              SettingsListTile.switchTile(
                key: const Key(
                    'general_settings_page_settings_card_accessibility_screen_reader_support'),
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
            key: const Key(
                'general_settings_page_settings_card_game_screen_recorder'),
            title: Text(
              S.of(context).gameScreenRecorder,
              key: const Key(
                  'general_settings_page_settings_card_game_screen_recorder_title'),
            ),
            children: <Widget>[
              SettingsListTile.switchTile(
                key: const Key(
                    'general_settings_page_settings_card_game_screen_recorder_support'),
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
                key: const Key(
                    'general_settings_page_settings_card_game_screen_recorder_duration'),
                titleString: S.of(context).duration,
                trailingString:
                    generalSettings.gameScreenRecorderDuration.toString(),
                onTap: () =>
                    _setGameScreenRecorderDuration(context, generalSettings),
              ),
              SettingsListTile(
                key: const Key(
                    'general_settings_page_settings_card_game_screen_recorder_pixel_ratio'),
                titleString: S.of(context).pixelRatio,
                trailingString:
                    "${generalSettings.gameScreenRecorderPixelRatio}%",
                onTap: () =>
                    _setGameScreenRecorderPixelRatio(context, generalSettings),
              ),
            ],
          ),
        if (DB().ruleSettings.isLikelyNineMensMorris())
          SettingsCard(
            key: const Key('general_settings_page_settings_card_llm_prompts'),
            title: Text(
              S.of(context).llm,
              key: const Key(
                  'general_settings_page_settings_card_llm_prompts_title'),
            ),
            children: <Widget>[
              SettingsListTile(
                key: const Key(
                    'general_settings_page_settings_card_llm_prompts_configure'),
                titleString: S.of(context).configurePromptTemplate,
                subtitleString: S.of(context).editPromptTemplateForLlmAnalysis,
                onTap: () => _configureLlmPrompt(context),
              ),
              SettingsListTile(
                key: const Key(
                    'general_settings_page_settings_card_llm_provider_configure'),
                titleString: S.of(context).configureLlmProvider,
                subtitleString: S.of(context).setProviderModelApiKeyAndBaseUrl,
                onTap: () => _configureLlmProvider(context),
                trailingString: DB().generalSettings.llmProvider.name,
              ),
            ],
          ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_misc'),
          title: Text(
            S.of(context).misc,
            key: const Key('general_settings_page_settings_card_misc_title'),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                  'general_settings_page_settings_card_misc_auto_restart'),
              value: generalSettings.isAutoRestart,
              onChanged: (bool val) => _setIsAutoRestart(generalSettings, val),
              titleString: S.of(context).isAutoRestart,
            ),
          ],
        ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_restore'),
          title: Text(
            S.of(context).restore,
            key: const Key('general_settings_page_settings_card_restore_title'),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                  'general_settings_page_settings_card_restore_default_settings'),
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
      key: const Key('general_settings_page_block_semantics'),
      child: Scaffold(
        key: const Key('general_settings_page_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.lightBackgroundColor,
        appBar: AppBar(
          key: const Key('general_settings_page_app_bar'),
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).generalSettings,
            key: const Key('general_settings_page_app_bar_title'),
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: ValueListenableBuilder<Box<GeneralSettings>>(
          key: const Key('general_settings_page_value_listenable_builder'),
          valueListenable: DB().listenGeneralSettings,
          builder: _buildGeneralSettingsList,
        ),
      ),
    );
  }
}
