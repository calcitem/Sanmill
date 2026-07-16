// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../experience_recording/models/user_action_event.dart';
import '../../experience_recording/services/diagnostic_action_trail_service.dart';
import '../../experience_recording/services/diagnostic_reproduction_service.dart';
import '../models/diagnostic_bundle.dart';
import 'diagnostic_bundle_codec.dart';
import 'diagnostic_config_snapshot.dart';
import 'diagnostic_game_context.dart';
import 'diagnostic_sanitizer.dart';
import 'distribution_provenance.dart';
import 'environment_config.dart';
import 'logger.dart';

/// Frozen local report captured before the user decides what to include.
class DiagnosticReportDraft {
  const DiagnosticReportDraft({
    required this.id,
    required this.createdAtUtc,
    required this.kind,
    required this.config,
    required this.game,
    required this.actionTrail,
    required this.logs,
    this.feedbackText,
    this.errorMessage,
    this.stackTrace,
  });

  factory DiagnosticReportDraft.fromJson(Map<String, dynamic> json) {
    final Object? rawConfig = json['config'];
    final Object? rawGame = json['game'];
    final Object? rawTrail = json['actionTrail'];
    if (rawConfig is! Map<String, dynamic> ||
        rawGame is! Map<String, dynamic> ||
        rawTrail is! Map<String, dynamic>) {
      throw const FormatException('Invalid diagnostic report draft.');
    }
    final String kindName = json['kind'] as String? ?? '';
    final DiagnosticReportKind kind = DiagnosticReportKind.values.firstWhere(
      (DiagnosticReportKind value) => value.name == kindName,
      orElse: () => throw FormatException('Unknown report kind: $kindName'),
    );
    return DiagnosticReportDraft(
      id: json['id'] as String,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
      kind: kind,
      feedbackText: json['feedbackText'] as String?,
      errorMessage: json['errorMessage'] as String?,
      stackTrace: json['stackTrace'] as String?,
      config: rawConfig,
      game: rawGame,
      actionTrail: DiagnosticActionTrailSnapshot.fromJson(rawTrail),
      logs: json['logs'] as String? ?? '',
    );
  }

  final String id;
  final DateTime createdAtUtc;
  final DiagnosticReportKind kind;
  final String? feedbackText;
  final String? errorMessage;
  final String? stackTrace;
  final Map<String, dynamic> config;
  final Map<String, dynamic> game;
  final DiagnosticActionTrailSnapshot actionTrail;
  final String logs;

  bool get isCrash => kind != DiagnosticReportKind.feedback;

  DiagnosticReportDraft copyWith({String? feedbackText}) {
    return DiagnosticReportDraft(
      id: id,
      createdAtUtc: createdAtUtc,
      kind: kind,
      feedbackText: feedbackText ?? this.feedbackText,
      errorMessage: errorMessage,
      stackTrace: stackTrace,
      config: config,
      game: game,
      actionTrail: actionTrail,
      logs: logs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'kind': kind.name,
    if (feedbackText != null) 'feedbackText': feedbackText,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (stackTrace != null) 'stackTrace': stackTrace,
    'config': config,
    'game': game,
    'actionTrail': actionTrail.toJson(),
    'logs': logs,
  };
}

class DiagnosticReportSelection {
  const DiagnosticReportSelection({
    required this.includeConfig,
    required this.includeActionTrail,
    required this.includeLogs,
  });

  factory DiagnosticReportSelection.defaultsFor(DiagnosticReportDraft draft) {
    return DiagnosticReportSelection(
      includeConfig: true,
      includeActionTrail: true,
      includeLogs: draft.isCrash,
    );
  }

  final bool includeConfig;
  final bool includeActionTrail;
  final bool includeLogs;
}

/// Creates local drafts, assembles exact previews and performs one-shot sends.
class DiagnosticReportService {
  factory DiagnosticReportService() => _instance;

  DiagnosticReportService._();

