// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// system_ui_service.dart
//
// System UI, window title, and orientation helpers. Extracted from `main.dart`
// to keep the app shell separate from `mill.dart` and other features.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';
import '../themes/app_theme.dart';
import 'logger.dart';

/// Initializes the given [SystemChrome] UI (fullscreen vs overlay).
Future<void> initializeUI(bool isFullScreen) async {
  if (isFullScreen) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: <SystemUiOverlay>[],
    );
  } else {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Constants.isAndroid10Plus = await isAndroidAtLeastVersion10();
}

/// Runs once at startup from [main] after [DB.init]. [isFullScreen] comes from
/// display settings; passed in to avoid importing [Database] here (which would
/// create an import cycle with `mill.dart`).
Future<void> initAppSystemUi({required bool isFullScreen}) async {
  await initializeUI(isFullScreen);
}

bool _isWideLayout(BuildContext context) {
  final double w = MediaQuery.of(context).orientation == Orientation.portrait
      ? MediaQuery.of(context).size.width
      : MediaQuery.of(context).size.height;
  return w >= 600;
}

void initializeScreenOrientation(BuildContext context) {
  if (!_isWideLayout(context)) {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
}

const MethodChannel uiMethodChannel = MethodChannel('com.calcitem.sanmill/ui');

Future<void> setWindowTitle(String title) async {
  if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) {
    return;
  }

  await uiMethodChannel.invokeMethod('setWindowTitle', <String, String>{
    'title': title,
  });
}

TextStyle getMonospaceTitleTextStyle(BuildContext context) {
  String fontFamily = 'monospace';

  if (kIsWeb) {
    fontFamily = 'monospace';
  } else {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        fontFamily = 'monospace';
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        fontFamily = 'Menlo';
        break;
      case TargetPlatform.windows:
        fontFamily = 'Consolas';
    }
  }

  return Theme.of(context).textTheme.titleLarge!.copyWith(
    color: AppTheme.gamePageActionSheetTextColor,
    fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
    fontFamily: fontFamily,
  );
}

double calculateNCharWidth(BuildContext context, int width) {
  final TextPainter textPainter = TextPainter(
    text: TextSpan(
      text: 'A' * width,
      style: getMonospaceTitleTextStyle(context),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();

  return textPainter.size.width;
}

void safePop() {
  if (currentNavigatorKey.currentState?.canPop() ?? false) {
    currentNavigatorKey.currentState?.pop();
  } else {
    logger.w('Cannot pop');
  }
}

Future<int?> getAndroidSDKVersion() async {
  if (kIsWeb || !Platform.isAndroid) {
    return null;
  }

  final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
  final AndroidDeviceInfo androidDeviceInfo =
      await deviceInfoPlugin.androidInfo;
  return androidDeviceInfo.version.sdkInt;
}

Future<bool> isAndroidAtLeastVersion10() async {
  final int? sdkInt = await getAndroidSDKVersion();
  if (sdkInt != null && sdkInt > 28) {
    return true;
  }
  return false;
}
