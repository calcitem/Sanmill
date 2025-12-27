// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// In-memory log ring buffer for on-device diagnostics.
///
/// This is intentionally lightweight:
/// - Stores formatted log lines only (as shown in console output).
/// - Keeps a bounded number of lines (ring buffer).
/// - Exposes a revision notifier for efficient UI updates.
class InAppLogBuffer {
  InAppLogBuffer._();

  static final InAppLogBuffer instance = InAppLogBuffer._();

  /// Maximum number of log lines kept in memory.
  ///
  /// Keep this bounded to avoid unbounded memory growth on long sessions.
  static const int maxLines = 2000;

  /// Incremented whenever the buffer content changes.
  ///
  /// The UI can listen to this and rebuild by reading [linesSnapshot].
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final ListQueue<InAppLogLine> _lines = ListQueue<InAppLogLine>();

  void addLine(Level level, String message) {
    if (message.isEmpty) {
      return;
    }

    _lines.add(
      InAppLogLine(time: DateTime.now(), level: level, message: message),
    );

    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }

    revision.value++;
  }

  void clear() {
    if (_lines.isEmpty) {
      return;
    }
    _lines.clear();
    revision.value++;
  }

  /// Returns an immutable snapshot of the current buffered lines.
  List<InAppLogLine> get linesSnapshot =>
      List<InAppLogLine>.unmodifiable(_lines);

  /// Export logs as plain text suitable for copying to clipboard.
  String exportText({String? contains}) {
    final String? query = (contains == null || contains.trim().isEmpty)
        ? null
        : contains.trim();

    final StringBuffer buffer = StringBuffer();
    for (final InAppLogLine line in _lines) {
      if (query != null && !line.message.contains(query)) {
        continue;
      }
      buffer
        ..write(line.time.toIso8601String())
        ..write(' ')
        ..write(_levelToShortName(line.level))
        ..write(' ')
        ..writeln(line.message);
    }
    return buffer.toString().trimRight();
  }

  static String _levelToShortName(Level level) {
    switch (level) {
      case Level.trace:
        return '[T]';
      // ignore: deprecated_member_use
      case Level.verbose:
        return '[V]';
      case Level.debug:
        return '[D]';
      case Level.info:
        return '[I]';
      case Level.warning:
        return '[W]';
      case Level.error:
        return '[E]';
      // ignore: deprecated_member_use
      case Level.wtf:
        return '[WTF]';
      case Level.fatal:
        return '[F]';
      case Level.all:
        return '[A]';
      case Level.off:
        return '[O]';
      // ignore: deprecated_member_use
      case Level.nothing:
        return '[ ]';
    }
  }
}

@immutable
class InAppLogLine {
  const InAppLogLine({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final Level level;
  final String message;
}
