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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/screens/navigation_home_screen.dart';
import 'package:sanmill/services/audios.dart';
import 'package:sanmill/shared/common/constants.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

import 'services/audios.dart';

Future<void> main() async {
  final catcher = Catcher(
    rootWidget: BetterFeedback(
      child: SanmillApp(),
      //localeOverride: Locale(Resources.of().languageCode),
    ),
    ensureInitialized: true,
  );

  String externalDirStr;
  try {
    final Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      externalDirStr = externalDir.path;
    } else {
      externalDirStr = ".";
    }
  } catch (e) {
    debugPrint(e.toString());
    externalDirStr = ".";
  }
  final String path = "$externalDirStr/${Constants.crashLogsFileName}";
  debugPrint("[env] ExternalStorageDirectory: $externalDirStr");
  final String recipients = Constants.recipients;

  final CatcherOptions debugOptions = CatcherOptions(PageReportMode(), [
    ConsoleHandler(),
    FileHandler(File(path), printLogs: true),
    EmailManualHandler([recipients], printLogs: true)
    //SentryHandler(SentryClient(sopt))
  ]);

  /// Release configuration.
  /// Same as above, but once user accepts dialog,
  /// user will be prompted to send email with crash to support.
  final CatcherOptions releaseOptions = CatcherOptions(PageReportMode(), [
    FileHandler(File(path), printLogs: true),
    EmailManualHandler([recipients], printLogs: true)
  ]);

  final CatcherOptions profileOptions = CatcherOptions(PageReportMode(), [
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

  debugPrint(window.physicalSize.toString());
  debugPrint(Constants.windowAspectRatio.toString());

  SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  if (Platform.isAndroid && isLargeScreen()) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
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

class SanmillApp extends StatelessWidget {
  final globalScaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    Audios.loadSounds();

    setSpecialCountryAndRegion(context);

    return MaterialApp(
      /// Add navigator key from Catcher.
      /// It will be used to navigate user to report page or to show dialog.
      navigatorKey: Catcher.navigatorKey,
      key: globalScaffoldKey,
      navigatorObservers: [routeObserver],
      localizationsDelegates: const [
        // ... app-specific localization delegate[s] here
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedLocales,
      theme: AppTheme.lightThemeData,
      darkTheme: AppTheme.darkThemeData,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: DoubleBackToCloseApp(
          snackBar: SnackBar(
            content: Text(Resources.of().strings.tapBackAgainToLeave),
          ),
          child: NavigationHomeScreen(),
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
