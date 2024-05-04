// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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
import 'dart:ui';

import 'package:catcher_2/catcher_2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:path_provider/path_provider.dart';

import 'appearance_settings/models/display_settings.dart';
import 'game_page/services/mill.dart';
import 'game_page/widgets/painters/painters.dart';
import 'generated/intl/l10n.dart';
import 'home/home.dart';
import 'shared/config/constants.dart';
import 'shared/database/database.dart';
import 'shared/services/environment_config.dart';
import 'shared/services/logger.dart';
import 'shared/themes/app_theme.dart';
import 'shared/utils/localizations/feedback_localization.dart';
import 'shared/widgets/snackbars/scaffold_messenger.dart';

part 'package:sanmill/shared/services/catcher_service.dart';
part 'package:sanmill/shared/services/system_ui_service.dart';

Future<void> main() async {
  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  if (EnvironmentConfig.test) {
    enableFlutterDriverExtension();
  }

  await DB.init();

  _initUI();

  if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
    catcher = Catcher2(
      rootWidget: const SanmillApp(),
      ensureInitialized: true,
    );

    await _initCatcher(catcher);

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
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
    DB(View.of(context)
        .platformDispatcher
        .views
        .first
        .platformDispatcher
        .locale);

    if (kIsWeb) {
      Locale? locale;

      if (PlatformDispatcher.instance.locale == const Locale('und') ||
          !S.supportedLocales.contains(
              Locale(PlatformDispatcher.instance.locale.languageCode))) {
        locale = const Locale('en');
      } else {
        locale = PlatformDispatcher.instance.locale;
      }

      return MaterialApp(
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
        home: Builder(
          builder: _buildHome,
        ),
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
              Locale(PlatformDispatcher.instance.locale.languageCode))) {
        DB().displaySettings =
            displaySettings.copyWith(locale: const Locale('en'));
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(displaySettings.fontScale),
          ),
          child: child!,
        );
      },
      home: Builder(
        builder: _buildHome,
      ),
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
      resizeToAvoidBottomInset: false,
      body: Home(),
    );
  }

  void _setupSharingIntent() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    // Listening for shared files when the app is already running
    _intentDataStreamSubscription =
        FlutterSharingIntent.instance.getMediaStream().listen(
      (List<SharedFile> value) {
        if (value.isNotEmpty && value.first.value != null) {
          final String filePath = value.first.value!;
          rootScaffoldMessengerKey.currentState!
              .showSnackBarClear("Setup Sharing Intent: $filePath");
        }
      },
      onError: (dynamic err) {
        logger.e("Error receiving intent data stream: $err");
      },
    );

    // Handling initial share when the app is launched from a closed state
    FlutterSharingIntent.instance.getInitialSharing().then(
      (List<SharedFile> value) {
        if (value.isNotEmpty && value.first.value != null) {
          final String filePath = value.first.value!;
          //rootScaffoldMessengerKey.currentState!.showSnackBarClear(filePath);

          // Call the loadGame function with the file path
          LoadService.loadGame(context, filePath).then((_) {
            logger.i("Game loaded successfully from shared file.");
            //rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            //    "Game loaded successfully from shared file.");
          }).catchError((dynamic error) {
            logger.e("Error loading game from shared file: $error");
            rootScaffoldMessengerKey.currentState!.showSnackBarClear(
                "Error loading game from shared file: $error"); // TODO: l10n
          });
        }
      },
      onError: (dynamic err) {
        logger.e("Error getting initial sharing: $err");
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            "Error getting initial sharing: $err"); // TODO: l10n
      },
    );
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _intentDataStreamSubscription?.cancel();
    }
    super.dispose();
  }
}
