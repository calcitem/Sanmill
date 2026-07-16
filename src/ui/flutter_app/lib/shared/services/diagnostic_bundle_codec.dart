// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../experience_recording/models/user_action_event.dart';
import '../models/diagnostic_bundle.dart';
import 'diagnostic_config_snapshot.dart';

const String diagnosticBundleBegin =
    '-----BEGIN SANMILL DIAGNOSTIC BUNDLE v1-----';
const String diagnosticBundleEnd = '-----END SANMILL DIAGNOSTIC BUNDLE-----';

/// Canonical, checksummed text representation shared by copy, upload/import.
class DiagnosticBundleCodec {
  const DiagnosticBundleCodec._();

  static const int maxBundleBytes = 512 * 1024;
  static const int maxFeedbackBytes = 8 * 1024;
  static const int maxErrorBytes = 8 * 1024;
  static const int maxStackBytes = 64 * 1024;
  static const int maxConfigBytes = 32 * 1024;
  static const int maxGameBytes = 64 * 1024;
  static const int maxLogsBytes = 64 * 1024;
  static const int maxActionTrailBytes = 192 * 1024;

  static String encode(DiagnosticBundleV1 bundle) {
    final Map<String, dynamic> unsigned = _deepStringMap(
      bundle.toUnsignedJson(),
    );
    if (_truncateField(
      unsigned['report'] as Map<String, dynamic>,
      'feedbackText',
      maxFeedbackBytes,
    )) {
      _markMissing(unsigned, 'feedback text truncated to 8 KiB');
    }
    if (_truncateField(
      unsigned['report'] as Map<String, dynamic>,
      'errorMessage',
      maxErrorBytes,
    )) {
      _markMissing(unsigned, 'error message truncated to 8 KiB');
    }
    if (_truncateField(
      unsigned['report'] as Map<String, dynamic>,
      'stackTrace',
      maxStackBytes,
    )) {
      _markMissing(unsigned, 'stack trace truncated to 64 KiB');
    }
    if (_truncateLogField(unsigned, 'logs', maxLogsBytes)) {
      _markMissing(unsigned, 'oldest logs truncated to 64 KiB');
    }
    _enforceComponentSize(unsigned, 'config', maxConfigBytes);
    _enforceComponentSize(unsigned, 'game', maxGameBytes);
    _trimTrail(unsigned);

    String encoded = _encodeSigned(unsigned);
    while (utf8.encode(encoded).length > maxBundleBytes) {
      final Map<String, dynamic> trail =
          unsigned['actionTrail'] as Map<String, dynamic>;
      final List<dynamic> events = trail['events'] as List<dynamic>;
      if (events.isNotEmpty) {
        events.removeAt(0);
        trail['truncatedEventCount'] =
            (trail['truncatedEventCount'] as int) + 1;
      } else if (unsigned['logs'] is String &&
          (unsigned['logs'] as String).isNotEmpty) {
        final String logs = unsigned['logs'] as String;
        unsigned['logs'] = _truncateUtf8Suffix(
          logs,
          utf8.encode(logs).length * 3 ~/ 4,
          marker: '[... oldest logs truncated ...]\n',
        );
        _markMissing(unsigned, 'oldest logs truncated for bundle size');
      } else {
        throw const FormatException(
          'Diagnostic bundle metadata exceeds the 512 KiB limit.',
        );
      }
      encoded = _encodeSigned(unsigned);
    }
    return encoded;
  }

