// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// general_settings_page.dart

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../appearance_settings/models/color_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../experience_recording/pages/session_list_page.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_page/services/gif_share/gif_share.dart';
import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/perfect_database_service.dart';
import '../../shared/services/snackbar_service.dart';
import '../../shared/services/url.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/general_settings.dart';
import 'developer_options_page.dart';
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

  // Debounce timer for database copy operations
  static Timer? _databaseCopyDebounce;

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
  void _configureLlmPrompt(BuildContext context) =>
      showDialog(context: context, builder: (_) => const LlmPromptDialog());

  // Show LLM provider configuration dialog
  void _configureLlmProvider(BuildContext context) =>
      showDialog(context: context, builder: (_) => const LlmConfigDialog());

  // Enable or disable AI chat assistant
  void _setAiChatEnabled(
    BuildContext context,
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings = generalSettings.copyWith(aiChatEnabled: value);

    // Show experimental feature warning when enabling
    if (value) {
      SnackBarService.showRootSnackBar(S.of(context).experimental);
    }

    logger.t("$_logTag aiChatEnabled: $value");
  }

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
      DB().generalSettings = generalSettings.copyWith(
        searchAlgorithm: searchAlgorithm,
      );

      switch (searchAlgorithm) {
        case SearchAlgorithm.alphaBeta:
          SnackBarService.showRootSnackBar(S.of(context).whatIsAlphaBeta);
          break;
        case SearchAlgorithm.pvs:
          SnackBarService.showRootSnackBar(S.of(context).whatIsPvs);
          break;
        case SearchAlgorithm.mtdf:
          SnackBarService.showRootSnackBar(S.of(context).whatIsMtdf);
          break;
        case SearchAlgorithm.mcts:
          SnackBarService.showRootSnackBar(S.of(context).whatIsMcts);
          break;
        // Random already has a dedicated localization entry.
        case SearchAlgorithm.random:
          SnackBarService.showRootSnackBar(S.of(context).whatIsRandom);
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
      // Cancel any pending debounce timer
      _databaseCopyDebounce?.cancel();

      // Debounce the file copy operation with 1 second delay
      _databaseCopyDebounce = Timer(const Duration(seconds: 1), () {
        // Execute file copy in background to avoid blocking main thread
        copyPerfectDatabaseFiles()
            .then((bool success) {
              if (!success) {
                logger.w('$_logTag Failed to copy perfect database files');
              }
            })
            .catchError((Object error) {
              logger.e('$_logTag Error copying perfect database files: $error');
            });
      });
    } else {
      // Cancel debounce if switching back to false
      _databaseCopyDebounce?.cancel();
    }
  }

  void _setTrapAwareness(GeneralSettings generalSettings, bool value) {
    // Enable or disable trap awareness
    DB().generalSettings = generalSettings.copyWith(trapAwareness: value);

    logger.t("$_logTag trapAwareness: $value");
  }

  void _showUsePerfectDatabaseDialog(BuildContext context) => showDialog(
    context: context,
    builder: (_) => const _UsePerfectDatabaseDialog(),
  );

  void _setDrawOnHumanExperience(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(
      drawOnHumanExperience: value,
    );

    logger.t("$_logTag drawOnHumanExperience: $value");
  }

  void _setConsiderMobility(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(considerMobility: value);

    logger.t("$_logTag considerMobility: $value");
  }

  void _setFocusOnBlockingPaths(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(
      focusOnBlockingPaths: value,
    );

    logger.t("$_logTag focusOnBlockingPaths: $value");
  }

  void _setShufflingEnabled(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(shufflingEnabled: value);

    logger.t("$_logTag shufflingEnabled: $value");
  }

  void _setTone(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(toneEnabled: value);

    logger.t("$_logTag toneEnabled: $value");

    if (value == true) {
      unawaited(SoundManager().startBackgroundMusic());
    } else {
      unawaited(SoundManager().stopBackgroundMusic());
    }
  }

  void _setBackgroundMusicEnabled(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(
      backgroundMusicEnabled: value,
    );
    logger.t("$_logTag backgroundMusicEnabled: $value");

    if (value == true) {
      unawaited(SoundManager().startBackgroundMusic());
    } else {
      unawaited(SoundManager().stopBackgroundMusic());
    }
  }

  // Platform-specific audio format support.
  // Windows (Media Foundation): No OGG/OPUS support.
  // iOS/macOS (AVFoundation): No OGG/OPUS/WMA support.
  // Android (MediaPlayer): Supports most formats.
  // Linux (GStreamer): Depends on installed plugins.

  static const Set<String> _windowsSupportedFormats = <String>{
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.wma',
    '.flac',
  };

  static const Set<String> _appleSupportedFormats = <String>{
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.aiff',
    '.flac',
    '.caf',
  };

  static const Set<String> _androidSupportedFormats = <String>{
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.flac',
    '.opus',
    '.amr',
    '.mid',
    '.midi',
    '.3gp',
  };

  static const Set<String> _linuxSupportedFormats = <String>{
    '.mp3',
    '.wav',
    '.ogg',
    '.flac',
    '.opus',
    '.m4a',
    '.aac',
  };

  /// Get the set of supported audio formats for the current platform.
  Set<String> _getSupportedAudioFormats() {
    if (kIsWeb) {
      // Web support varies by browser; allow common formats.
      return <String>{'.mp3', '.wav', '.ogg', '.m4a', '.aac'};
    }
    if (Platform.isWindows) {
      return _windowsSupportedFormats;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return _appleSupportedFormats;
    }
    if (Platform.isAndroid) {
      return _androidSupportedFormats;
    }
    if (Platform.isLinux) {
      return _linuxSupportedFormats;
    }
    // Fallback: allow common formats.
    return <String>{'.mp3', '.wav', '.m4a', '.aac', '.flac'};
  }

  /// Check if the audio format is supported on the current platform.
  bool _isAudioFormatSupported(String extension) {
    final String ext = extension.toLowerCase();
    return _getSupportedAudioFormats().contains(ext);
  }

  Future<void> _pickBackgroundMusicFile(
    BuildContext context,
    GeneralSettings generalSettings,
  ) async {
    if (EnvironmentConfig.test == true) {
      return;
    }

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory musicDir = Directory("${appDocDir.path}/music");
    if (!musicDir.existsSync()) {
      await musicDir.create(recursive: true);
    }

    if (!context.mounted) {
      return;
    }

    // Use FilePicker to allow users to select audio files from any accessible directory.
    // This solves the issue where users could not access their own music folders on Android
    // without requiring the MANAGE_EXTERNAL_STORAGE permission.
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    final String picked = result.files.single.path!;
    final String originalName = p.basename(picked);
    final String ext = p.extension(picked);

    // Validate audio format support on current platform.
    if (!_isAudioFormatSupported(ext)) {
      if (!context.mounted) {
        return;
      }
      final String supportedFormats = _getSupportedAudioFormats().join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S
                .of(context)
                .error(
                  'Format $ext is not supported. Supported: $supportedFormats',
                ),
          ),
        ),
      );
      return;
    }

    // Clean up old background music file before copying new one.
    await _deleteOldBackgroundMusicFile(
      generalSettings.backgroundMusicFilePath,
    );

    // Determine the target path, avoiding filename conflicts.
    final String newPath = _resolveUniqueMusicPath(musicDir.path, originalName);

    try {
      await File(picked).copy(newPath);
    } catch (e) {
      logger.e("$_logTag Failed to copy background music file: $e");
      return;
    }

    DB().generalSettings = generalSettings.copyWith(
      backgroundMusicEnabled: true,
      backgroundMusicFilePath: newPath,
    );
    logger.t("$_logTag backgroundMusicFilePath: $newPath");

    await SoundManager().startBackgroundMusic();
  }

  /// Delete the old background music file if it exists.
  Future<void> _deleteOldBackgroundMusicFile(String oldPath) async {
    if (oldPath.isEmpty) {
      return;
    }
    try {
      final File oldFile = File(oldPath);
      if (oldFile.existsSync()) {
        await oldFile.delete();
        logger.t("$_logTag Deleted old background music file: $oldPath");
      }
    } catch (e) {
      logger.w("$_logTag Failed to delete old background music file: $e");
    }
  }

  /// Resolve a unique file path in the music directory.
  /// If the file already exists, append a numeric suffix.
  String _resolveUniqueMusicPath(String dirPath, String filename) {
    final String baseName = p.basenameWithoutExtension(filename);
    final String ext = p.extension(filename);
    String candidate = "$dirPath/$filename";

    int counter = 1;
    while (File(candidate).existsSync()) {
      candidate = "$dirPath/${baseName}_$counter$ext";
      counter++;
    }
    return candidate;
  }

  Future<void> _clearBackgroundMusic(GeneralSettings generalSettings) async {
    // Delete the background music file from disk.
    await _deleteOldBackgroundMusicFile(
      generalSettings.backgroundMusicFilePath,
    );

    DB().generalSettings = generalSettings.copyWith(
      backgroundMusicEnabled: false,
      backgroundMusicFilePath: '',
    );
    logger.t("$_logTag backgroundMusic cleared");
    await SoundManager().stopBackgroundMusic();
  }

  void _setKeepMuteWhenTakingBack(GeneralSettings generalSettings, bool value) {
    DB().generalSettings = generalSettings.copyWith(
      keepMuteWhenTakingBack: value,
    );

    logger.t("$_logTag keepMuteWhenTakingBack: $value");
  }

  void _setSoundTheme(BuildContext context, GeneralSettings generalSettings) {
    void callback(SoundTheme? soundTheme) {
      DB().generalSettings = generalSettings.copyWith(soundTheme: soundTheme);

      logger.t("$_logTag soundTheme = $soundTheme");

      // TODO: Take effect on iOS
      if (Platform.isIOS) {
        SnackBarService.showRootSnackBar(S.of(context).reopenToTakeEffect);
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
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings = generalSettings.copyWith(
      gameScreenRecorderSupport: value,
    );

    logger.t("$_logTag gameScreenRecorderSupport: $value");

    // Free captured frames immediately when the feature is disabled.
    if (value == false) {
      GifShare().releaseData();
    }
  }

  void _setExperienceRecordingEnabled(
    BuildContext context,
    GeneralSettings generalSettings,
    bool value,
  ) {
    DB().generalSettings = generalSettings.copyWith(
      experienceRecordingEnabled: value,
    );

    logger.t("$_logTag experienceRecordingEnabled: $value");

    // Stop any active recording when feature is disabled.
    if (!value) {
      RecordingService().stopRecording();
    }
  }

  void _openRecordingSessions(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SessionListPage(),
      ),
    );
  }

  void _setGameScreenRecorderDuration(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    void callback(int? duration) {
      Navigator.pop(context);

      DB().generalSettings = generalSettings.copyWith(
        gameScreenRecorderDuration: duration ?? 2,
      );

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
      SnackBarService.showRootSnackBar(S.of(context).reopenToTakeEffect);

      Navigator.pop(context);

      DB().generalSettings = generalSettings.copyWith(
        gameScreenRecorderPixelRatio: ratio ?? 50,
      );

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

    final String perfectDatabaseDescription = S
        .of(context)
        .perfectDatabaseDescription;
    final String perfectDatabaseDescriptionFistLine =
        perfectDatabaseDescription.contains('\n')
        ? perfectDatabaseDescription.substring(
            0,
            perfectDatabaseDescription.indexOf('\n'),
          )
        : perfectDatabaseDescription;

    return SettingsList(
      key: const Key('general_settings_page_settings_list'),
      children: <Widget>[
        SettingsCard(
          key: const Key('general_settings_page_settings_card_who_moves_first'),
          title: Text(
            S.of(context).whoMovesFirst,
            key: const Key(
              'general_settings_page_settings_card_who_moves_first_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_who_moves_first_switch_tile',
              ),
              value: !generalSettings.aiMovesFirst,
              onChanged: (bool val) {
                _setWhoMovesFirst(generalSettings, !val);
                if (val == false &&
                    DB().ruleSettings.isLikelyNineMensMorris()) {
                  SnackBarService.showRootSnackBar(
                    S.of(context).firstMoveDetail,
                  );
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
              'general_settings_page_settings_card_difficulty_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_difficulty_skill_level',
              ),
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
                'general_settings_page_settings_card_difficulty_move_time',
              ),
              titleString: S.of(context).moveTime,
              trailingString: DB().generalSettings.moveTime.toString(),
              onTap: () => _setMoveTime(context),
            ),
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_difficulty_human_move_time',
              ),
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
              'general_settings_page_settings_card_ais_play_style_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_algorithm',
              ),
              titleString: S.of(context).algorithm,
              trailingString: generalSettings.searchAlgorithm!.name,
              onTap: () => _setAlgorithm(context, generalSettings),
            ),
            if (DB().ruleSettings.isLikelyNineMensMorris() ||
                DB().ruleSettings.isLikelyElFilja())
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_ais_play_style_use_opening_book',
                ),
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
                  'general_settings_page_settings_card_ais_play_style_use_perfect_database',
                ),
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
            if (!kIsWeb &&
                DB().generalSettings.usePerfectDatabase &&
                isRuleSupportingPerfectDatabase())
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_ais_play_style_trap_awareness',
                ),
                value: generalSettings.trapAwareness,
                onChanged: (bool val) {
                  _setTrapAwareness(generalSettings, val);
                },
                titleString: S.of(context).trapAwareness,
                subtitleString: S.of(context).trapAwarenessDescription,
              ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_draw_on_human_experience',
              ),
              value: generalSettings.drawOnHumanExperience,
              onChanged: (bool val) {
                _setDrawOnHumanExperience(generalSettings, val);
              },
              titleString: S.of(context).drawOnHumanExperience,
              subtitleString: S.of(context).drawOnTheHumanExperienceDetail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_consider_mobility',
              ),
              value: generalSettings.considerMobility,
              onChanged: (bool val) {
                _setConsiderMobility(generalSettings, val);
              },
              titleString: S.of(context).considerMobility,
              subtitleString: S.of(context).considerMobilityOfPiecesDetail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_focus_on_blocking_paths',
              ),
              value: generalSettings.focusOnBlockingPaths,
              onChanged: (bool val) {
                _setFocusOnBlockingPaths(generalSettings, val);
              },
              titleString: S.of(context).focusOnBlockingPaths,
              subtitleString: S.of(context).focusOnBlockingPaths_Detail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_ai_is_lazy',
              ),
              value: generalSettings.aiIsLazy,
              onChanged: (bool val) {
                _setAiIsLazy(generalSettings, val);
              },
              titleString: S.of(context).passive,
              subtitleString: S.of(context).passiveDetail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_shuffling_enabled',
              ),
              value: generalSettings.shufflingEnabled,
              onChanged: (bool val) {
                _setShufflingEnabled(generalSettings, val);
              },
              titleString: S.of(context).shufflingEnabled,
              subtitleString: S.of(context).moveRandomlyDetail,
            ),
          ],
        ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_play_sounds'),
          title: Text(
            S.of(context).playSounds,
            key: const Key(
              'general_settings_page_settings_card_play_sounds_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_play_sounds_tone_enabled',
              ),
              value: generalSettings.toneEnabled,
              onChanged: (bool val) => _setTone(generalSettings, val),
              titleString: S.of(context).playSoundsInTheGame,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_play_sounds_keep_mute_when_taking_back',
              ),
              value: generalSettings.keepMuteWhenTakingBack,
              onChanged: (bool val) =>
                  _setKeepMuteWhenTakingBack(generalSettings, val),
              titleString: S.of(context).keepMuteWhenTakingBack,
            ),
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_play_sounds_sound_theme',
              ),
              titleString: S.of(context).soundTheme,
              trailingString: generalSettings.soundTheme!.localeName(context),
              onTap: () => _setSoundTheme(context, generalSettings),
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_settings_card_play_sounds_background_music_enabled',
              ),
              value: generalSettings.backgroundMusicEnabled,
              onChanged: (bool val) =>
                  _setBackgroundMusicEnabled(generalSettings, val),
              titleString: S.of(context).backgroundMusic,
              subtitleString: S.of(context).backgroundMusicDescription,
            ),
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_play_sounds_background_music_file',
              ),
              titleString: S.of(context).backgroundMusicFile,
              trailingString: generalSettings.backgroundMusicFilePath.isEmpty
                  ? S.of(context).none
                  : p.basename(generalSettings.backgroundMusicFilePath),
              onTap: () => _pickBackgroundMusicFile(context, generalSettings),
            ),
            if (generalSettings.backgroundMusicFilePath.isNotEmpty)
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_play_sounds_background_music_clear',
                ),
                titleString: S.of(context).clearBackgroundMusic,
                onTap: () => _clearBackgroundMusic(generalSettings),
              ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_play_sounds_vibration_enabled',
                ),
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
                'general_settings_page_settings_card_accessibility_title',
              ),
            ),
            children: <Widget>[
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_accessibility_screen_reader_support',
                ),
                value: generalSettings.screenReaderSupport,
                onChanged: (bool val) {
                  _setScreenReaderSupport(generalSettings, val);
                  SnackBarService.showRootSnackBar(
                    S.of(context).reopenToTakeEffect,
                  );
                },
                titleString: S.of(context).screenReaderSupport,
              ),
            ],
          ),
        // TODO: Fix iOS bug
        if (!kIsWeb && (Platform.isAndroid))
          SettingsCard(
            key: const Key(
              'general_settings_page_settings_card_game_screen_recorder',
            ),
            title: Text(
              S.of(context).gameScreenRecorder,
              key: const Key(
                'general_settings_page_settings_card_game_screen_recorder_title',
              ),
            ),
            children: <Widget>[
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_game_screen_recorder_support',
                ),
                value: generalSettings.gameScreenRecorderSupport,
                onChanged: (bool val) {
                  _setGameScreenRecorderSupport(generalSettings, val);
                  if (val == true) {
                    SnackBarService.showRootSnackBar(
                      S.of(context).experimental,
                    );
                  }
                },
                titleString: S.of(context).shareGIF,
              ),
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_game_screen_recorder_duration',
                ),
                titleString: S.of(context).duration,
                trailingString: generalSettings.gameScreenRecorderDuration
                    .toString(),
                onTap: () =>
                    _setGameScreenRecorderDuration(context, generalSettings),
              ),
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_game_screen_recorder_pixel_ratio',
                ),
                titleString: S.of(context).pixelRatio,
                trailingString:
                    "${generalSettings.gameScreenRecorderPixelRatio}%",
                onTap: () =>
                    _setGameScreenRecorderPixelRatio(context, generalSettings),
              ),
            ],
          ),
        SettingsCard(
          key: const Key(
            'general_settings_page_settings_card_experience_recording',
          ),
          title: Text(
            S.of(context).experienceRecording,
            key: const Key(
              'general_settings_page_settings_card_experience_recording_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'general_settings_page_experience_recording_enabled',
              ),
              value: generalSettings.experienceRecordingEnabled,
              onChanged: (bool val) {
                _setExperienceRecordingEnabled(
                  context,
                  generalSettings,
                  val,
                );
                if (val == true) {
                  SnackBarService.showRootSnackBar(
                    S.of(context).experimental,
                  );
                }
              },
              titleString: S.of(context).experienceRecording,
              subtitleString:
                  S.of(context).experienceRecordingDescription,
            ),
            SettingsListTile(
              key: const Key(
                'general_settings_page_recording_sessions',
              ),
              titleString: S.of(context).recordingSessions,
              onTap: () => _openRecordingSessions(context),
            ),
          ],
        ),
        if (DB().ruleSettings.isLikelyNineMensMorris())
          SettingsCard(
            key: const Key('general_settings_page_settings_card_llm_prompts'),
            title: Text(
              S.of(context).llm,
              key: const Key(
                'general_settings_page_settings_card_llm_prompts_title',
              ),
            ),
            children: <Widget>[
              SettingsListTile.switchTile(
                key: const Key(
                  'general_settings_page_settings_card_ai_chat_enabled',
                ),
                value: generalSettings.aiChatEnabled,
                onChanged: (bool val) =>
                    _setAiChatEnabled(context, generalSettings, val),
                titleString: S.of(context).enableAiChat,
                subtitleString: S.of(context).allowChatWithAiAssistant,
              ),
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_llm_prompts_configure',
                ),
                titleString: S.of(context).configurePromptTemplate,
                subtitleString: S.of(context).editPromptTemplateForLlmAnalysis,
                onTap: () => _configureLlmPrompt(context),
              ),
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_llm_provider_configure',
                ),
                titleString: S.of(context).configureLlmProvider,
                subtitleString: S.of(context).setProviderModelApiKeyAndBaseUrl,
                onTap: () => _configureLlmProvider(context),
                trailingString: DB().generalSettings.llmProvider.name,
              ),
            ],
          ),
        SettingsCard(
          key: const Key('general_settings_page_settings_card_developer'),
          title: Text(
            S.of(context).developerOptions,
            key: const Key(
              'general_settings_page_settings_card_developer_title',
            ),
          ),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_developer_options',
              ),
              titleString: S.of(context).developerOptions,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const DeveloperOptionsPage(),
                ),
              ),
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
                'general_settings_page_settings_card_restore_default_settings',
              ),
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
    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);

        final Widget page = BlockSemantics(
          key: const Key('general_settings_page_block_semantics'),
          child: Scaffold(
            key: const Key('general_settings_page_scaffold'),
            resizeToAvoidBottomInset: false,
            backgroundColor: useDarkSettingsUi
                ? settingsTheme.scaffoldBackgroundColor
                : AppTheme.lightBackgroundColor,
            appBar: AppBar(
              key: const Key('general_settings_page_app_bar'),
              leading: CustomDrawerIcon.of(context)?.drawerIcon,
              title: Text(
                S.of(context).generalSettings,
                key: const Key('general_settings_page_app_bar_title'),
                style: useDarkSettingsUi
                    ? null
                    : AppTheme.appBarTheme.titleTextStyle,
              ),
            ),
            body: ValueListenableBuilder<Box<GeneralSettings>>(
              key: const Key('general_settings_page_value_listenable_builder'),
              valueListenable: DB().listenGeneralSettings,
              builder: _buildGeneralSettingsList,
            ),
          ),
        );

        return useDarkSettingsUi
            ? Theme(data: settingsTheme, child: page)
            : page;
      },
    );
  }
}
