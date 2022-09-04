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

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:catcher/catcher.dart';
import 'package:double_back_to_close_app/double_back_to_close_app.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/services/environment_config.dart';
import 'package:sanmill/services/language_info.dart';
import 'package:sanmill/services/logger.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/feedback_localization.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/navigation_home_screen.dart';

part 'package:sanmill/services/catcher.dart';
part 'package:sanmill/services/init_system_ui.dart';

Future<void> main() async {
  logger.i('Environment [catcher]: ${EnvironmentConfig.catcher}');
  logger.i('Environment [dev_mode]: ${EnvironmentConfig.devMode}');
  logger.i('Environment [test]: ${EnvironmentConfig.test}');

  if (EnvironmentConfig.test) {
    enableFlutterDriverExtension();
  }

  var app = BetterFeedback(
    localizationsDelegates: const [
      ...S.localizationsDelegates,
      CustomFeedbackLocalizationsDelegate.delegate,
    ],
    child: SanmillApp(),
    localeOverride: Locale(Resources.of().languageCode),
  );

  if (EnvironmentConfig.catcher && !kIsWeb && Platform.isAndroid) {
    var catcher = Catcher(rootWidget: app, ensureInitialized: true);
  } else {
    runApp(app);
  }

  String externalDirStr;
  try {
    Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      externalDirStr = externalDir.path.toString();
    } else {
      externalDirStr = ".";
    }
  } catch (e) {
    print(e);
    externalDirStr = ".";
  }
  String path = externalDirStr + "/" + Constants.crashLogsFileName;
  print("[env] ExternalStorageDirectory: " + externalDirStr);
  String recipients = Constants.recipients;

  CatcherOptions debugOptions =
      CatcherOptions(PageReportMode(showStackTrace: true), [
    ConsoleHandler(),
    FileHandler(File(path), printLogs: true),
    EmailManualHandler([recipients], printLogs: true)
    //SentryHandler(SentryClient(sopt))
  ]);

  /// Release configuration.
  /// Same as above, but once user accepts dialog,
  /// user will be prompted to send email with crash to support.
  CatcherOptions releaseOptions =
      CatcherOptions(PageReportMode(showStackTrace: true), [
    FileHandler(File(path), printLogs: true),
    EmailManualHandler([recipients], printLogs: true)
  ]);

  CatcherOptions profileOptions =
      CatcherOptions(PageReportMode(showStackTrace: true), [
    ConsoleHandler(),
    FileHandler(File(path), printLogs: true),
    EmailManualHandler([recipients], printLogs: true)
  ]);

  /// Pass root widget (MyApp) along with Catcher configuration:
  catcher.updateConfig(
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
    profileConfig: profileOptions,
  );

  print(window.physicalSize);
  print(Constants.windowAspectRatio);

  SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  if (Platform.isAndroid && isLargeScreen()) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  if (isSmallScreen()) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }
}

RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

final globalScaffoldKey = GlobalKey<ScaffoldState>();

class SanmillApp extends StatefulWidget {
  @override
  _SanmillAppState createState() => _SanmillAppState();
}

class _SanmillAppState extends State<SanmillApp> {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      print("[audio] Audio Player is not support Windows.");
      return;
    } else {
      Audios.loadSounds();
    }
  }

  @override
  Widget build(BuildContext context) {
    setSpecialCountryAndRegion(context);

    return MaterialApp(
      /// Add navigator key from Catcher.
      /// It will be used to navigate user to report page or to show dialog.
      navigatorKey: EnvironmentConfig.catcher ? Catcher.navigatorKey : null,
      key: globalScaffoldKey,
      navigatorObservers: [routeObserver],
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      //locale: Locale(Config.languageCode),
      theme: AppTheme.lightThemeData,
      darkTheme: AppTheme.darkThemeData,
      debugShowCheckedModeBanner: EnvironmentConfig.devMode,
      home: Scaffold(
        body: DoubleBackToCloseApp(
          child: NavigationHomeScreen(),
          snackBar: SnackBar(
            content: Text(S.of(context).tapBackAgainToLeave),
          ),
        ),
      ),
      /*
      WillPopScope(
              onWillPop: () async {
                Audios.disposePool();
                return true;
              },
      */
    );
  }
}
