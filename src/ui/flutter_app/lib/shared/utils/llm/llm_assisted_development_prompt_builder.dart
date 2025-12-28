// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// llm_assisted_development_prompt_builder.dart

/// Utilities for building a developer-oriented prompt to be pasted into an LLM.
library;

/// Returns true if the provided text looks like Sanmill app logs.
///
/// Heuristics:
/// - Contains `package:sanmill` (Flutter stack traces / logs)
/// - Contains `info score` (engine evaluation logs)
bool looksLikeSanmillLog(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  final String lower = trimmed.toLowerCase();
  return lower.contains('package:sanmill') || lower.contains('info score');
}

/// Extracts a log snippet from clipboard text if it looks like a log.
String? extractSanmillLog(String clipboardText) {
  final String trimmed = clipboardText.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (!looksLikeSanmillLog(trimmed)) {
    return null;
  }
  return trimmed;
}

const String _promptHeader = '''
You are an expert in the Mill board game (e.g., Nine Men’s Morris variants) and a senior engineer specializing in Flutter, Dart, and C++. You are rigorous, detail-oriented, and you think through edge cases. You generalize from examples and prioritize maintainability, extensibility, readability, and minimal, well-scoped diffs.

Here is the task:
''';

String _promptFooter({required String languageName}) {
  final String lang = languageName.trim();
  assert(lang.isNotEmpty);

  return '''
If the task involves adding new UI strings, only update the `en` and `zh` ARB files unless explicitly requested. Other language ARB files do not need to be modified.
Your answer must be in $lang, but code comments must be in English. Git commit messages must also be in English, and trailers must not include `Co-authored-by`.
Only modify code; do not generate a documentation summary. If existing documentation must be updated, you may update it.
''';
}

/// Builds a developer-oriented LLM prompt.
///
/// The output format is:
/// - Fixed English header
/// - User task text
/// - Fixed English footer (with the `<language>` placeholder replaced by
///   [languageName])
/// - Optional log section wrapped in Markdown code fences if [log] is provided
String buildLlmAssistedDevelopmentPrompt({
  required String task,
  required String languageName,
  String? log,
}) {
  final String trimmedTask = task.trim();
  assert(trimmedTask.isNotEmpty);

  final StringBuffer buffer = StringBuffer()
    ..write(_promptHeader)
    ..writeln()
    ..writeln(trimmedTask)
    ..writeln()
    ..write(_promptFooter(languageName: languageName).trimRight());

  final String? trimmedLog = (log == null) ? null : log.trim();
  if (trimmedLog != null && trimmedLog.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln()
      ..writeln('Here are the relevant logs for your reference:')
      ..writeln()
      ..writeln('```')
      ..writeln(trimmedLog)
      ..writeln('```');
  }

  return buffer.toString();
}
