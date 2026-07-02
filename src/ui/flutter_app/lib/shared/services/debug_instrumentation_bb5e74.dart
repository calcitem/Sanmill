// #region agent log
// Temporary debug-session instrumentation (session bb5e74).
// Appends NDJSON lines to the debug log; remove after the fix is verified.

import 'dart:convert';
import 'dart:io';

void agentDbg(
  String location,
  String message,
  Map<String, Object?> data, {
  String? hypothesisId,
  String runId = 'historyRule',
}) {
  try {
    File('D:/Repo/Sanmill/debug-bb5e74.log').writeAsStringSync(
      '${jsonEncode(<String, Object?>{'sessionId': 'bb5e74', 'runId': runId, if (hypothesisId != null) 'hypothesisId': hypothesisId, 'location': location, 'message': message, 'data': data, 'timestamp': DateTime.now().millisecondsSinceEpoch})}\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // Instrumentation must never alter app behavior.
  }
}

// #endregion