  static DiagnosticBundleV1 decode(String input) {
    if (utf8.encode(input).length > 2 * 1024 * 1024) {
      throw const FormatException('Diagnostic input exceeds 2 MiB.');
    }
    final Map<String, dynamic> json = _extractJsonObject(input);
    final Set<String> allowedKeys = <String>{
      'schema',
      'version',
      'bundleId',
      'createdAtUtc',
      'application',
      'report',
      'config',
      'game',
      'actionTrail',
      'logs',
      'sanitizerVersion',
      'missingCapabilities',
      'integrity',
    };
    _rejectUnknown(json, allowedKeys, 'bundle');
    if (json['schema'] != DiagnosticBundleV1.schema ||
        json['version'] != DiagnosticBundleV1.version) {
      throw const FormatException('Unsupported diagnostic bundle schema.');
    }
    if (utf8.encode(jsonEncode(json)).length > maxBundleBytes) {
      throw const FormatException('Diagnostic bundle exceeds 512 KiB.');
    }
    final String normalizedText =
        '$diagnosticBundleBegin\n'
        '${const JsonEncoder.withIndent('  ').convert(_canonicalize(json))}\n'
        '$diagnosticBundleEnd';
    if (utf8.encode(normalizedText).length > maxBundleBytes) {
      throw const FormatException('Diagnostic bundle exceeds 512 KiB.');
    }
    _verifyIntegrity(json);

    final String bundleId = _boundedString(json['bundleId'], 'bundleId', 128);
    final DateTime? createdAt = DateTime.tryParse(
      _boundedString(json['createdAtUtc'], 'createdAtUtc', 64),
    );
    if (createdAt == null || !createdAt.isUtc) {
      throw const FormatException('createdAtUtc must be a UTC timestamp.');
    }
    final Map<String, dynamic> application = _object(
      json['application'],
      'application',
    );
    _validateApplication(application);
    final Map<String, dynamic> report = _object(json['report'], 'report');
    _rejectUnknown(report, const <String>{
      'kind',
      'feedbackText',
      'errorMessage',
      'stackTrace',
    }, 'report');
    final DiagnosticReportKind kind = _reportKind(report['kind']);
    final String? feedbackText = _optionalBoundedString(
      report['feedbackText'],
      'feedbackText',
      maxFeedbackBytes,
    );
    final String? errorMessage = _optionalBoundedString(
      report['errorMessage'],
      'errorMessage',
      maxErrorBytes,
    );
    final String? stackTrace = _optionalBoundedString(
      report['stackTrace'],
      'stackTrace',
      maxStackBytes,
    );
    final Map<String, dynamic> config = _object(json['config'], 'config');
    _ensureBytes(config, maxConfigBytes, 'config');
    DiagnosticConfigSnapshot.validate(config);
    final Map<String, dynamic> game = _object(json['game'], 'game');
    _validateGame(game);
    _ensureBytes(game, maxGameBytes, 'game');
    final DiagnosticActionTrailSnapshot actionTrail =
        DiagnosticActionTrailSnapshot.fromJson(
          _object(json['actionTrail'], 'actionTrail'),
        );
    if (actionTrail.checkpoint case final ActionTrailCheckpoint checkpoint) {
      DiagnosticConfigSnapshot.validate(checkpoint.safeConfig);
      _validateGame(checkpoint.game);
      _ensureBytes(checkpoint.game, maxGameBytes, 'checkpoint game');
    }
    _ensureBytes(actionTrail.toJson(), maxActionTrailBytes, 'actionTrail');
    final String? logs = _optionalBoundedString(
      json['logs'],
      'logs',
      maxLogsBytes,
    );
    final Object? missingRaw = json['missingCapabilities'];
    if (missingRaw is! List<dynamic> ||
        missingRaw.length > 64 ||
        missingRaw.any(
          (dynamic value) => value is! String || value.length > 160,
        )) {
      throw const FormatException('Invalid missingCapabilities list.');
    }
    return DiagnosticBundleV1(
      bundleId: bundleId,
      createdAtUtc: createdAt,
      application: application,
      kind: kind,
      feedbackText: feedbackText,
      errorMessage: errorMessage,
      stackTrace: stackTrace,
      config: config,
      game: game,
      actionTrail: actionTrail,
      logs: logs,
      sanitizerVersion: _boundedString(
        json['sanitizerVersion'],
        'sanitizerVersion',
        32,
      ),
      missingCapabilities: missingRaw.cast<String>(),
    );
  }

  static String _encodeSigned(Map<String, dynamic> unsigned) {
    final Map<String, dynamic> canonicalUnsigned =
        (_canonicalize(unsigned) as Map<String, dynamic>?)!;
    final String digest = sha256
        .convert(utf8.encode(jsonEncode(canonicalUnsigned)))
        .toString();
    final Map<String, dynamic> signed = <String, dynamic>{
      ...canonicalUnsigned,
      'integrity': <String, dynamic>{'algorithm': 'SHA-256', 'digest': digest},
    };
    final String pretty = const JsonEncoder.withIndent(
      '  ',
    ).convert(_canonicalize(signed));
    return '$diagnosticBundleBegin\n$pretty\n$diagnosticBundleEnd';
  }

