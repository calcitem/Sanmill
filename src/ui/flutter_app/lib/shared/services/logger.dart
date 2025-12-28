// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// logger.dart

import 'dart:collection';

import 'package:logger/logger.dart';

import 'environment_config.dart';

class MemoryOutput extends LogOutput {
  MemoryOutput({this.bufferSize = 4000})
    : _buffer = ListQueue<OutputEvent>(bufferSize);

  /// Maximum number of logs to keep in memory
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
}

final MemoryOutput memoryOutput = MemoryOutput();

int _clampLogLevel(int requested) {
  if (requested < 0) {
    return 0;
  }
  if (requested >= Level.values.length) {
    return Level.values.length - 1;
  }
  return requested;
}

final Logger logger = Logger(
  output: MultiOutput(<LogOutput?>[ConsoleOutput(), memoryOutput]),
  level: Level.values[_clampLogLevel(EnvironmentConfig.logLevel)],
);
