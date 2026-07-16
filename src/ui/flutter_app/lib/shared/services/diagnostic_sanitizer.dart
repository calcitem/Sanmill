// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';

import 'logger.dart';

/// Current redaction ruleset written into every diagnostic bundle.
const String diagnosticSanitizerVersion = '1.0.0';

/// Privacy boundary shared by action trails, logs and legacy recordings.
class DiagnosticSanitizer {
  const DiagnosticSanitizer._();

  static final RegExp _email = RegExp(
    r'\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _url = RegExp(
    r'''\b(?:https?|wss?)://[^\s<>"']+''',
    caseSensitive: false,
  );
  static final RegExp _ipv4 = RegExp(
    r'(?<![0-9])(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])'
    r'(?:\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])){3}(?![0-9])',
  );
  static final RegExp _ipv6 = RegExp(
    r'\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{0,4}\b',
    caseSensitive: false,
  );
  static final RegExp _mac = RegExp(
    r'\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b',
    caseSensitive: false,
  );
  static final RegExp _windowsPath = RegExp(
    r'\b[A-Za-z]:\\(?:[^\s\\/:*?"<>|]+\\)*[^\s\\/:*?"<>|]*',
  );
  static final RegExp _unixPath = RegExp(
    r'(?<![A-Za-z0-9])/(?:Users|home|data|storage|private|var|tmp|sdcard|mnt|Volumes|etc|opt|usr|Library|Applications)/[^\s]*',
    caseSensitive: false,
  );
  static final RegExp _authorization = RegExp(
    r'(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _secretAssignment = RegExp(
    r'\b(api[_-]?key|token|secret|password|cookie)'
    r'''(\s*[:=]\s*)["']?[^\s,"';}]+''',
    caseSensitive: false,
  );
  static final RegExp _sessionAssignment = RegExp(
    r'\b(session[_-]?id)(\s*[:=]\s*)'
    r'''["']?([^\s,"';}]+)''',
    caseSensitive: false,
  );
  static final RegExp _remoteContext = RegExp(
    r'(\[Remote\]\[[^\]]+\]\[[^\]]+\]\[)([^\]]+)'
    r'(\]\[)([^\]]+)(\]\[[^\]]+\])',
  );
  static final RegExp _peerAssignment = RegExp(
    r'\b(peer\s*=\s*)([^\s]+)',
    caseSensitive: false,
  );
  static final RegExp _longToken = RegExp(
    r'\b(?=[A-Za-z0-9_\-]{32,}\b)(?=[A-Za-z0-9_\-]*[A-Za-z])'
    r'(?=[A-Za-z0-9_\-]*[0-9])[A-Za-z0-9_\-]+\b',
  );

  /// Redacts common identifiers and credentials from arbitrary log text.
  static String sanitizeText(String input, {required String reportSalt}) {
    String value = input;
    value = value.replaceAllMapped(_remoteContext, (Match match) {
      final String session = match.group(2)!;
      final String round = match.group(4)!;
      return '${match.group(1)}${_hashUnlessMissing(reportSalt, session)}'
          '${match.group(3)}${_hashUnlessMissing(reportSalt, round)}'
          '${match.group(5)}';
    });
    value = value.replaceAllMapped(
      _peerAssignment,
      (Match match) =>
          '${match.group(1)}${_hashUnlessMissing(reportSalt, match.group(2)!)}',
    );
    value = value.replaceAllMapped(
      _sessionAssignment,
      (Match match) =>
          '${match.group(1)}${match.group(2)}'
          '<hash:${_saltedHash(reportSalt, match.group(3)!)}>',
    );
    value = value.replaceAllMapped(
      _authorization,
      (Match match) => '${match.group(1)}<redacted-authorization>',
    );
    value = value.replaceAllMapped(
      _secretAssignment,
      (Match match) => '${match.group(1)}${match.group(2)}<redacted-secret>',
    );
    value = value
        .replaceAll(_email, '<redacted-email>')
        .replaceAll(_url, '<redacted-url>')
        .replaceAll(_ipv4, '<redacted-ip>')
        .replaceAll(_ipv6, '<redacted-ip>')
        .replaceAll(_mac, '<redacted-mac>')
        .replaceAll(_windowsPath, '<redacted-path>')
        .replaceAll(_unixPath, '<redacted-path>')
        .replaceAllMapped(
          _longToken,
          (Match match) => '<hash:${_saltedHash(reportSalt, match.group(0)!)}>',
        );
    return value;
  }

