// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// logger.dart

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
import 'environment_config.dart';

class MemoryOutput extends LogOutput {
  MemoryOutput({this.bufferSize = 1000})
    : _buffer = ListQueue<OutputEvent>(bufferSize);

  /// Maximum number of logs to keep in memory.
  /// Reduced from 4000 to 1000 to prevent memory bloat during stress testing.
  final int bufferSize;

  final ListQueue<OutputEvent> _buffer;

  @override
  void output(OutputEvent event) {
    if (_buffer.length >= bufferSize) {
      _buffer.removeFirst();
    }
    _buffer.add(event);
  }

  /// Get all logs in the buffer
  List<OutputEvent> get logs => _buffer.toList();

  /// Clear all logs from the buffer
  void clear() {
    _buffer.clear();
  }
}

final MemoryOutput memoryOutput = MemoryOutput();

/// Maps [EnvironmentConfig.logLevel] to a [Level] understood by package:logger.
///
/// Values follow [EnvironmentConfig.logLevel] documentation:
/// 0=all, 1=trace, 2=debug, 3=info, 4=warning, 5=error, 6=fatal.
Level resolveConfiguredLogLevel(int requested) {
  return switch (requested) {
    0 => Level.all,
    1 => Level.trace,
    2 => Level.debug,
    3 => Level.info,
    4 => Level.warning,
    5 => Level.error,
    6 => Level.fatal,
    _ => Level.all,
  };
}

final Logger logger = Logger(
  filter: ProductionFilter(),
  output: MultiOutput(<LogOutput?>[
    if (kDebugMode) ConsoleOutput(),
    memoryOutput,
  ]),
  level: resolveConfiguredLogLevel(EnvironmentConfig.logLevel),
);

String _formatLogLevelLabel(Level level) {
  return switch (level) {
    Level.trace => 'TRACE',
    Level.debug => 'DEBUG',
    Level.info => 'INFO',
    Level.warning => 'WARN',
    Level.error => 'ERROR',
    Level.fatal => 'FATAL',
    Level.all => 'ALL',
    // ignore: deprecated_member_use
    Level.verbose => 'VERBOSE',
    // ignore: deprecated_member_use
    Level.wtf => 'WTF',
    // ignore: deprecated_member_use
    Level.nothing => 'NOTHING',
    Level.off => 'OFF',
  };
}

/// Formats in-memory logs for download, sharing, or crash-report attachments.
String formatMemoryLogsForExport({DateTime? exportedAt}) {
  final DateTime timestamp = exportedAt ?? DateTime.now();
  final StringBuffer buffer = StringBuffer()
    ..writeln('Sanmill logs - ${timestamp.toIso8601String()}')
    ..writeln('=' * 50)
    ..writeln();

  for (final OutputEvent event in memoryOutput.logs) {
    buffer.writeln('[${_formatLogLevelLabel(event.level)}]');
    event.lines.forEach(buffer.writeln);
    buffer.writeln();
  }

  return buffer.toString();
}

/// Writes the current in-memory log buffer to a temporary file for sharing.
///
/// Returns the file path, or null when the buffer is empty.
Future<String?> exportMemoryLogsToTempFile({DateTime? exportedAt}) async {
  if (memoryOutput.logs.isEmpty) {
    return null;
  }

  final Directory tempDir = await getTemporaryDirectory();
  final DateTime timestamp = exportedAt ?? DateTime.now();
  final String safeTimestamp = timestamp
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final File file = File('${tempDir.path}/sanmill_logs_$safeTimestamp.txt');
  await file.writeAsString(formatMemoryLogsForExport(exportedAt: timestamp));
  return file.path;
}

/// Resolves the on-disk crash log file used by Catcher [FileHandler].
Future<String> resolveCrashLogFilePath() async {
  if (kIsWeb) {
    return './${Constants.crashLogsFile}';
  }

  if (Platform.isIOS ||
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS) {
    return './${Constants.crashLogsFile}';
  }

  try {
    final Directory? externalDir = await getExternalStorageDirectory();
    final String baseDir = externalDir?.path ?? '.';
    return '$baseDir/${Constants.crashLogsFile}';
  } on Object {
    return './${Constants.crashLogsFile}';
  }
}
