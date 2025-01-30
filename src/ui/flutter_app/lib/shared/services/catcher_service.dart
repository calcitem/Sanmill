// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// catcher_service.dart

part of 'package:sanmill/main.dart';

late Catcher2 catcher;

/// Initializes the given [catcher]
Future<void> _initCatcher(Catcher2 catcher) async {
  final Map<String, String> customParameters = <String, String>{};
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
        EmailManualHandler(Constants.recipientEmails, printLogs: true)
      ],
      customParameters: customParameters);

  /// Release configuration.
  /// Same as above, but once user accepts dialog,
  /// user will be prompted to send email with crash to support.
  final Catcher2Options releaseOptions = Catcher2Options(
      kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS
          ? SilentReportMode()
          : PageReportMode(),
      <ReportHandler>[
        FileHandler(File(path), printLogs: true),
        EmailManualHandler(Constants.recipientEmails, printLogs: true)
      ],
      customParameters: customParameters);

  final Catcher2Options profileOptions = Catcher2Options(
      PageReportMode(),
      <ReportHandler>[
        ConsoleHandler(),
        FileHandler(File(path), printLogs: true),
        EmailManualHandler(Constants.recipientEmails, printLogs: true)
      ],
      customParameters: customParameters);

  /// Pass root widget (MyApp) along with Catcher configuration:
  catcher.updateConfig(
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
    profileConfig: profileOptions,
  );
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