  /// Produces a mainline-only move representation without identifying tags,
  /// comments, variations or arbitrary imported file content.
  static String sanitizeMoveText(String input) {
    if (input.isEmpty) {
      return '';
    }
    final List<String> safeTags = <String>[];
    final RegExp tag = RegExp(r'^\s*\[([A-Za-z0-9_]+)\s+"([^"]*)"\]\s*$');
    const Set<String> allowedTags = <String>{
      'FEN',
      'SetUp',
      'Variant',
      'Result',
    };
    final List<String> moveLines = <String>[];
    for (final String line in const LineSplitter().convert(input)) {
      final Match? match = tag.firstMatch(line);
      if (match != null) {
        if (allowedTags.contains(match.group(1))) {
          safeTags.add('[${match.group(1)} "${match.group(2)}"]');
        }
      } else {
        moveLines.add(line);
      }
    }

    String moves = moveLines.join(' ');
    moves = _stripBalancedSections(moves, '(', ')');
    moves = _stripBalancedSections(moves, '{', '}');
    moves = moves
        .replaceAll(RegExp(r';[^\r\n]*'), ' ')
        .replaceAll(RegExp(r'\$[0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (moves.length > 64 * 1024) {
      moves = moves.substring(0, 64 * 1024);
    }
    return <String>[...safeTags, if (moves.isNotEmpty) moves].join('\n');
  }

  /// Converts an unreviewed legacy payload into registered JSON scalars.
  ///
  /// Raw clipboard/file/PGN/settings values are represented only by metadata.
  static Map<String, dynamic> sanitizeLegacyPayload(
    Map<String, dynamic> input,
  ) {
    final Map<String, dynamic> output = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in input.entries) {
      final String lowerKey = entry.key.toLowerCase();
      final Object? value = entry.value;
      if (lowerKey.contains('pgn') ||
          lowerKey.contains('content') ||
          lowerKey.contains('clipboard') ||
          lowerKey.contains('prompt') ||
          lowerKey.contains('reply') ||
          lowerKey.contains('response') ||
          lowerKey.contains('path') ||
          lowerKey.contains('filename') ||
          lowerKey.contains('apikey') ||
          lowerKey.contains('token') ||
          lowerKey.contains('secret') ||
          lowerKey.contains('url') ||
          lowerKey.contains('settings')) {
        if (value is String) {
          output['lengthBucket'] = lengthBucket(value.length);
        } else if (value is List<dynamic>) {
          output['lengthBucket'] = lengthBucket(value.length);
        } else if (value is Map<dynamic, dynamic>) {
          output['lengthBucket'] = lengthBucket(value.length);
        }
        continue;
      }
      if (value is bool || value is int || value is double) {
        output[entry.key] = value;
      } else if (value is Enum) {
        output[entry.key] = value.name;
      } else if (value is String) {
        output[entry.key] = _safeSemanticString(value);
      } else if (value != null) {
        output[entry.key] = _safeSemanticString(value.toString());
      }
    }
    return output;
  }

  static String lengthBucket(int length) {
    if (length == 0) {
      return '0';
    }
    if (length <= 16) {
      return '1-16';
    }
    if (length <= 64) {
      return '17-64';
    }
    if (length <= 256) {
      return '65-256';
    }
    if (length <= 1024) {
      return '257-1024';
    }
    if (length <= 8192) {
      return '1025-8192';
    }
    return '>8192';
  }

  /// Returns at most the latest 200 log records and at most 64 KiB.
  static String sanitizedMemoryLogs({required String reportSalt}) {
    final List<OutputEvent> logs = memoryOutput.logs.length <= 200
        ? memoryOutput.logs
        : memoryOutput.logs.sublist(memoryOutput.logs.length - 200);
    final List<String> retainedBlocks = <String>[];
    int usedBytes = 0;
    for (final OutputEvent event in logs.reversed) {
      final String block = sanitizeText(
        '[${event.level.name.toUpperCase()}]\n${event.lines.join('\n')}\n',
        reportSalt: reportSalt,
      );
      final int blockBytes = utf8.encode(block).length;
      if (usedBytes + blockBytes > 64 * 1024) {
        break;
      }
      retainedBlocks.add(block);
      usedBytes += blockBytes;
    }
    return retainedBlocks.reversed.join().trim();
  }

  static String _safeSemanticString(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (_email.hasMatch(trimmed) ||
        _url.hasMatch(trimmed) ||
        _ipv4.hasMatch(trimmed) ||
        _ipv6.hasMatch(trimmed) ||
        _mac.hasMatch(trimmed) ||
        _windowsPath.hasMatch(trimmed) ||
        _unixPath.hasMatch(trimmed) ||
        _authorization.hasMatch(trimmed) ||
        _secretAssignment.hasMatch(trimmed) ||
        _sessionAssignment.hasMatch(trimmed) ||
        _longToken.hasMatch(trimmed)) {
      return '<redacted>';
    }
    return trimmed.length <= 160 ? trimmed : trimmed.substring(0, 160);
  }

  static String _stripBalancedSections(
    String input,
    String opening,
    String closing,
  ) {
    final StringBuffer output = StringBuffer();
    int depth = 0;
    for (int i = 0; i < input.length; i++) {
      final String character = input[i];
      if (character == opening) {
        depth++;
        continue;
      }
      if (character == closing && depth > 0) {
        depth--;
        continue;
      }
      if (depth == 0) {
        output.write(character);
      }
    }
    return output.toString();
  }

  static String _saltedHash(String salt, String value) {
    return sha256
        .convert(utf8.encode('$salt\u0000$value'))
        .toString()
        .substring(0, 12);
  }

  static String _hashUnlessMissing(String salt, String value) {
    return value == '-' ? '-' : '<hash:${_saltedHash(salt, value)}>';
  }
}
