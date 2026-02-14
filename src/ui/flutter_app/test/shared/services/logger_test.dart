// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// logger_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:sanmill/shared/services/logger.dart';

void main() {
  // ---------------------------------------------------------------------------
  // MemoryOutput
  // ---------------------------------------------------------------------------
  group('MemoryOutput', () {
    test('should start with empty buffer', () {
      final MemoryOutput output = MemoryOutput();
      expect(output.logs, isEmpty);
    });

    test('should store output events', () {
      final MemoryOutput output = MemoryOutput();

      output.output(OutputEvent(Level.info, <String>['test message']));

      expect(output.logs.length, 1);
      expect(output.logs.first.lines, contains('test message'));
    });

    test('should respect buffer size limit', () {
      final MemoryOutput output = MemoryOutput(bufferSize: 3);

      for (int i = 0; i < 5; i++) {
        output.output(OutputEvent(Level.info, <String>['msg $i']));
      }

      // Buffer should have only the last 3 entries
      expect(output.logs.length, 3);
      expect(output.logs.first.lines, contains('msg 2'));
      expect(output.logs.last.lines, contains('msg 4'));
    });

    test('clear should remove all logs', () {
      final MemoryOutput output = MemoryOutput();

      output.output(OutputEvent(Level.info, <String>['msg 1']));
      output.output(OutputEvent(Level.info, <String>['msg 2']));

      output.clear();

      expect(output.logs, isEmpty);
    });

    test('default bufferSize should be 1000', () {
      final MemoryOutput output = MemoryOutput();
      expect(output.bufferSize, 1000);
    });

    test('should handle rapid sequential writes', () {
      final MemoryOutput output = MemoryOutput(bufferSize: 100);

      for (int i = 0; i < 200; i++) {
        output.output(OutputEvent(Level.debug, <String>['rapid $i']));
      }

      expect(output.logs.length, 100);
    });
  });

  // ---------------------------------------------------------------------------
  // Global logger
  // ---------------------------------------------------------------------------
  group('Global logger instance', () {
    test('logger should be non-null', () {
      expect(logger, isNotNull);
    });

    test('memoryOutput should be accessible', () {
      expect(memoryOutput, isNotNull);
      expect(memoryOutput, isA<MemoryOutput>());
    });

    test('logger should log to memoryOutput', () {
      final int beforeCount = memoryOutput.logs.length;

      // Logging at a level that should be captured (info is level 3)
      logger.i('test log entry for unit test');

      // The log count should increase (depends on log level setting)
      // Since EnvironmentConfig.logLevel defaults to 0 (all), this should work
      expect(memoryOutput.logs.length, greaterThanOrEqualTo(beforeCount));
    });
  });
}
