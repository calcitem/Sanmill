// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// main.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:catcher_2/catcher_2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:path_provider/path_provider.dart';

import 'appearance_settings/models/display_settings.dart';
import 'game_page/services/engine/bitboard.dart';
import 'game_page/services/mill.dart';
import 'game_page/services/painters/painters.dart';
import 'generated/intl/l10n.dart';
import 'home/home.dart';
import 'puzzle/services/puzzle_manager.dart';
import 'shared/config/constants.dart';
import 'shared/database/database.dart';
import 'shared/services/environment_config.dart';
import 'shared/services/logger.dart';
import 'shared/services/screenshot_service.dart';
import 'shared/services/snackbar_service.dart';
import 'shared/themes/app_theme.dart';
import 'shared/utils/localizations/feedback_localization.dart';
import 'shared/widgets/snackbars/scaffold_messenger.dart';
import 'statistics/services/stats_service.dart';
// Voice assistant functionality disabled
// import 'voice_assistant/services/voice_assistant_service.dart';

part 'package:sanmill/shared/services/catcher_service.dart';
part 'package:sanmill/shared/services/system_ui_service.dart';

// Log tag for main

Future<void> main() async {
  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  // IMPORTANT: Remove or comment out for integration_test screenshots
  // if (EnvironmentConfig.test) {
  //   enableFlutterDriverExtension();
  // }

  await DB.init();

  // Initialize ELO service
  EloRatingService();

  // Initialize Puzzle Manager
  await PuzzleManager().init();

  // Initialize Screenshot service (if not in test mode)
  if (!EnvironmentConfig.test) {
    await ScreenshotService.instance.init();
  }

  // Voice assistant functionality disabled
  // Check and clean up incomplete voice model downloads from previous sessions
  // await VoiceAssistantService().modelDownloader.checkAndCleanIncompleteDownloads();

  // Initialize voice assistant service if enabled
  // if (DB().voiceAssistantSettings.enabled) {
  //   await VoiceAssistantService().initialize();
  // }

  _initUI();

  initBitboards();

  if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
    catcher = Catcher2(rootWidget: const SanmillApp(), ensureInitialized: true);

    await _initCatcher(catcher);

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      // Filter known Flutter framework bugs that should not crash the app
      final String stackTrace = stack.toString();

      // Known bug: EditableText toolbar race condition
      // See: Flutter framework editable_text.dart _handleContextMenuOnScroll
      // The _dataWhenToolbarShowScheduled field can be null when
      // addPostFrameCallback executes due to race condition
      if (error is TypeError &&
          error.toString().contains(
            'Null check operator used on a null value',
          ) &&
          stackTrace.contains('EditableTextState._handleContextMenuOnScroll')) {
        logger.w('Caught known Flutter framework bug in EditableText: $error');
        logger.w('Stack trace: $stackTrace');
        return true; // Suppress this known framework bug
      }

      if (EnvironmentConfig.catcher == true) {
        Catcher2.reportCheckedError(error, stack);
      }
      return true;
    };
  } else {
    runApp(const SanmillApp());
  }
}

class SanmillApp extends StatefulWidget {
  const SanmillApp({super.key});

  @override
  SanmillAppState createState() => SanmillAppState();
}