  static final DiagnosticReportService _instance = DiagnosticReportService._();
  static const int maxDrafts = 5;
  static const Duration draftTtl = Duration(days: 7);

  final ValueNotifier<List<DiagnosticReportDraft>> drafts =
      ValueNotifier<List<DiagnosticReportDraft>>(
        const <DiagnosticReportDraft>[],
      );
  bool _initialized = false;

  bool get remoteSendingAvailable =>
      !kIsWeb &&
      !EnvironmentConfig.diagnosticsRemoteDisabled &&
      _isGlitchTipDsn(EnvironmentConfig.diagnosticsDsn) &&
      EnvironmentConfig.diagnosticsRecipient.trim().isNotEmpty &&
      _isWebUrl(EnvironmentConfig.diagnosticsPrivacyUrl);

  static bool _isGlitchTipDsn(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isNotEmpty &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last.isNotEmpty;
  }

  static bool _isWebUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _loadDrafts();
  }

  Future<DiagnosticReportDraft> captureCrash({
    required Object error,
    required StackTrace stackTrace,
    DiagnosticReportKind kind = DiagnosticReportKind.crash,
  }) async {
    await initialize();
    final String id = const Uuid().v4();
    final DiagnosticReportDraft draft = DiagnosticReportDraft(
      id: id,
      createdAtUtc: DateTime.now().toUtc(),
      kind: kind,
      errorMessage: DiagnosticSanitizer.sanitizeText(
        error.toString(),
        reportSalt: id,
      ),
      stackTrace: DiagnosticSanitizer.sanitizeText(
        stackTrace.toString(),
        reportSalt: id,
      ),
      config: DiagnosticConfigSnapshot.capture(),
      game: DiagnosticGameContext.capture(),
      actionTrail: DiagnosticActionTrailService().freeze(),
      logs: DiagnosticSanitizer.sanitizedMemoryLogs(reportSalt: id),
    );
    await _saveDraft(draft);
    return draft;
  }

  Future<DiagnosticReportDraft> createFeedback({
    String feedbackText = '',
  }) async {
    await initialize();
    final String id = const Uuid().v4();
    final DiagnosticReportDraft draft = DiagnosticReportDraft(
      id: id,
      createdAtUtc: DateTime.now().toUtc(),
      kind: DiagnosticReportKind.feedback,
      feedbackText: feedbackText,
      config: DiagnosticConfigSnapshot.capture(),
      game: DiagnosticGameContext.capture(),
      actionTrail: DiagnosticActionTrailService().freeze(),
      logs: DiagnosticSanitizer.sanitizedMemoryLogs(reportSalt: id),
    );
    return draft;
  }

  Future<String> buildBundleText(
    DiagnosticReportDraft draft,
    DiagnosticReportSelection selection, {
    String? feedbackText,
  }) async {
    final DistributionProvenance provenance =
        await DistributionProvenance.collect();
    final List<String> missing = <String>[];
    if (!selection.includeConfig) {
      missing.add('config omitted by user');
    }
    if (!selection.includeActionTrail) {
      missing.add('action trail omitted by user');
    } else if (draft.actionTrail.checkpoint == null) {
      missing.add('no action checkpoint available');
    }
    if (!selection.includeLogs) {
      missing.add('logs omitted by user');
    }
    if (provenance.signingDigest == null) {
      missing.add('platform signing digest unavailable');
    }
    final DiagnosticActionTrailSnapshot trail = selection.includeActionTrail
        ? draft.actionTrail
        : DiagnosticActionTrailSnapshot(
            checkpoint: null,
            events: const <UserActionEventV1>[],
            truncatedEventCount: 0,
            recordedAtUtc: draft.createdAtUtc,
          );
    final Map<String, dynamic> config = selection.includeConfig
        ? draft.config
        : const <String, dynamic>{
            'generalSettings': <String, dynamic>{},
            'ruleSettings': <String, dynamic>{},
            'displaySettings': <String, dynamic>{},
            'colorSettings': <String, dynamic>{},
            'informationalOnly': <String, dynamic>{},
          };
    return DiagnosticBundleCodec.encode(
      DiagnosticBundleV1(
        bundleId: draft.id,
        createdAtUtc: draft.createdAtUtc,
        application: provenance.toJson(),
        kind: draft.kind,
        feedbackText: feedbackText ?? draft.feedbackText,
        errorMessage: draft.errorMessage,
        stackTrace: draft.stackTrace,
        config: config,
        game: draft.game,
        actionTrail: trail,
        logs: selection.includeLogs ? draft.logs : null,
        sanitizerVersion: diagnosticSanitizerVersion,
        missingCapabilities: missing,
      ),
    );
  }

