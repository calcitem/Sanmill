// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/recording_models.dart';
import 'package:sanmill/experience_recording/models/user_action_event.dart';
import 'package:sanmill/experience_recording/services/diagnostic_reproduction_service.dart';
import 'package:sanmill/shared/models/diagnostic_bundle.dart';

void main() {
  UserActionEventV1 event({
    required int sequence,
    required String actionId,
    required Map<String, Object?> payload,
    UserActionPhase phase = UserActionPhase.success,
    String? correlationId,
  }) {
    return UserActionEventV1.fromJson(<String, dynamic>{
      'sequence': sequence,
      'elapsedMs': sequence * 100,
      'runId': 'run-id',
      'routeId': '/gamePage',
      'actionId': actionId,
      'phase': phase.name,
      'correlationId': correlationId ?? 'correlation-$sequence',
      'payload': payload,
      'stateDigest': <String, String>{'fen': 'fen-$sequence'},
    });
  }

  test(
    'replay planner executes allowlisted actions and skips blocked ones',
    () {
      final DiagnosticBundleV1 bundle = DiagnosticBundleV1(
        bundleId: 'bundle-id',
        createdAtUtc: DateTime.utc(2026),
        application: const <String, dynamic>{
          'version': 'test',
          'platform': 'test',
        },
        kind: DiagnosticReportKind.crash,
        config: const <String, dynamic>{},
        game: const <String, dynamic>{'fen': 'final-fen'},
        actionTrail: DiagnosticActionTrailSnapshot(
          checkpoint: const ActionTrailCheckpoint(
            sequence: 0,
            elapsedMs: 0,
            safeConfig: <String, dynamic>{},
            routeStack: <String>['root:/gamePage'],
            game: <String, dynamic>{
              'fen': 'checkpoint-fen',
              'mode': 'humanVsAi',
            },
          ),
          events: <UserActionEventV1>[
            event(
              sequence: 1,
              actionId: 'game.board.tap',
              payload: const <String, Object?>{'sq': 12},
              phase: UserActionPhase.attempt,
              correlationId: 'board-tap',
            ),
            event(
              sequence: 2,
              actionId: 'game.board.tap',
              payload: const <String, Object?>{'sq': 12},
              correlationId: 'board-tap',
            ),
            event(
              sequence: 3,
              actionId: 'external.operation',
              payload: const <String, Object?>{
                'source': 'file',
                'format': 'moveText',
                'lengthBucket': '17-64',
              },
            ),
            event(
              sequence: 4,
              actionId: 'game.board.tap',
              payload: const <String, Object?>{'sq': 15},
              phase: UserActionPhase.attempt,
              correlationId: 'cancelled-tap',
            ),
            event(
              sequence: 5,
              actionId: 'game.board.tap',
              payload: const <String, Object?>{'sq': 15},
              phase: UserActionPhase.cancel,
              correlationId: 'cancelled-tap',
            ),
          ],
          truncatedEventCount: 0,
          recordedAtUtc: DateTime.utc(2026),
        ),
        sanitizerVersion: '1.0.0',
        missingCapabilities: const <String>[],
      );

      final session = DiagnosticReproductionService().buildReplaySession(
        bundle,
      );

      expect(session.events, hasLength(1));
      expect(session.events.single.data['sq'], 12);
      expect(session.events.single.data['diagnosticSequence'], 1);
      expect(session.events.single.data['expectedFen'], 'fen-2');
    },
  );

  test('replay guard blocks external operations and restores state', () {
    expect(DiagnosticReplayGuard.active, isFalse);

    DiagnosticReplayGuard.enter();
    addTearDown(DiagnosticReplayGuard.exit);

    expect(DiagnosticReplayGuard.active, isTrue);
    expect(
      () => DiagnosticReplayGuard.requireAllowed('network request'),
      throwsStateError,
    );

    DiagnosticReplayGuard.exit();
    expect(DiagnosticReplayGuard.active, isFalse);
  });

  test('replay planner retains allowlisted scalar settings changes', () {
    final DiagnosticBundleV1 bundle = DiagnosticBundleV1(
      bundleId: 'bundle-id',
      createdAtUtc: DateTime.utc(2026),
      application: const <String, dynamic>{
        'version': 'test',
        'platform': 'test',
      },
      kind: DiagnosticReportKind.feedback,
      config: const <String, dynamic>{},
      game: const <String, dynamic>{},
      actionTrail: DiagnosticActionTrailSnapshot(
        checkpoint: const ActionTrailCheckpoint(
          sequence: 0,
          elapsedMs: 0,
          safeConfig: <String, dynamic>{},
          routeStack: <String>['root:/gamePage'],
          game: <String, dynamic>{},
        ),
        events: <UserActionEventV1>[
          event(
            sequence: 1,
            actionId: 'settings.changed',
            payload: const <String, Object?>{
              'category': 'general',
              'settingId': 'AiIsLazy',
              'oldValue': false,
              'newValue': true,
            },
          ),
        ],
        truncatedEventCount: 0,
        recordedAtUtc: DateTime.utc(2026),
      ),
      sanitizerVersion: '1.0.0',
      missingCapabilities: const <String>[],
    );

    final session = DiagnosticReproductionService().buildReplaySession(bundle);

    expect(session.events, hasLength(1));
    expect(session.events.single.type, RecordingEventType.settingsChange);
    expect(session.events.single.data['newValue'], isTrue);
  });
}
