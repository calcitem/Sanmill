// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// catcher_service.dart

part of 'package:sanmill/main.dart';

late Catcher2 catcher;

/// Initializes the given [catcher]
Future<void> _initCatcher(Catcher2 catcher) async {
  final Map<String, String> customParameters =
      await _buildCrashReportParameters();
  late final String externalDirStr;

  if (kIsWeb ||
      Platform.isIOS ||
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS) {
    externalDirStr = ".";
  } else {
    try {
      final Directory? externalDir = await getExternalStorageDirectory();
      externalDirStr = externalDir != null ? externalDir.path : ".";
    } catch (e) {
      logger.e(e.toString());
      externalDirStr = ".";
    }
  }

  final String path = "$externalDirStr/${Constants.crashLogsFile}";
  logger.t("[env] ExternalStorageDirectory: $externalDirStr");

  final Catcher2Options debugOptions = Catcher2Options(
    kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS
        ? SilentReportMode()
        : PageReportMode(),
    <ReportHandler>[
      ConsoleHandler(),
      FileHandler(File(path), printLogs: true),
      SanmillEmailHandler(Constants.recipientEmails, printLogs: true),
    ],
    customParameters: customParameters,
  );

  /// Release configuration.
  /// Same as above, but once user accepts dialog,
  /// user will be prompted to send email with crash to support.
  final Catcher2Options releaseOptions = Catcher2Options(
    kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS
        ? SilentReportMode()
        : PageReportMode(),
    <ReportHandler>[
      FileHandler(File(path), printLogs: true),
      SanmillEmailHandler(Constants.recipientEmails, printLogs: true),
    ],
    customParameters: customParameters,
  );

  final Catcher2Options profileOptions =
      Catcher2Options(PageReportMode(), <ReportHandler>[
        ConsoleHandler(),
        FileHandler(File(path), printLogs: true),
        SanmillEmailHandler(Constants.recipientEmails, printLogs: true),
      ], customParameters: customParameters);

  /// Pass root widget (MyApp) along with Catcher configuration:
  catcher.updateConfig(
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
    profileConfig: profileOptions,
  );
}

Future<Map<String, String>> _buildCrashReportParameters() async {
  final Map<String, String> parameters = <String, String>{
    "PlatformDispatcher.locale": _formatLocale(
      PlatformDispatcher.instance.locale,
    ),
    "PlatformDispatcher.locales": _formatLocales(
      PlatformDispatcher.instance.locales,
    ),
    "DB.displaySettings.locale": _formatNullableLocale(
      DB().displaySettings.locale,
    ),
    "Platform": _platformName(),
  };

  parameters.addAll(await _buildPackageParameters());
  parameters.addAll(await _buildDeviceParameters());

  return parameters;
}

Future<Map<String, String>> _buildPackageParameters() async {
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return <String, String>{
      "App.version": packageInfo.version,
      "App.buildNumber": packageInfo.buildNumber,
      "App.packageName": packageInfo.packageName,
    };
  } catch (e) {
    logger.e("Failed to collect package info: $e");
    return <String, String>{"App.version": "unknown"};
  }
}

Future<Map<String, String>> _buildDeviceParameters() async {
  if (kIsWeb) {
    return <String, String>{"OS": "web"};
  }

  try {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo info = await deviceInfoPlugin.androidInfo;
      return <String, String>{
        "OS": "Android ${info.version.release}",
        "OS.sdkInt": info.version.sdkInt.toString(),
        "Device": "${info.brand} ${info.model}",
        "Device.manufacturer": info.manufacturer,
      };
    }

    if (Platform.isIOS) {
      final IosDeviceInfo info = await deviceInfoPlugin.iosInfo;
      return <String, String>{
        "OS": "iOS ${info.systemVersion}",
        "Device": info.utsname.machine,
        "Device.name": info.name,
      };
    }

    if (Platform.isLinux) {
      final LinuxDeviceInfo info = await deviceInfoPlugin.linuxInfo;
      return <String, String>{"OS": info.prettyName, "Device": "Linux"};
    }

    if (Platform.isWindows) {
      final WindowsDeviceInfo info = await deviceInfoPlugin.windowsInfo;
      return <String, String>{
        "OS": info.productName,
        "OS.buildNumber": info.buildNumber.toString(),
        "Device": "Windows",
      };
    }

    if (Platform.isMacOS) {
      final MacOsDeviceInfo info = await deviceInfoPlugin.macOsInfo;
      return <String, String>{
        "OS": "macOS ${info.osRelease}",
        "Device": info.model,
      };
    }
  } catch (e) {
    logger.e("Failed to collect device info: $e");
  }

  return <String, String>{"OS": Platform.operatingSystem};
}

void _updateCrashReportLocaleContext() {
  if (!EnvironmentConfig.catcher || kIsWeb || Platform.isIOS) {
    return;
  }

  final Catcher2Options? options = catcher.getCurrentConfig();
  if (options == null) {
    return;
  }

  options.customParameters["PlatformDispatcher.locale"] = _formatLocale(
    PlatformDispatcher.instance.locale,
  );
  options.customParameters["PlatformDispatcher.locales"] = _formatLocales(
    PlatformDispatcher.instance.locales,
  );
  options.customParameters["DB.displaySettings.locale"] = _formatNullableLocale(
    DB().displaySettings.locale,
  );
}

String _formatLocale(Locale locale) {
  return locale.toLanguageTag();
}

String _formatNullableLocale(Locale? locale) {
  return locale == null ? "system" : _formatLocale(locale);
}

String _formatLocales(List<Locale> locales) {
  return locales.map(_formatLocale).join(", ");
}

String _platformName() {
  if (kIsWeb) {
    return "web";
  }
  return Platform.operatingSystem;
}

/// Generates content for the options.
String generateOptionsContent() {
  String content = "";

  if (EnvironmentConfig.catcher && !kIsWeb && !Platform.isIOS) {
    final Catcher2Options options = catcher.getCurrentConfig()!;
    for (final dynamic value in options.customParameters.values) {
      final String str = value
          .toString()
          .replaceAll("setoption name ", "")
          .replaceAll("value", "=");
      content += "$str\n";
    }
  }

  return content;
}