  /// Sends exactly [bundleText]. It never rebuilds, retries or queues a report.
  Future<void> send(String bundleText) async {
    DiagnosticReplayGuard.requireAllowed('Diagnostic report sending');
    if (!remoteSendingAvailable) {
      throw StateError('Remote diagnostic sending is not configured.');
    }
    final DiagnosticBundleV1 validated = DiagnosticBundleCodec.decode(
      bundleText,
    );
    await GlitchTipDiagnosticTransport.send(
      dsn: EnvironmentConfig.diagnosticsDsn,
      bundleText: bundleText,
      bundle: validated,
    );
  }

  Future<void> deleteDraft(String id) async {
    drafts.value = drafts.value
        .where((DiagnosticReportDraft draft) => draft.id != id)
        .toList(growable: false);
    if (kIsWeb) {
      return;
    }
    final File file = await _draftFile(id);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> retainFeedbackDraft(
    DiagnosticReportDraft draft,
    String feedbackText,
  ) {
    return _saveDraft(draft.copyWith(feedbackText: feedbackText));
  }

  Future<void> _saveDraft(DiagnosticReportDraft draft) async {
    final List<DiagnosticReportDraft> updated = <DiagnosticReportDraft>[
      draft,
      ...drafts.value.where(
        (DiagnosticReportDraft existing) => existing.id != draft.id,
      ),
    ];
    final List<DiagnosticReportDraft> retained = updated
        .take(maxDrafts)
        .toList(growable: false);
    drafts.value = retained;
    if (kIsWeb) {
      return;
    }
    final File target = await _draftFile(draft.id);
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(draft.toJson()), flush: true);
    await _replaceDraftFile(temporary, target);
    await _deleteUnretainedFiles(
      retained.map((DiagnosticReportDraft d) => d.id).toSet(),
    );
  }

  Future<void> _loadDrafts() async {
    if (kIsWeb) {
      return;
    }
    final Directory directory = await _draftDirectory();
    final List<DiagnosticReportDraft> loaded = <DiagnosticReportDraft>[];
    for (final File file in directory.listSync().whereType<File>().where(
      (File file) => file.path.endsWith('.json'),
    )) {
      try {
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Draft root must be an object.');
        }
        final DiagnosticReportDraft draft = DiagnosticReportDraft.fromJson(
          decoded,
        );
        if (DateTime.now().toUtc().difference(draft.createdAtUtc) > draftTtl) {
          await file.delete();
        } else {
          loaded.add(draft);
        }
      } on Object catch (error) {
        logger.w('[DiagnosticReport] Removing invalid draft: $error');
        await file.delete();
      }
    }
    loaded.sort(
      (DiagnosticReportDraft a, DiagnosticReportDraft b) =>
          b.createdAtUtc.compareTo(a.createdAtUtc),
    );
    drafts.value = loaded.take(maxDrafts).toList(growable: false);
    await _deleteUnretainedFiles(
      drafts.value.map((DiagnosticReportDraft draft) => draft.id).toSet(),
    );
  }

  Future<void> _deleteUnretainedFiles(Set<String> retainedIds) async {
    if (kIsWeb) {
      return;
    }
    final Directory directory = await _draftDirectory();
    for (final File file in directory.listSync().whereType<File>().where(
      (File file) => file.path.endsWith('.json'),
    )) {
      final String filename = file.uri.pathSegments.last;
      final String id = filename.substring(0, filename.length - 5);
      if (!retainedIds.contains(id)) {
        await file.delete();
      }
    }
  }

  Future<File> _draftFile(String id) async {
    final Directory directory = await _draftDirectory();
    return File('${directory.path}/$id.json');
  }

  Future<void> _replaceDraftFile(File temporary, File target) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (target.existsSync()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    }
  }

  Future<Directory> _draftDirectory() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory directory = Directory(
      '${support.path}/diagnostic_report_drafts',
    );
    await directory.create(recursive: true);
    return directory;
  }
}

