// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// recording_models_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/recording_models.dart';

void main() {
  group('RecordingEventType', () {
    test('all values have unique names', () {
      final Set<String> names = RecordingEventType.values
          .map((RecordingEventType e) => e.name)
          .toSet();
      expect(names.length, equals(RecordingEventType.values.length));
    });

    test('includes essential event categories', () {
      expect(
        RecordingEventType.values,
        containsAll(<RecordingEventType>[
          RecordingEventType.boardTap,
          RecordingEventType.aiMove,
          RecordingEventType.settingsChange,
          RecordingEventType.gameReset,
          RecordingEventType.gameModeChange,
          RecordingEventType.gameOver,
          RecordingEventType.historyNavigation,
          RecordingEventType.undoMove,
          RecordingEventType.custom,
        ]),
      );
    });
  });

  group('RecordingEvent', () {
    test('constructor stores all fields', () {
      const RecordingEvent event = RecordingEvent(
        timestampMs: 1234,
        type: RecordingEventType.boardTap,
        data: <String, dynamic>{'sq': 12},
      );

      expect(event.timestampMs, 1234);
      expect(event.type, RecordingEventType.boardTap);
      expect(event.data['sq'], 12);
    });

    test('toJson produces correct map', () {
      const RecordingEvent event = RecordingEvent(
        timestampMs: 500,
        type: RecordingEventType.aiMove,
        data: <String, dynamic>{'move': 'a1', 'side': 'O'},
      );

      final Map<String, dynamic> json = event.toJson();

      expect(json['timestampMs'], 500);
      expect(json['type'], 'aiMove');
      expect(json['data'], isA<Map<String, dynamic>>());
      expect((json['data'] as Map<String, dynamic>)['move'], 'a1');
    });

    test('fromJson round-trip preserves data', () {
      const RecordingEvent original = RecordingEvent(
        timestampMs: 999,
        type: RecordingEventType.settingsChange,
        data: <String, dynamic>{'category': 'general', 'key': 'value'},
      );

      final Map<String, dynamic> json = original.toJson();
      final RecordingEvent restored = RecordingEvent.fromJson(json);

      expect(restored.timestampMs, original.timestampMs);
      expect(restored.type, original.type);
      expect(restored.data['category'], 'general');
      expect(restored.data['key'], 'value');
    });

    test('fromJson handles missing fields gracefully', () {
      final RecordingEvent event = RecordingEvent.fromJson(
        const <String, dynamic>{},
      );

      expect(event.timestampMs, 0);
      expect(event.type, RecordingEventType.custom);
      expect(event.data, isEmpty);
    });

    test('fromJson handles unknown event type', () {
      final RecordingEvent event = RecordingEvent.fromJson(
        const <String, dynamic>{
          'timestampMs': 100,
          'type': 'futureEventType',
          'data': <String, dynamic>{},
        },
      );

      expect(event.type, RecordingEventType.custom);
    });

    test('toString includes type name and timestamp', () {
      const RecordingEvent event = RecordingEvent(
        timestampMs: 42,
        type: RecordingEventType.gameReset,
        data: <String, dynamic>{'force': true},
      );

      final String str = event.toString();
      expect(str, contains('gameReset'));
      expect(str, contains('42'));
    });
  });

  group('RecordingSession', () {
    final DateTime testTime = DateTime(2026, 2, 16, 10, 30);

    RecordingSession makeSession({
      List<RecordingEvent> events = const <RecordingEvent>[],
      String? notes,
      String? gameMode,
    }) {
      return RecordingSession(
        id: 'test-id-1234',
        appVersion: '7.2.6+5423',
        deviceInfo: 'TestDevice (Linux)',
        startTime: testTime,
        durationMs: 60000,
        initialSnapshot: const <String, dynamic>{
          'generalSettings': <String, dynamic>{'skillLevel': 3},
          'ruleSettings': <String, dynamic>{'piecesCount': 9},
        },
        events: events,
        gameMode: gameMode,
        notes: notes,
      );
    }

    test('constructor stores all fields', () {
      final RecordingSession session = makeSession(
        gameMode: 'humanVsAi',
        notes: 'Bug repro',
      );

      expect(session.id, 'test-id-1234');
      expect(session.appVersion, '7.2.6+5423');
      expect(session.deviceInfo, 'TestDevice (Linux)');
      expect(session.startTime, testTime);
      expect(session.durationMs, 60000);
      expect(session.duration, const Duration(seconds: 60));
      expect(session.gameMode, 'humanVsAi');
      expect(session.notes, 'Bug repro');
      expect(session.initialSnapshot, isNotEmpty);
      expect(session.events, isEmpty);
    });

    test('toJson produces valid JSON string', () {
      final RecordingSession session = makeSession(
        events: const <RecordingEvent>[
          RecordingEvent(
            timestampMs: 0,
            type: RecordingEventType.boardTap,
            data: <String, dynamic>{'sq': 8},
          ),
          RecordingEvent(
            timestampMs: 500,
            type: RecordingEventType.aiMove,
            data: <String, dynamic>{'move': 'd5'},
          ),
        ],
        gameMode: 'humanVsAi',
      );

      final Map<String, dynamic> json = session.toJson();

      // Verify it can be encoded to JSON string and back.
      final String encoded = jsonEncode(json);
      expect(encoded, isNotEmpty);

      final Map<String, dynamic> decoded =
          jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['id'], 'test-id-1234');
      expect(decoded['events'], hasLength(2));
    });

    test('fromJson round-trip preserves all fields', () {
      final RecordingSession original = makeSession(
        events: const <RecordingEvent>[
          RecordingEvent(
            timestampMs: 100,
            type: RecordingEventType.gameReset,
            data: <String, dynamic>{'force': true},
          ),
        ],
        gameMode: 'humanVsHuman',
        notes: 'Test notes',
      );

      final String jsonStr = jsonEncode(original.toJson());
      final RecordingSession restored = RecordingSession.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(restored.id, original.id);
      expect(restored.appVersion, original.appVersion);
      expect(restored.deviceInfo, original.deviceInfo);
      expect(
        restored.startTime.toIso8601String(),
        original.startTime.toIso8601String(),
      );
      expect(restored.durationMs, original.durationMs);
      expect(restored.gameMode, original.gameMode);
      expect(restored.notes, original.notes);
      expect(restored.events.length, original.events.length);
      expect(restored.events.first.type, RecordingEventType.gameReset);
      expect(
        restored.initialSnapshot['generalSettings'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('fromJson handles missing optional fields', () {
      final RecordingSession session = RecordingSession.fromJson(
        const <String, dynamic>{
          'id': 'minimal',
          'startTime': '2026-01-01T00:00:00.000',
        },
      );

      expect(session.id, 'minimal');
      expect(session.appVersion, isEmpty);
      expect(session.events, isEmpty);
      expect(session.gameMode, isNull);
      expect(session.notes, isNull);
      expect(session.durationMs, 0);
    });

    test('fromJson handles completely empty map', () {
      final RecordingSession session = RecordingSession.fromJson(
        const <String, dynamic>{},
      );

      expect(session.id, isEmpty);
      expect(session.events, isEmpty);
      expect(session.initialSnapshot, isEmpty);
    });

    test('copyWith replaces selected fields', () {
      final RecordingSession original = makeSession(notes: 'Original');
      final RecordingSession copy = original.copyWith(
        notes: 'Updated',
        durationMs: 120000,
      );

      expect(copy.notes, 'Updated');
      expect(copy.durationMs, 120000);
      // Unchanged fields.
      expect(copy.id, original.id);
      expect(copy.appVersion, original.appVersion);
      expect(copy.events, original.events);
    });

    test('copyWith without arguments returns equivalent session', () {
      final RecordingSession original = makeSession(
        gameMode: 'aiVsAi',
        notes: 'Test',
      );
      final RecordingSession copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.appVersion, original.appVersion);
      expect(copy.durationMs, original.durationMs);
      expect(copy.gameMode, original.gameMode);
      expect(copy.notes, original.notes);
    });

    test('duration getter converts milliseconds correctly', () {
      final RecordingSession session = makeSession();

      expect(session.duration, const Duration(milliseconds: 60000));
      expect(session.duration.inSeconds, 60);
      expect(session.duration.inMinutes, 1);
    });

    test('toString includes id and event count', () {
      final RecordingSession session = makeSession(
        events: const <RecordingEvent>[
          RecordingEvent(
            timestampMs: 0,
            type: RecordingEventType.boardTap,
            data: <String, dynamic>{},
          ),
        ],
      );

      final String str = session.toString();
      expect(str, contains('test-id-1234'));
      expect(str, contains('1 events'));
      expect(str, contains('60s'));
    });

    test('gameMode is included in JSON only when non-null', () {
      final RecordingSession withMode = makeSession(gameMode: 'humanVsAi');
      final RecordingSession withoutMode = makeSession();

      final Map<String, dynamic> jsonWith = withMode.toJson();
      final Map<String, dynamic> jsonWithout = withoutMode.toJson();

      expect(jsonWith.containsKey('gameMode'), isTrue);
      expect(jsonWithout.containsKey('gameMode'), isFalse);
    });

    test('notes is included in JSON only when non-null', () {
      final RecordingSession withNotes = makeSession(notes: 'A note');
      final RecordingSession withoutNotes = makeSession();

      expect(withNotes.toJson().containsKey('notes'), isTrue);
      expect(withoutNotes.toJson().containsKey('notes'), isFalse);
    });

    test('large event list serializes correctly', () {
      final List<RecordingEvent> events = List<RecordingEvent>.generate(
        100,
        (int i) => RecordingEvent(
          timestampMs: i * 100,
          type: RecordingEventType.boardTap,
          data: <String, dynamic>{'sq': 8 + (i % 24)},
        ),
      );

      final RecordingSession session = makeSession(events: events);
      final String jsonStr = jsonEncode(session.toJson());
      final RecordingSession restored = RecordingSession.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(restored.events.length, 100);
      expect(restored.events.first.timestampMs, 0);
      expect(restored.events.last.timestampMs, 9900);
    });
  });
}
