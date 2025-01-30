// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// system_ui_service.dart

part of 'package:sanmill/main.dart';

/// Initializes the given [SystemChrome] ui
Future<void> initializeUI(bool isFullScreen) async {
  // TODO: [Leptopoda] Use layoutBuilder to add adaptiveness
  if (isFullScreen) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: <SystemUiOverlay>[]);
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

Future<void> _initUI() async {
  final bool isFullScreen = DB().displaySettings.isFullScreen;
  await initializeUI(isFullScreen);
}

void _initializeScreenOrientation(BuildContext context) {
  if (!isTablet(context)) {
    SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown
      ],
    );
  }
}

const MethodChannel uiMethodChannel = MethodChannel('com.calcitem.sanmill/ui');

Future<void> setWindowTitle(String title) async {
  if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) {
    // TODO: Support other desktop platforms.
    return;
  }

  await uiMethodChannel
      .invokeMethod('setWindowTitle', <String, String>{'title': title});
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
        break;
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

// This function should only be used when necessary,
// as it has been found that unexpected results may occur
// when calling InfoDialog.
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
    return true; // Android 10 corresponds to SDK version 29
  }
  return false;
}