/// Minimal one-shot Sentry-envelope transport supported by GlitchTip.
class GlitchTipDiagnosticTransport {
  const GlitchTipDiagnosticTransport._();

  static Future<void> send({
    required String dsn,
    required String bundleText,
    required DiagnosticBundleV1 bundle,
    http.Client? client,
  }) async {
    final Uri dsnUri = Uri.parse(dsn);
    if (!dsnUri.hasScheme ||
        dsnUri.host.isEmpty ||
        dsnUri.userInfo.isEmpty ||
        dsnUri.pathSegments.isEmpty) {
      throw const FormatException('Invalid GlitchTip DSN.');
    }
    final String publicKey = dsnUri.userInfo.split(':').first;
    final String projectId = dsnUri.pathSegments.last;
    if (publicKey.isEmpty || projectId.isEmpty) {
      throw const FormatException('Invalid GlitchTip DSN.');
    }
    final String pathPrefix = dsnUri.pathSegments
        .take(dsnUri.pathSegments.length - 1)
        .map(Uri.encodeComponent)
        .join('/');
    final Uri endpoint = dsnUri.replace(
      userInfo: '',
      path:
          '/${pathPrefix.isEmpty ? '' : '$pathPrefix/'}api/'
          '${Uri.encodeComponent(projectId)}/envelope/',
      queryParameters: <String, String>{
        'sentry_key': publicKey,
        'sentry_version': '7',
      },
    );
    final String eventId = sha256
        .convert(utf8.encode(bundle.bundleId))
        .toString()
        .substring(0, 32);
    final Map<String, dynamic> signing =
        bundle.application['signing'] as Map<String, dynamic>;
    final Map<String, dynamic> event = <String, dynamic>{
      'event_id': eventId,
      'timestamp': bundle.createdAtUtc.toIso8601String(),
      'platform': 'dart',
      'level': bundle.kind == DiagnosticReportKind.feedback ? 'info' : 'error',
      'message': <String, dynamic>{
        'formatted': bundle.errorMessage ?? 'Sanmill user feedback',
      },
      'tags': <String, String>{
        'application_id': bundle.application['applicationId'] as String,
        'distribution_channel': bundle.application['channel'] as String,
        'declared_distributor':
            bundle.application['declaredDistributor'] as String,
        'source_revision': bundle.application['sourceRevision'] as String,
        'report_kind': bundle.kind.name,
        'signing_status': signing['status'] as String,
        if (signing['sha256'] case final String digest)
          'signing_digest': digest,
      },
      'extra': <String, dynamic>{'sanmillDiagnosticBundle': bundleText},
    };
    final String payload = jsonEncode(event);
    final String envelope = <String>[
      jsonEncode(<String, String>{'event_id': eventId}),
      jsonEncode(<String, dynamic>{
        'type': 'event',
        'length': utf8.encode(payload).length,
      }),
      payload,
    ].join('\n');
    final http.Client transport = client ?? http.Client();
    final bool ownsClient = client == null;
    late final http.Response response;
    try {
      response = await transport
          .post(
            endpoint,
            headers: const <String, String>{
              'Content-Type': 'application/x-sentry-envelope',
            },
            body: envelope,
          )
          .timeout(const Duration(seconds: 20));
    } finally {
      if (ownsClient) {
        transport.close();
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GlitchTip rejected the report (${response.statusCode}).',
        uri: endpoint,
      );
    }
  }
}
