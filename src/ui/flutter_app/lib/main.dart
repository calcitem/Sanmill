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

import 'dart:io';
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:double_back_to_close_app/double_back_to_close_app.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/display_settings.dart';
import 'package:sanmill/screens/home.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/feedback_localization.dart';
import 'package:sanmill/shared/scaffold_messenger.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/services/catcher.dart';
part 'package:sanmill/services/init_system_ui.dart';

Future<void> main() async {
  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  if (EnvironmentConfig.test) {
    enableFlutterDriverExtension();
  }

  await DB.init();

  _initUI();

  if (EnvironmentConfig.catcher && !Platform.isWindows) {
    final catcher = Catcher(
      rootWidget: const SanmillApp(),
      ensureInitialized: true,
    );

    await _initCatcher(catcher);
  } else {
    runApp(const SanmillApp());
  }
}

class SanmillApp extends StatelessWidget {
  const SanmillApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DB(window.platformDispatcher.locale);

    return ValueListenableBuilder(
      valueListenable: DB().listenDisplaySettings,
      builder: _buildApp,
    );
  }

  Widget _buildApp(BuildContext context, Box<DisplaySettings> box, Widget? _) {
    final DisplaySettings _displaySettings = box.get(
      DB.displaySettingsKey,
      defaultValue: const DisplaySettings(),
    )!;

    return BetterFeedback(
      localizationsDelegates: const [
        ...S.localizationsDelegates,
        CustomFeedbackLocalizationsDelegate.delegate,
      ],
      localeOverride: _displaySettings.languageCode,
      theme: AppTheme.feedbackTheme,
      child: MaterialApp(
        /// Add navigator key from Catcher.
        /// It will be used to navigate user to report page or to show dialog.
        navigatorKey: EnvironmentConfig.catcher ? Catcher.navigatorKey : null,
        key: GlobalKey<ScaffoldState>(),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: _displaySettings.languageCode,
        theme: AppTheme.lightThemeData,
        darkTheme: AppTheme.darkThemeData,
        debugShowCheckedModeBanner: EnvironmentConfig.devMode,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaleFactor: _displaySettings.fontScale,
            ),
            child: child!,
          );
        },
        home: Builder(
          builder: _buildHome,
        ),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    return Scaffold(
      body: DoubleBackToCloseApp(
        snackBar: CustomSnackBar(S.of(context).tapBackAgainToLeave),
        child: const Home(),
      ),
    );
  }
}