class SanmillAppState extends State<SanmillApp> {
  StreamSubscription<List<SharedFile>>? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _setupSharingIntent();
  }

  @override
  Widget build(BuildContext context) {
    DB(
      View.of(context).platformDispatcher.views.first.platformDispatcher.locale,
    );

    if (kIsWeb) {
      Locale? locale;

      if (PlatformDispatcher.instance.locale == const Locale('und') ||
          !S.supportedLocales.contains(
            Locale(PlatformDispatcher.instance.locale.languageCode),
          )) {
        locale = const Locale('en');
      } else {
        locale = PlatformDispatcher.instance.locale;
      }

      return MaterialApp(
        navigatorKey: navigatorStateKey,
        key: GlobalKey<ScaffoldState>(),
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: locale,
        theme: AppTheme.lightThemeData,
        darkTheme: AppTheme.darkThemeData,
        debugShowCheckedModeBanner: EnvironmentConfig.devMode,
        builder: (BuildContext context, Widget? child) {
          _initializeScreenOrientation(context);
          setWindowTitle(S.of(context).appName);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(),
            child: child!,
          );
        },
        home: Builder(builder: _buildHome),
      );
    }

    return ValueListenableBuilder<Box<DisplaySettings>>(
      valueListenable: DB().listenDisplaySettings,
      builder: _buildApp,
    );
  }

  Widget _buildApp(BuildContext context, Box<DisplaySettings> box, Widget? _) {
    final DisplaySettings displaySettings = box.get(
      DB.displaySettingsKey,
      defaultValue: const DisplaySettings(),
    )!;

    Locale? locale;

    if (displaySettings.locale == null) {
      if (PlatformDispatcher.instance.locale == const Locale('und') ||
          !S.supportedLocales.contains(
            Locale(PlatformDispatcher.instance.locale.languageCode),
          )) {
        DB().displaySettings = displaySettings.copyWith(
          locale: const Locale('en'),
        );
        locale = const Locale('en');
      } else {
        locale = PlatformDispatcher.instance.locale;
      }
    } else {
      locale = displaySettings.locale;
    }

    final MaterialApp materialApp = MaterialApp(
      /// Add navigator key from Catcher.
      /// It will be used to navigate user to report page or to show dialog.
      navigatorKey: (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS)
          ? Catcher2.navigatorKey
          : navigatorStateKey,
      key: GlobalKey<ScaffoldState>(),
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: locale,
      theme: AppTheme.lightThemeData,
      darkTheme: AppTheme.darkThemeData,
      debugShowCheckedModeBanner: EnvironmentConfig.devMode,
      builder: (BuildContext context, Widget? child) {
        _initializeScreenOrientation(context);
        setWindowTitle(S.of(context).appName);
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(displaySettings.fontScale)),
          child: child!,
        );
      },
      home: Builder(builder: _buildHome),
    );

    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return materialApp;
    } else if (Platform.isAndroid || Platform.isIOS) {
      return BetterFeedback(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          ...S.localizationsDelegates,
          CustomFeedbackLocalizationsDelegate.delegate,
        ],
        localeOverride: displaySettings.locale,
        theme: AppTheme.feedbackTheme,
        child: materialApp,
      );
    }

    return materialApp;
  }

  Widget _buildHome(BuildContext context) {
    return const Scaffold(
      key: Key('home_scaffold_key'),
      resizeToAvoidBottomInset: false,
      body: Home(key: Home.homeMainKey),
    );
  }

  void _setupSharingIntent() {
    // Skip setting up sharing intent for web or unsupported platforms
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    // Listen for shared files when the app is already running
    _intentDataStreamSubscription = FlutterSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedFile> files) {
            _handleSharedFiles(files, isRunning: true);
          },
          onError: (dynamic error) {
            logger.e("Error receiving intent data stream: $error");
            SnackBarService.showRootSnackBar(
              "Error receiving intent data stream: $error",
            ); // Consider localization
          },
        );

    // Handle initial sharing when the app is launched from a closed state
    FlutterSharingIntent.instance.getInitialSharing().then(
      (List<SharedFile> files) {
        _handleSharedFiles(files, isRunning: false);
      },
      onError: (dynamic error) {
        logger.e("Error getting initial sharing: $error");
        SnackBarService.showRootSnackBar(
          "Error getting initial sharing: $error",
        ); // Consider localization
      },
    );
  }

  // Helper method to process shared files
  void _handleSharedFiles(List<SharedFile> files, {required bool isRunning}) {
    if (files.isNotEmpty && files.first.value != null) {
      final String filePath = files.first.value!;
      // Show notification to user about the shared file path
      logger.i("Setup Sharing Intent: $filePath");
      // Load the game from the shared file
      LoadService.loadGame(context, filePath, isRunning: isRunning)
          .then((_) {
            logger.i("Game loaded successfully from shared file.");
          })
          .catchError((dynamic error) {
            logger.e("Error loading game from shared file: $error");
            SnackBarService.showRootSnackBar(
              "Error loading game from shared file: $error",
            ); // Consider localization
          });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _intentDataStreamSubscription?.cancel();
    }
    super.dispose();
  }
}
