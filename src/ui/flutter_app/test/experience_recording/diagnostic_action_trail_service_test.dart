// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/experience_recording/models/user_action_event.dart';
import 'package:sanmill/experience_recording/services/diagnostic_action_trail_service.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('external events reject unknown and wrongly typed fields', () {
    Map<String, dynamic> eventJson(Map<String, dynamic> payload) =>
        <String, dynamic>{
          'sequence': 1,
          'elapsedMs': 10,
          'runId': 'run-id',
          'routeId': '/gamePage',
          'actionId': 'game.board.tap',
          'phase': 'success',
          'correlationId': 'correlation-id',
          'payload': payload,
          'stateDigest': <String, String>{},
        };

    expect(
      () => UserActionEventV1.fromJson(
        eventJson(<String, dynamic>{'sq': 1, 'rawText': 'secret'}),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserActionEventV1.fromJson(
        eventJson(<String, dynamic>{'sq': 'not-an-integer'}),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('settings events preserve only JSON scalar values', () {
    final Map<String, Object?> payload =
        UserActionCatalog.require('settings.changed').validateExternal(
          <String, dynamic>{
            'category': 'general',
            'settingId': 'AiIsLazy',
            'oldValue': false,
            'newValue': true,
          },
        );

    expect(payload['oldValue'], isFalse);
    expect(payload['newValue'], isTrue);
    expect(
      () => UserActionCatalog.require('settings.changed').validateExternal(
        <String, dynamic>{
          'category': 'general',
          'settingId': 'AiIsLazy',
          'newValue': <String, dynamic>{'unsafe': true},
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('ring buffer enforces count/byte caps and marks truncation', () async {
    final Database? previous = Database.instance;
    Database.instance = MockDB();
    addTearDown(() => Database.instance = previous);
    final DiagnosticActionTrailService service = DiagnosticActionTrailService();
    await service.initialize();
    addTearDown(() => service.setEnabled(false));
    await service.clear();

    for (int i = 0; i < DiagnosticActionTrailService.maxEvents + 50; i++) {
      service.record(
        actionId: 'game.board.tap',
        phase: UserActionPhase.success,
        payload: <String, dynamic>{'sq': i % 24},
      );
    }

    final DiagnosticActionTrailSnapshot snapshot = service.freeze();
    expect(snapshot.events.length, lessThanOrEqualTo(500));
    expect(snapshot.truncatedEventCount, greaterThan(0));
    expect(
      service.retainedBytes,
      lessThanOrEqualTo(DiagnosticActionTrailService.maxEncodedBytes),
    );
    for (int i = 1; i < snapshot.events.length; i++) {
      expect(
        snapshot.events[i].sequence,
        greaterThan(snapshot.events[i - 1].sequence),
      );
    }
  });

  test('disabling clears retained events immediately', () async {
    final Database? previous = Database.instance;
    Database.instance = MockDB();
    addTearDown(() => Database.instance = previous);
    final DiagnosticActionTrailService service = DiagnosticActionTrailService();
    await service.initialize();
    await service.setEnabled(true);
    addTearDown(() => service.setEnabled(false));
    service.record(
      actionId: 'game.board.tap',
      phase: UserActionPhase.success,
      payload: const <String, dynamic>{'sq': 1},
    );
    expect(service.eventCount, greaterThan(0));

    await service.setEnabled(false);

    expect(service.eventCount, 0);
    expect(service.freeze().events, isEmpty);
  });
}
