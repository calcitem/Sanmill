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

import 'package:catcher/catcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/navigation_home_screen.dart';
//import 'package:stack_trace/stack_trace.dart';

//import 'common/config.dart';
import 'services/audios.dart';

//import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  if (!(Platform.isAndroid || Platform.isIOS)) {
    runApp(SanmillApp());
    return;
  }

  var catcher = Catcher(rootWidget: SanmillApp(), ensureInitialized: true);

  //DateTime now = DateTime.now();
  //String formattedDate = DateFormat('yyyy-MM-dd_kk-mm').format(now);
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
  String path = externalDirStr + "/sanmill-crash-logs.txt";
  print("ExternalStorageDirectory: " + externalDirStr);
  String recipients = "calcitem@outlook.com";

  /// Create catcher configuration.
  /// Debug configuration with dialog report mode and console handler.
  /// It will show dialog and once user accepts it, error will be shown
  /// in console.
  //CatcherOptions debugOptions = CatcherOptions(
  //    PageReportMode(showStackTrace: true), [ConsoleHandler()]);
  //SentryOptions sopt = new SentryOptions();
  //sopt.dsn =
  //    "https://62c565096ba146a6b70bc57dbb72386c@o525088.ingest.sentry.io/5638585";

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

  SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }

  SystemChrome.setEnabledSystemUIOverlays([]);
}

RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

final globalScaffoldKey = GlobalKey<ScaffoldState>();

class SanmillApp extends StatefulWidget {
  //
  static const StatusBarHeight = 28.0;

  @override
  _SanmillAppState createState() => _SanmillAppState();
}

class _SanmillAppState extends State<SanmillApp> {
  @override
  void initState() {
    //Chain.capture(() {
    //  Config.loadSettings();
    //});
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      /// Add navigator key from Catcher.
      /// It will be used to navigate user to report page or to show dialog.
      navigatorKey: Catcher.navigatorKey,
      key: globalScaffoldKey,
      navigatorObservers: [routeObserver],
      localizationsDelegates: [
        // ... app-specific localization delegate[s] here
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('en', ''), // English, no country code
        const Locale.fromSubtags(
            languageCode: 'zh'), // Chinese *See Advanced Locales below*
        // ... other locales the app supports
      ],
      theme: ThemeData(primarySwatch: AppTheme.appPrimaryColor),
      debugShowCheckedModeBanner: false,
      home: WillPopScope(
        onWillPop: () async {
          Audios.release();
          return true;
        },
        child: NavigationHomeScreen(),
      ),
    );
  }
}
