// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../experience_recording/models/user_action_event.dart';

enum DiagnosticReportKind { crash, feedback, engineFailure }

/// Validated content of a Sanmill Diagnostic Bundle v1.
class DiagnosticBundleV1 {
  const DiagnosticBundleV1({
    required this.bundleId,
    required this.createdAtUtc,
    required this.application,
    required this.kind,
    required this.config,
    required this.game,
    required this.actionTrail,
    required this.sanitizerVersion,
    required this.missingCapabilities,
    this.feedbackText,
    this.errorMessage,
    this.stackTrace,
    this.logs,
  });

  static const String schema = 'sanmill.diagnostic.bundle';
  static const int version = 1;

  final String bundleId;
  final DateTime createdAtUtc;
  final Map<String, dynamic> application;
  final DiagnosticReportKind kind;
  final String? feedbackText;
  final String? errorMessage;
  final String? stackTrace;
  final Map<String, dynamic> config;
  final Map<String, dynamic> game;
  final DiagnosticActionTrailSnapshot actionTrail;
  final String? logs;
  final String sanitizerVersion;
  final List<String> missingCapabilities;

  Map<String, dynamic> toUnsignedJson() => <String, dynamic>{
    'schema': schema,
    'version': version,
    'bundleId': bundleId,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'application': application,
    'report': <String, dynamic>{
      'kind': kind.name,
      if (feedbackText != null) 'feedbackText': feedbackText,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (stackTrace != null) 'stackTrace': stackTrace,
    },
    'config': config,
    'game': game,
    'actionTrail': actionTrail.toJson(),
    if (logs != null) 'logs': logs,
    'sanitizerVersion': sanitizerVersion,
    'missingCapabilities': missingCapabilities,
  };
}
