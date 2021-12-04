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
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:double_back_to_close_app/double_back_to_close_app.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/models/display.dart';
import 'package:sanmill/screens/home.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/language_info.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/feedback_localization.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

part 'package:sanmill/services/catcher.dart';
part 'package:sanmill/services/init_system_ui.dart';

Future<void> main() async {
  debugPrint("Environment [catcher]: ${EnvironmentConfig.catcher}");
  debugPrint("Environment [dev_mode]: ${EnvironmentConfig.devMode}");
  debugPrint("Environment [monkey_test]: ${EnvironmentConfig.monkeyTest}");

  await LocalDatabaseService.initStorage();

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

RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class SanmillApp extends StatelessWidget {
  const SanmillApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final globalScaffoldKey = GlobalKey<ScaffoldState>();
    Audios.loadSounds();

    return ValueListenableBuilder(
      valueListenable: LocalDatabaseService.listenDisplay,
      builder: (BuildContext context, Box<Display> displayBox, child) {
        final Display _display = displayBox.get(
          LocalDatabaseService.displayKey,
          defaultValue: const Display(),
        )!;
        return BetterFeedback(
          localizationsDelegates: const [
            ...S.localizationsDelegates,
            CustomFeedbackLocalizationsDelegate.delegate,
          ],
          localeOverride: _display.languageCode,
          theme: AppTheme.feedbackTheme,
          child: MaterialApp(
            /// Add navigator key from Catcher.
            /// It will be used to navigate user to report page or to show dialog.
            navigatorKey:
                EnvironmentConfig.catcher ? Catcher.navigatorKey : null,
            key: globalScaffoldKey,
            navigatorObservers: [routeObserver],
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            locale: _display.languageCode,
            theme: AppTheme.lightThemeData,
            darkTheme: AppTheme.darkThemeData,
            debugShowCheckedModeBanner: false,
            home: child,
          ),
        );
      },
      child: Builder(
        builder: (context) {
          setSpecialCountryAndRegion(context);
          return Scaffold(
            body: DoubleBackToCloseApp(
              snackBar: SnackBar(
                content: Text(S.of(context).tapBackAgainToLeave),
              ),
              child: const Home(),
            ),
          );
        },
      ),
    );
  }
}
