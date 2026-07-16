// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/material.dart';

import 'diagnostic_report_service.dart';

/// Catcher handler that only freezes a local draft. It never performs I/O to
/// the network and intentionally ignores Catcher's screenshot field.
class DiagnosticCatcherHandler extends ReportHandler {
  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    await DiagnosticReportService().captureCrash(
      error: report.error as Object? ?? StateError('Unknown Catcher error'),
      stackTrace: report.stackTrace is StackTrace
          ? report.stackTrace as StackTrace
          : StackTrace.fromString(report.stackTrace.toString()),
    );
    return true;
  }

  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;
}
