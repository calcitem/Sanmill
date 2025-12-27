// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.dart

import 'package:logger/logger.dart';

import 'environment_config.dart';
import 'in_app_log_buffer.dart';

int _clampLogLevel(int requested) {
  if (requested < 0) {
    return 0;
  }
  if (requested >= Level.values.length) {
    return Level.values.length - 1;
  }
  return requested;
}

class _InAppLogOutput extends LogOutput {
  _InAppLogOutput({required this.delegate});

  final LogOutput delegate;

  @override
  void output(OutputEvent event) {
    for (final String line in event.lines) {
      InAppLogBuffer.instance.addLine(event.level, line);
    }
    delegate.output(event);
  }
}

final Logger logger = Logger(
  level: Level.values[_clampLogLevel(EnvironmentConfig.logLevel)],
  output: _InAppLogOutput(delegate: ConsoleOutput()),
);
