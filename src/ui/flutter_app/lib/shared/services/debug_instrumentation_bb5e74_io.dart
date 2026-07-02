// #region agent log
// Temporary debug-session instrumentation (session bb5e74).
// Appends NDJSON lines to a platform-appropriate log file in debug builds.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _sessionId = 'bb5e74';
const String _logFileName = 'debug-bb5e74.log';

/// Used when running from the Windows dev checkout; ignored elsewhere.
const String _windowsDevLogPath = r'D:\Repo\Sanmill\debug-bb5e74.log';

File? _logFile;
Future<File>? _logFileFuture;

void agentDbg(
  String location,
  String message,
  Map<String, Object?> data, {
  String? hypothesisId,
  String runId = 'historyRule',
}) {
  if (!kDebugMode) {
    return;
  }
  unawaited(
    _appendAgentLog(
      location: location,
      message: message,
      data: data,
      hypothesisId: hypothesisId,
      runId: runId,
    ),
  );
}

Future<void> _appendAgentLog({
  required String location,
  required String message,
  required Map<String, Object?> data,
  String? hypothesisId,
  required String runId,
}) async {
  try {
    final File file = _logFile ??= await (_logFileFuture ??= _resolveLogFile());
    final String line = jsonEncode(<String, Object?>{
      'sessionId': _sessionId,
      'runId': runId,
      'hypothesisId': ?hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await file.writeAsString('$line\n', mode: FileMode.append);
  } catch (_) {
    // Instrumentation must never alter app behavior.
  }
}

Future<File> _resolveLogFile() async {
  if (Platform.isWindows) {
    final File devFile = File(_windowsDevLogPath);
    if (devFile.parent.existsSync()) {
      return devFile;
    }
  }

  final Directory dir = await getTemporaryDirectory();
  return File(p.join(dir.path, _logFileName));
}

// #endregion