  static void _verifyIntegrity(Map<String, dynamic> json) {
    final Map<String, dynamic> integrity = _object(
      json['integrity'],
      'integrity',
    );
    _rejectUnknown(integrity, const <String>{
      'algorithm',
      'digest',
    }, 'integrity');
    if (integrity['algorithm'] != 'SHA-256') {
      throw const FormatException('Unsupported bundle checksum algorithm.');
    }
    final String expected = _boundedString(
      integrity['digest'],
      'integrity.digest',
      64,
    );
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('Invalid SHA-256 checksum encoding.');
    }
    final Map<String, dynamic> unsigned = _deepStringMap(json)
      ..remove('integrity');
    final String actual = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(unsigned))))
        .toString();
    if (actual != expected) {
      throw const FormatException('Diagnostic bundle checksum mismatch.');
    }
  }

  static Map<String, dynamic> _extractJsonObject(String input) {
    String candidate = input.trim();
    final Object? direct = _tryJsonDecode(candidate);
    if (direct is String) {
      return _extractJsonObject(direct);
    }
    if (direct is Map<String, dynamic>) {
      if (direct['schema'] == DiagnosticBundleV1.schema) {
        return direct;
      }
      final Object? embedded = _findEmbeddedBundle(direct);
      if (embedded is String) {
        return _extractJsonObject(embedded);
      }
      if (embedded is Map<String, dynamic>) {
        return embedded;
      }
    }
    final int begin = candidate.indexOf(diagnosticBundleBegin);
    if (begin >= 0) {
      final int contentStart = begin + diagnosticBundleBegin.length;
      final int end = candidate.indexOf(diagnosticBundleEnd, contentStart);
      if (end < 0) {
        throw const FormatException('Diagnostic bundle end marker is missing.');
      }
      candidate = candidate.substring(contentStart, end).trim();
    }
    candidate = candidate
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();

    Object? decoded;
    try {
      decoded = jsonDecode(candidate);
    } on FormatException {
      final int firstBrace = candidate.indexOf('{');
      final int lastBrace = candidate.lastIndexOf('}');
      if (firstBrace < 0 || lastBrace <= firstBrace) {
        rethrow;
      }
      decoded = jsonDecode(candidate.substring(firstBrace, lastBrace + 1));
    }
    if (decoded is String) {
      return _extractJsonObject(decoded);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Diagnostic bundle root must be an object.');
    }
    if (decoded['schema'] == DiagnosticBundleV1.schema) {
      return decoded;
    }
    final Object? embedded = _findEmbeddedBundle(decoded);
    if (embedded is String) {
      return _extractJsonObject(embedded);
    }
    if (embedded is Map<String, dynamic>) {
      return embedded;
    }
    throw const FormatException('No Sanmill diagnostic bundle was found.');
  }

  static Object? _tryJsonDecode(String value) {
    if (!value.startsWith('{') &&
        !value.startsWith('[') &&
        !value.startsWith('"')) {
      return null;
    }
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static Object? _findEmbeddedBundle(Object? value, [int depth = 0]) {
    if (depth > 10) {
      return null;
    }
    if (value is Map<dynamic, dynamic>) {
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        final String key = entry.key.toString().toLowerCase();
        if ((key == 'sanmilldiagnosticbundle' ||
                key == 'diagnosticbundle' ||
                key == 'bundle') &&
            (entry.value is String || entry.value is Map<String, dynamic>)) {
          return entry.value;
        }
        final Object? nested = _findEmbeddedBundle(entry.value, depth + 1);
        if (nested != null) {
          return nested;
        }
      }
    } else if (value is List<dynamic>) {
      for (final Object? item in value) {
        final Object? nested = _findEmbeddedBundle(item, depth + 1);
        if (nested != null) {
          return nested;
        }
      }
    } else if (value is String && value.contains(diagnosticBundleBegin)) {
      return value;
    }
    return null;
  }

  static void _trimTrail(Map<String, dynamic> unsigned) {
    final Map<String, dynamic> trail =
        unsigned['actionTrail'] as Map<String, dynamic>;
    final List<dynamic> events = trail['events'] as List<dynamic>;
    while (utf8.encode(jsonEncode(trail)).length > maxActionTrailBytes &&
        events.isNotEmpty) {
      events.removeAt(0);
      trail['truncatedEventCount'] = (trail['truncatedEventCount'] as int) + 1;
    }
    if (utf8.encode(jsonEncode(trail)).length > maxActionTrailBytes) {
      throw const FormatException('Action checkpoint exceeds 192 KiB.');
    }
  }

  static bool _truncateField(
    Map<String, dynamic> object,
    String key,
    int maxBytes,
  ) {
    final Object? value = object[key];
    if (value is! String || utf8.encode(value).length <= maxBytes) {
      return false;
    }
    object[key] = _truncateUtf8(value, maxBytes);
    return true;
  }

  static bool _truncateLogField(
    Map<String, dynamic> object,
    String key,
    int maxBytes,
  ) {
    final Object? value = object[key];
    if (value is! String || utf8.encode(value).length <= maxBytes) {
      return false;
    }
    object[key] = _truncateUtf8Suffix(
      value,
      maxBytes,
      marker: '[... oldest logs truncated ...]\n',
    );
    return true;
  }

  static String _truncateUtf8(String value, int maxBytes) {
    if (utf8.encode(value).length <= maxBytes) {
      return value;
    }
    int low = 0;
    int high = value.length;
    while (low < high) {
      final int middle = (low + high + 1) ~/ 2;
      if (utf8.encode(value.substring(0, middle)).length <= maxBytes) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    int end = low;
    if (end < value.length) {
      final int codeUnit = value.codeUnitAt(end);
      if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        end--;
      }
    }
    return value.substring(0, end);
  }

  static String _truncateUtf8Suffix(
    String value,
    int maxBytes, {
    required String marker,
  }) {
    final int markerBytes = utf8.encode(marker).length;
    final int contentBudget = maxBytes - markerBytes;
    if (contentBudget <= 0) {
      return _truncateUtf8(marker, maxBytes);
    }
    int low = 0;
    int high = value.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (utf8.encode(value.substring(middle)).length <= contentBudget) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    int start = low;
    if (start < value.length) {
      final int codeUnit = value.codeUnitAt(start);
      if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        start++;
      }
    }
    final int nextLine = value.indexOf('\n', start);
    if (nextLine >= 0 && nextLine + 1 < value.length) {
      start = nextLine + 1;
    }
    return '$marker${value.substring(start)}';
  }

  static void _markMissing(Map<String, dynamic> unsigned, String message) {
    final List<dynamic> missing =
        unsigned['missingCapabilities'] as List<dynamic>;
    if (!missing.contains(message)) {
      missing.add(message);
    }
  }

  static void _enforceComponentSize(
    Map<String, dynamic> object,
    String key,
    int maxBytes,
  ) {
    _ensureBytes(object[key], maxBytes, key);
  }

  static void _ensureBytes(Object? value, int maxBytes, String label) {
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      throw FormatException('$label exceeds $maxBytes bytes.');
    }
  }

  static void _validateApplication(Map<String, dynamic> application) {
    const Set<String> required = <String>{
      'applicationId',
      'version',
      'buildNumber',
      'platform',
      'channel',
      'sourceRevision',
      'sourceUrl',
      'declaredDistributor',
      'signing',
    };
    _rejectUnknown(application, required, 'application');
    for (final String key in required.difference(const <String>{'signing'})) {
      _boundedString(application[key], 'application.$key', 512);
    }
    final Map<String, dynamic> signing = _object(
      application['signing'],
      'application.signing',
    );
    _rejectUnknown(signing, const <String>{
      'kind',
      'status',
      'sha256',
    }, 'application.signing');
    _boundedString(signing['kind'], 'application.signing.kind', 96);
    _boundedString(signing['status'], 'application.signing.status', 96);
    if (signing['sha256'] != null) {
      final String digest = _boundedString(
        signing['sha256'],
        'application.signing.sha256',
        128,
      );
      if (!RegExp(r'^[A-Fa-f0-9:]{32,128}$').hasMatch(digest)) {
        throw const FormatException('Invalid signing digest.');
      }
    }
  }

  static void _validateGame(Map<String, dynamic> game) {
    const Map<String, int> fields = <String, int>{
      'fen': 512,
      'mode': 96,
      'phase': 96,
      'sideToMove': 96,
      'zobrist': 128,
      'moves': maxGameBytes,
      'lastMove': 160,
    };
    _rejectUnknown(game, fields.keys.toSet(), 'game');
    for (final MapEntry<String, dynamic> entry in game.entries) {
      _boundedString(entry.value, 'game.${entry.key}', fields[entry.key]!);
    }
  }

  static DiagnosticReportKind _reportKind(Object? value) {
    if (value is String) {
      for (final DiagnosticReportKind kind in DiagnosticReportKind.values) {
        if (kind.name == value) {
          return kind;
        }
      }
    }
    throw FormatException('Unknown report kind: $value');
  }

  static String _boundedString(Object? value, String label, int maxBytes) {
    if (value is! String ||
        value.isEmpty ||
        utf8.encode(value).length > maxBytes) {
      throw FormatException('$label must be a non-empty bounded string.');
    }
    return value;
  }

  static String? _optionalBoundedString(
    Object? value,
    String label,
    int maxBytes,
  ) {
    if (value == null) {
      return null;
    }
    if (value is! String || utf8.encode(value).length > maxBytes) {
      throw FormatException('$label exceeds its size limit.');
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value, String label) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$label must be a JSON object.');
    }
    return value;
  }

  static void _rejectUnknown(
    Map<String, dynamic> object,
    Set<String> allowed,
    String label,
  ) {
    final Set<String> unknown = object.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown $label keys: ${unknown.toList()..sort()}');
    }
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map<dynamic, dynamic>) {
      final List<String> keys = value.keys.map((dynamic key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List<dynamic>) {
      return value.map<Object?>(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _deepStringMap(Map<String, dynamic> source) {
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }
}
