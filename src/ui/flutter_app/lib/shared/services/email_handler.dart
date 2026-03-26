// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// email_handler.dart

import 'package:catcher_2/handlers/base_email_handler.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

import '../../general_settings/services/config_import_export_service.dart';
import 'logger.dart';

/// A catcher_2 [ReportHandler] that sends crash reports via e-mail and
/// attaches a freshly-exported sanmill_config archive so the developer can
/// reproduce the exact user settings when investigating the crash.
///
/// Uses [FlutterEmailSender] (the same backend as the user-feedback flow)
/// rather than the flutter_mailer backend used by the built-in
/// [EmailManualHandler].
class SanmillEmailHandler extends BaseEmailHandler {
  SanmillEmailHandler(
    this.recipients, {
    this.sendHtml = true,
    this.printLogs = false,
    super.emailTitle,
    super.emailHeader,
    super.enableDeviceParameters = true,
    super.enableApplicationParameters = true,
    super.enableStackTrace = true,
    super.enableCustomParameters = true,
  }) : assert(recipients.isNotEmpty, "Recipients can't be empty");

  final List<String> recipients;
  final bool sendHtml;
  final bool printLogs;

  static const String _logTag = '[sanmill_email_handler]';

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    try {
      final String? configPath = await ConfigImportExportService.exportConfig();

      final List<String> attachments = <String>[
        if (report.screenshot?.path.isNotEmpty ?? false)
          report.screenshot!.path,
        ?configPath,
      ];

      _printLog(
        '$_logTag Sending crash report email '
        'with ${attachments.length} attachment(s)',
      );

      final Email email = Email(
        subject: getEmailTitle(report),
        recipients: recipients,
        body: sendHtml
            ? setupHtmlMessageText(report)
            : setupRawMessageText(report),
        attachmentPaths: attachments,
        isHTML: sendHtml,
      );

      await FlutterEmailSender.send(email);
      _printLog('$_logTag Email sent successfully');
      return true;
    } catch (e, st) {
      _printLog('$_logTag Failed to send email: $e\n$st');
      return false;
    }
  }

  @override
  List<PlatformType> getSupportedPlatforms() => <PlatformType>[
    PlatformType.android,
    PlatformType.iOS,
  ];

  void _printLog(String msg) {
    if (printLogs) {
      logger.i(msg);
    }
  }
}
