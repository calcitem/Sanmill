// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/user_action_event.dart';

void main() {
  UserActionEventV1 event({int sequence = 1}) {
    return UserActionEventV1(
      sequence: sequence,
      elapsedMs: sequence * 10,
      runId: 'run-id',
      routeId: '/gamePage',
      actionId: 'game.board.tap',
      phase: UserActionPhase.success,
      correlationId: 'correlation-$sequence',
      payload: const <String, Object?>{'sq': 12},
      stateDigest: const <String, String>{
        'fen': 'fen-value',
        'zobrist': '123',
        'route': '/gamePage',
        'config': 'abcd',
      },
    );
  }

  group('UserActionEventV1', () {
    test('strict round trip preserves registered fields', () {
      final UserActionEventV1 restored = UserActionEventV1.fromJson(
        event().toJson(),
      );

      expect(restored.sequence, 1);
      expect(restored.payload, <String, Object?>{'sq': 12});
      expect(restored.replayPolicy, UserActionReplayPolicy.replayable);
    });

    test('rejects unknown actions', () {
      final Map<String, dynamic> json = event().toJson()
        ..['actionId'] = 'unregistered.action';

      expect(
        () => UserActionEventV1.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown payload fields', () {
      final Map<String, dynamic> json = event().toJson();
      json['payload'] = <String, dynamic>{'sq': 12, 'rawText': 'secret'};

      expect(
        () => UserActionEventV1.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects incorrect payload types', () {
      final Map<String, dynamic> json = event().toJson();
      json['payload'] = <String, dynamic>{'sq': 'twelve'};

      expect(
        () => UserActionEventV1.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown event envelope fields', () {
      final Map<String, dynamic> json = event().toJson()
        ..['futureField'] = true;

      expect(
        () => UserActionEventV1.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DiagnosticActionTrailSnapshot', () {
    test('requires strictly increasing sequence numbers', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'checkpoint': null,
        'events': <Map<String, dynamic>>[
          event(sequence: 2).toJson(),
          event(sequence: 1).toJson(),
        ],
        'truncatedEventCount': 0,
        'recordedAtUtc': DateTime.utc(2026).toIso8601String(),
      };

      expect(
        () => DiagnosticActionTrailSnapshot.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a typed checkpoint and ordered events', () {
      final DiagnosticActionTrailSnapshot snapshot =
          DiagnosticActionTrailSnapshot.fromJson(<String, dynamic>{
            'checkpoint': <String, dynamic>{
              'sequence': 0,
              'elapsedMs': 0,
              'safeConfig': <String, dynamic>{},
              'routeStack': <String>['root:/gamePage'],
              'game': <String, dynamic>{'fen': 'fen-value'},
            },
            'events': <Map<String, dynamic>>[
              event().toJson(),
              event(sequence: 2).toJson(),
            ],
            'truncatedEventCount': 3,
            'recordedAtUtc': DateTime.utc(2026).toIso8601String(),
          });

      expect(snapshot.events, hasLength(2));
      expect(snapshot.truncatedEventCount, 3);
      expect(snapshot.checkpoint?.routeStack, <String>['root:/gamePage']);
    });

    test('rejects events from more than one run', () {
      final Map<String, dynamic> second = event(sequence: 2).toJson()
        ..['runId'] = 'another-run';
      final Map<String, dynamic> json = <String, dynamic>{
        'checkpoint': null,
        'events': <Map<String, dynamic>>[event().toJson(), second],
        'truncatedEventCount': 0,
        'recordedAtUtc': DateTime.utc(2026).toIso8601String(),
      };

      expect(
        () => DiagnosticActionTrailSnapshot.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a checkpoint that does not precede retained events', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'checkpoint': <String, dynamic>{
          'sequence': 1,
          'elapsedMs': 10,
          'safeConfig': <String, dynamic>{},
          'routeStack': <String>['root:/gamePage'],
          'game': <String, dynamic>{},
        },
        'events': <Map<String, dynamic>>[event().toJson()],
        'truncatedEventCount': 0,
        'recordedAtUtc': DateTime.utc(2026).toIso8601String(),
      };

      expect(
        () => DiagnosticActionTrailSnapshot.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
