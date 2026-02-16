// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_service_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/recording_models.dart';
import 'package:sanmill/experience_recording/services/recording_service.dart';

void main() {
  group('RecordingService', () {
    test('singleton returns same instance', () {
      final RecordingService a = RecordingService();
      final RecordingService b = RecordingService();
      expect(identical(a, b), isTrue);
    });

    test('isRecording is false initially', () {
      expect(RecordingService().isRecording, isFalse);
    });

    test('isSuppressed is false initially', () {
      expect(RecordingService().isSuppressed, isFalse);
    });

    test('eventCountNotifier starts at zero', () {
      expect(RecordingService().eventCountNotifier.value, 0);
    });

    test('recordEvent is no-op when not recording', () {
      final RecordingService service = RecordingService();
      // Should not throw.
      service.recordEvent(RecordingEventType.boardTap, <String, dynamic>{
        'sq': 10,
      });
      // Event count stays at zero because recording is not active.
      expect(service.eventCountNotifier.value, 0);
    });

    test('recordEvent is no-op when suppressed', () {
      final RecordingService service = RecordingService();
      service.isSuppressed = true;
      service.recordEvent(RecordingEventType.boardTap, <String, dynamic>{
        'sq': 10,
      });
      expect(service.eventCountNotifier.value, 0);
      service.isSuppressed = false;
    });

    test('stopRecording returns null when not recording', () async {
      final RecordingSession? session = await RecordingService()
          .stopRecording();
      expect(session, isNull);
    });

    test('maxEventsPerSession is positive', () {
      expect(RecordingService.maxEventsPerSession, greaterThan(0));
    });

    test('maxSessionFiles is positive', () {
      expect(RecordingService.maxSessionFiles, greaterThan(0));
    });

    test('maxTotalStorageBytes is positive', () {
      expect(RecordingService.maxTotalStorageBytes, greaterThan(0));
    });

    test('flushInterval is positive duration', () {
      expect(RecordingService.flushInterval.inMilliseconds, greaterThan(0));
    });
  });

  group('RecordingService.importSessionFromJsonString', () {
    test('returns null for empty string', () async {
      final RecordingSession? result =
          await RecordingService().importSessionFromJsonString('');
      expect(result, isNull);
    });

    test('returns null for invalid JSON', () async {
      final RecordingSession? result =
          await RecordingService().importSessionFromJsonString('not json');
      expect(result, isNull);
    });

    test('returns null for JSON array instead of object', () async {
      final RecordingSession? result =
          await RecordingService().importSessionFromJsonString('[1, 2, 3]');
      expect(result, isNull);
    });

    test('returns null for session with empty id', () async {
      final String json = jsonEncode(<String, dynamic>{
        'id': '',
        'appVersion': '1.0',
        'deviceInfo': 'test',
        'startTime': DateTime.now().toIso8601String(),
        'durationMs': 100,
        'initialSnapshot': <String, dynamic>{},
        'events': <dynamic>[],
      });
      final RecordingSession? result =
          await RecordingService().importSessionFromJsonString(json);
      expect(result, isNull);
    });
  });

  group('RecordingService.importSessionFromFile', () {
    test('returns null for non-existent file', () async {
      final RecordingSession? result = await RecordingService()
          .importSessionFromFile('/non/existent/path.json');
      expect(result, isNull);
    });
  });
}
