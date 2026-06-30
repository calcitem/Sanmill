// SPDX-License-Identifier: AGPL-3.0-or-later
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

import '../../game_page/services/gif_share/gif_share.dart';
import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/database/settings_repositories.dart';
import '../../shared/database/settings_repository.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/human_database_service.dart';
import '../../shared/services/logger.dart';
import '../../shared/services/perfect_database_service.dart';
import '../../shared/services/snackbar_service.dart';
import '../../shared/services/url.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/general_settings.dart';
import '../services/config_import_export_service.dart';
import 'developer_options_page.dart';
import 'dialogs/llm_config_dialog.dart';
import 'dialogs/llm_prompt_dialog.dart';

part 'dialogs/reset_settings_alert_dialog.dart';
part 'dialogs/use_perfect_database_dialog.dart';
part 'pages/settings_sub_page.dart';
part 'pages/advanced_ai_search_page.dart';
part 'pages/ai_knowledge_sources_page.dart';
part 'modals/algorithm_modal.dart';
part 'modals/duration_modal.dart';
part 'modals/ratio_modal.dart';
part 'modals/sound_theme_modal.dart';
part 'pickers/skill_level_picker.dart';
part 'pickers/search_threads_picker.dart';
part 'sliders/move_time_slider.dart';
part 'sliders/opening_randomness_slider.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  static const String _logTag = "[general_settings_page]";
  static Timer? _databaseCopyDebounce;

  SettingsRepository get _settingsRepository =>
      SettingsRepositories.instance.current.repository;

  // Restore
  void _restoreFactoryDefaultSettings(BuildContext context) => showDialog(
    context: context,
    builder: (_) => const _ResetSettingsAlertDialog(),
  );

  Future<void> _exportSettings(BuildContext context) async {
    final S strings = S.of(context);
    final bool? success = await ConfigImportExportService.shareConfig(
      shareSubject: strings.configImportShareSubject,
      saveDialogTitle: strings.exportAllSettings,
    );
    if (!context.mounted) {
      return;
    }
    if (success == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? strings.configExportSuccess : strings.configExportFailed,
        ),
      ),
    );
  }

  Future<void> _importSettings(BuildContext context) async {
    FilePickerResult? pickResult;
    try {
      pickResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[
          ConfigImportExportService.fileExtension,
          'json',
        ],
      );
    } catch (e, st) {
      logger.e('$_logTag Import file pick failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).configImportErrorReadFailed)),
        );
      }
      return;
    }

    if (pickResult == null ||
        pickResult.files.isEmpty ||
        pickResult.files.single.path == null) {
      return;
    }
    final String filePath = pickResult.files.single.path!;

    if (!context.mounted) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          S.of(ctx).importAllSettings,
          style: TextStyle(
            fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          ),
        ),
        content: Text(S.of(ctx).configImportConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(ctx).confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final ConfigImportResult result =
        await ConfigImportExportService.importConfigFromPath(filePath);

    if (!context.mounted) {
      return;
    }

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).configImportSuccess)),
      );
    } else if (!result.userCancelled) {
      final S s = S.of(context);
      final String message = switch (result.errorKind) {
        ConfigImportErrorKind.fileNotFound => s.configImportErrorFileNotFound,
        ConfigImportErrorKind.invalidFile => s.configImportErrorInvalidFile,
        ConfigImportErrorKind.readFailed => s.configImportErrorReadFailed,
        null => s.configImportErrorReadFailed,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
    _settingsRepository.generalSettings = generalSettings.copyWith(
      aiChatEnabled: value,
    );

    // Show experimental feature warning when enabling
    if (value) {
      SnackBarService.showRootSnackBar(S.of(context).experimental);
    }

    logger.t("$_logTag aiChatEnabled: $value");
  }

  void _setWhoMovesFirst(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      aiMovesFirst: value,
    );

    logger.t("$_logTag aiMovesFirst: $value");
  }

  void _setAiIsLazy(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      aiIsLazy: value,
    );

    logger.t("$_logTag aiIsLazy: $value");
  }

  void _setAlgorithm(BuildContext context, GeneralSettings generalSettings) {
    void callback(SearchAlgorithm? searchAlgorithm) {
      _settingsRepository.generalSettings = generalSettings.copyWith(
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

  void _setDrawOnHumanExperience(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      drawOnHumanExperience: value,
    );

    logger.t("$_logTag drawOnHumanExperience: $value");
  }

  void _setConsiderMobility(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      considerMobility: value,
    );

    logger.t("$_logTag considerMobility: $value");
  }

  void _setFocusOnBlockingPaths(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      focusOnBlockingPaths: value,
    );

    logger.t("$_logTag focusOnBlockingPaths: $value");
  }

  void _setShufflingEnabled(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      shufflingEnabled: value,
    );

    logger.t("$_logTag shufflingEnabled: $value");
  }

  void _setUseLazySmp(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      useLazySmp: value,
    );

    logger.t("$_logTag useLazySmp: $value");
  }

  void _setEngineThreads(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _SearchThreadsPicker(),
  );

  void _openAiKnowledgeSources(BuildContext context) {
    Navigator.of(
      context,
    ).push(_settingsDrillInRoute<void>(_AiKnowledgeSourcesPage(parent: this)));
  }

  void _openAdvancedAiSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(_settingsDrillInRoute<void>(_AdvancedAiSearchPage(parent: this)));
  }

  void _setTrapAwareness(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      trapAwareness: value,
    );

    logger.t("$_logTag trapAwareness: $value");
  }

  void _setUseOpeningBook(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      useOpeningBook: value,
    );

    logger.t("$_logTag useOpeningBook: $value");
  }

  void _setShowOpeningInfo(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      showOpeningInfo: value,
    );

    logger.t("$_logTag showOpeningInfo: $value");
  }

  void _setPreferFavoredOpenings(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      preferFavoredOpenings: value,
    );

    logger.t("$_logTag preferFavoredOpenings: $value");
  }

  void _setOpeningRandomness(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const _OpeningRandomnessSlider(),
      );

  void _setUsePerfectDatabase(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      usePerfectDatabase: value,
    );

    logger.t("$_logTag usePerfectDatabase: $value");

    if (value) {
      _databaseCopyDebounce?.cancel();
      _databaseCopyDebounce = Timer(const Duration(seconds: 1), () {
        unawaited(
          ensurePerfectDatabaseReady().then((bool success) {
            if (!success) {
              logger.w('$_logTag Failed to initialize perfect database');
            }
          }),
        );
      });
    } else {
      _databaseCopyDebounce?.cancel();
      disablePerfectDatabase();
    }
  }

  void _showUsePerfectDatabaseDialog(BuildContext context) => showDialog(
    context: context,
    builder: (_) => const _UsePerfectDatabaseDialog(),
  );

  Future<void> _setHumanDatabaseEnabled(
    BuildContext context,
    GeneralSettings generalSettings,
    bool value,
  ) async {
    if (!value) {
      HumanDatabaseService.instance.disable();
      _settingsRepository.generalSettings = generalSettings.copyWith(
        humanDatabaseEnabled: false,
      );
      logger.t("$_logTag humanDatabaseEnabled: false");
      return;
    }

    if (generalSettings.humanDatabaseFilePath.trim().isEmpty) {
      await _pickHumanDatabaseFile(
        context,
        generalSettings,
        enableAfterPick: true,
      );
      return;
    }

    final HumanDatabaseReadyResult ready = await HumanDatabaseService.instance
        .ensureReady(generalSettings.humanDatabaseFilePath);
    if (!context.mounted) {
      return;
    }
    if (!ready.ready) {
      _settingsRepository.generalSettings = generalSettings.copyWith(
        humanDatabaseEnabled: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S.of(context).humanGameDatabaseLoadFailed(ready.status.error),
          ),
        ),
      );
      return;
    }

    _settingsRepository.generalSettings = generalSettings.copyWith(
      humanDatabaseEnabled: true,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S
              .of(context)
              .humanGameDatabaseLoaded(
                ready.status.positionCount,
                ready.status.moveCount,
              ),
        ),
      ),
    );
    logger.t("$_logTag humanDatabaseEnabled: true");
  }

  Future<void> _pickHumanDatabaseFile(
    BuildContext context,
    GeneralSettings generalSettings, {
    bool enableAfterPick = false,
  }) async {
    if (EnvironmentConfig.test == true) {
      return;
    }

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['sqlite', 'sqlite3', 'db'],
    );
    if (result == null || result.files.single.path == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final String pickedPath = result.files.single.path!;

    // Persisting a multi-hundred-MB database takes a moment; block input with
    // a progress dialog so the user does not re-tap and queue a second import.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(S.of(context).pleaseWait)),
          ],
        ),
      ),
    );

    String? persistentPath;
    HumanDatabaseReadyResult? ready;
    String? error;
    try {
      // Copy the picked file out of the OS cache into durable app-private
      // storage first (see HumanDatabaseService.importDatabaseFile); the cache
      // path FilePicker returns is cleared by the system and would leave the
      // feature "enabled but file gone".  Validate the persisted copy.
      persistentPath = await HumanDatabaseService.instance.importDatabaseFile(
        pickedPath,
      );
      ready = await HumanDatabaseService.instance.ensureReady(persistentPath);
    } catch (e) {
      error = '$e';
    }

    if (!context.mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(); // dismiss progress

    if (error != null ||
        persistentPath == null ||
        ready == null ||
        !ready.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            S
                .of(context)
                .humanGameDatabaseLoadFailed(
                  error ?? ready?.status.error ?? '',
                ),
          ),
        ),
      );
      return;
    }

    _settingsRepository.generalSettings = generalSettings.copyWith(
      humanDatabaseEnabled:
          enableAfterPick || generalSettings.humanDatabaseEnabled,
      humanDatabaseFilePath: persistentPath,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S
              .of(context)
              .humanGameDatabaseLoaded(
                ready.status.positionCount,
                ready.status.moveCount,
              ),
        ),
      ),
    );
    logger.t("$_logTag humanDatabaseFilePath: $persistentPath");
  }

  Future<void> _downloadHumanDatabase(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.of(ctx).downloadHumanGameDatabase),
        content: Text(S.of(ctx).downloadHumanGameDatabaseConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.of(ctx).no),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.of(ctx).yes),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await launchURL(context, Constants.humanDatabaseDownloadUrl);
  }

  void _clearHumanDatabaseFile(GeneralSettings generalSettings) {
    HumanDatabaseService.instance.disable();
    _settingsRepository.generalSettings = generalSettings.copyWith(
      humanDatabaseEnabled: false,
      humanDatabaseFilePath: '',
    );
    logger.t("$_logTag humanDatabase cleared");
  }

  void _setShowHumanDatabaseStats(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      showHumanDatabaseStats: value,
    );

    logger.t("$_logTag showHumanDatabaseStats: $value");
  }

  void _setTone(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      toneEnabled: value,
    );

    logger.t("$_logTag toneEnabled: $value");

    if (value == true) {
      unawaited(SoundManager().startBackgroundMusic());
    } else {
      unawaited(SoundManager().stopBackgroundMusic());
    }
  }

  void _setBackgroundMusicEnabled(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
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

    _settingsRepository.generalSettings = generalSettings.copyWith(
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

    _settingsRepository.generalSettings = generalSettings.copyWith(
      backgroundMusicEnabled: false,
      backgroundMusicFilePath: '',
    );
    logger.t("$_logTag backgroundMusic cleared");
    await SoundManager().stopBackgroundMusic();
  }

  void _setKeepMuteWhenTakingBack(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      keepMuteWhenTakingBack: value,
    );

    logger.t("$_logTag keepMuteWhenTakingBack: $value");
  }

  void _setSoundTheme(BuildContext context, GeneralSettings generalSettings) {
    void callback(SoundTheme? soundTheme) {
      _settingsRepository.generalSettings = generalSettings.copyWith(
        soundTheme: soundTheme,
      );

      logger.t("$_logTag soundTheme = $soundTheme");

      // On iOS, audioplayers does not support hot-reloading asset sources
      // after the players have been initialised; a restart is required.
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
    _settingsRepository.generalSettings = generalSettings.copyWith(
      vibrationEnabled: value,
    );

    logger.t("$_logTag vibrationEnabled: $value");
  }

  void _setScreenReaderSupport(GeneralSettings generalSettings, bool value) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      screenReaderSupport: value,
    );

    logger.t("$_logTag screenReaderSupport: $value");
  }

  void _setGameScreenRecorderSupport(
    GeneralSettings generalSettings,
    bool value,
  ) {
    _settingsRepository.generalSettings = generalSettings.copyWith(
      gameScreenRecorderSupport: value,
    );

    logger.t("$_logTag gameScreenRecorderSupport: $value");

    // Free captured frames immediately when the feature is disabled.
    if (value == false) {
      GifShare().releaseData();
    }
  }

  void _setGameScreenRecorderDuration(
    BuildContext context,
    GeneralSettings generalSettings,
  ) {
    void callback(int? duration) {
      Navigator.pop(context);

      _settingsRepository.generalSettings = generalSettings.copyWith(
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

      _settingsRepository.generalSettings = generalSettings.copyWith(
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
                'general_settings_page_settings_card_ais_play_style_knowledge_sources',
              ),
              titleString: S.of(context).aiKnowledgeSources,
              subtitleString: S.of(context).aiKnowledgeSources_Detail,
              trailingString: _aiKnowledgeSourcesSummary(
                context,
                generalSettings,
              ),
              onTap: () => _openAiKnowledgeSources(context),
            ),
            SettingsListTile(
              key: const Key(
                'general_settings_page_settings_card_ais_play_style_advanced_search',
              ),
              titleString: S.of(context).advancedAiSearch,
              subtitleString: S.of(context).advancedAiSearch_Detail,
              trailingString: _advancedAiSearchSummary(generalSettings),
              onTap: () => _openAdvancedAiSearch(context),
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
        if (supportsGameScreenRecorder)
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
        if (!kIsWeb)
          SettingsCard(
            key: const Key(
              'general_settings_page_settings_card_config_import_export',
            ),
            title: Text(
              S.of(context).configImportExport,
              key: const Key(
                'general_settings_page_settings_card_config_import_export_title',
              ),
            ),
            children: <Widget>[
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_export_all_settings',
                ),
                titleString: S.of(context).exportAllSettings,
                onTap: () => _exportSettings(context),
              ),
              SettingsListTile(
                key: const Key(
                  'general_settings_page_settings_card_import_all_settings',
                ),
                titleString: S.of(context).importAllSettings,
                onTap: () => _importSettings(context),
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
    return BlockSemantics(
      key: const Key('general_settings_page_block_semantics'),
      child: Scaffold(
        key: const Key('general_settings_page_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          key: const Key('general_settings_page_app_bar'),
          title: Text(
            S.of(context).generalSettings,
            key: const Key('general_settings_page_app_bar_title'),
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
