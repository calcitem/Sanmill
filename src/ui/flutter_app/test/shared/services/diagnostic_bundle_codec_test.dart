// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanmill/experience_recording/models/user_action_event.dart';
import 'package:sanmill/shared/models/diagnostic_bundle.dart';
import 'package:sanmill/shared/services/diagnostic_bundle_codec.dart';
import 'package:sanmill/shared/services/diagnostic_report_service.dart';

void main() {
  DiagnosticBundleV1 bundle() {
    return DiagnosticBundleV1(
      bundleId: '01234567-89ab-cdef-0123-456789abcdef',
      createdAtUtc: DateTime.utc(2026, 7, 16),
      application: const <String, dynamic>{
        'applicationId': 'com.calcitem.sanmill',
        'version': '8.0.0',
        'buildNumber': '6707',
        'platform': 'android',
        'channel': 'source',
        'sourceRevision': 'abcdef',
        'sourceUrl': 'https://github.com/calcitem/Sanmill',
        'declaredDistributor': 'Sanmill',
        'signing': <String, dynamic>{
          'kind': 'android-certificate-sha256',
          'status': 'not-observed',
        },
      },
      kind: DiagnosticReportKind.crash,
      errorMessage: 'StateError: example',
      stackTrace: '#0 example',
      config: const <String, dynamic>{
        'generalSettings': <String, dynamic>{},
        'ruleSettings': <String, dynamic>{},
        'displaySettings': <String, dynamic>{},
        'colorSettings': <String, dynamic>{},
        'informationalOnly': <String, dynamic>{},
      },
      game: const <String, dynamic>{
        'fen': 'example-fen',
        'mode': 'humanVsAi',
        'zobrist': '42',
      },
      actionTrail: DiagnosticActionTrailSnapshot(
        checkpoint: null,
        events: const <UserActionEventV1>[],
        truncatedEventCount: 0,
        recordedAtUtc: DateTime.utc(2026, 7, 16),
      ),
      logs: 'safe log',
      sanitizerVersion: '1.0.0',
      missingCapabilities: const <String>['no checkpoint'],
    );
  }

  test('round trip preserves bundle and application id', () {
    final String encoded = DiagnosticBundleCodec.encode(bundle());
    final DiagnosticBundleV1 decoded = DiagnosticBundleCodec.decode(encoded);

    expect(encoded, startsWith(diagnosticBundleBegin));
    expect(encoded, endsWith(diagnosticBundleEnd));
    expect(decoded.bundleId, bundle().bundleId);
    expect(decoded.application['applicationId'], 'com.calcitem.sanmill');
    expect(decoded.game['fen'], 'example-fen');
  });

  test('tampering is rejected by the SHA-256 checksum', () {
    final String encoded = DiagnosticBundleCodec.encode(
      bundle(),
    ).replaceFirst('example-fen', 'tampered-fen');

    expect(
      () => DiagnosticBundleCodec.decode(encoded),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts JSON-escaped and GlitchTip embedded text', () {
    final String encoded = DiagnosticBundleCodec.encode(bundle());
    final String escaped = jsonEncode(encoded);
    final String eventJson = jsonEncode(<String, dynamic>{
      'extra': <String, dynamic>{'sanmillDiagnosticBundle': encoded},
    });

    expect(DiagnosticBundleCodec.decode(escaped).bundleId, bundle().bundleId);
    expect(DiagnosticBundleCodec.decode(eventJson).bundleId, bundle().bundleId);
  });

  test('rejects unsafe fields inside a replay checkpoint', () {
    final DiagnosticBundleV1 unsafe = DiagnosticBundleV1(
      bundleId: bundle().bundleId,
      createdAtUtc: bundle().createdAtUtc,
      application: bundle().application,
      kind: bundle().kind,
      config: bundle().config,
      game: bundle().game,
      actionTrail: DiagnosticActionTrailSnapshot(
        checkpoint: const ActionTrailCheckpoint(
          sequence: 0,
          elapsedMs: 0,
          safeConfig: <String, dynamic>{
            'generalSettings': <String, dynamic>{},
            'ruleSettings': <String, dynamic>{},
            'displaySettings': <String, dynamic>{},
            'colorSettings': <String, dynamic>{},
            'informationalOnly': <String, dynamic>{},
          },
          routeStack: <String>['root:/gamePage'],
          game: <String, dynamic>{
            'fen': 'example-fen',
            'privatePlayerName': 'must-not-enter-a-bundle',
          },
        ),
        events: const <UserActionEventV1>[],
        truncatedEventCount: 0,
        recordedAtUtc: DateTime.utc(2026, 7, 16),
      ),
      sanitizerVersion: '1.0.0',
      missingCapabilities: const <String>[],
    );

    expect(
      () => DiagnosticBundleCodec.decode(DiagnosticBundleCodec.encode(unsafe)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an excessively large wrapper before JSON traversal', () {
    expect(
      () => DiagnosticBundleCodec.decode('x' * (2 * 1024 * 1024 + 1)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects oversized feedback after checksum validation', () {
    final DiagnosticBundleV1 oversized = DiagnosticBundleV1(
      bundleId: bundle().bundleId,
      createdAtUtc: bundle().createdAtUtc,
      application: bundle().application,
      kind: DiagnosticReportKind.feedback,
      feedbackText: List<String>.filled(20 * 1024, 'x').join(),
      config: bundle().config,
      game: bundle().game,
      actionTrail: bundle().actionTrail,
      sanitizerVersion: '1.0.0',
      missingCapabilities: const <String>[],
    );

    final DiagnosticBundleV1 decoded = DiagnosticBundleCodec.decode(
      DiagnosticBundleCodec.encode(oversized),
    );
    expect(utf8.encode(decoded.feedbackText!).length, 8 * 1024);
    expect(
      decoded.missingCapabilities,
      contains('feedback text truncated to 8 KiB'),
    );
  });

  test('oversized logs discard oldest complete lines with a marker', () {
    final String padding = List<String>.filled(20, 'x').join();
    final String logs = <String>[
      for (int i = 0; i < 5000; i++) 'log-$i $padding',
    ].join('\n');
    final DiagnosticBundleV1 oversized = DiagnosticBundleV1(
      bundleId: bundle().bundleId,
      createdAtUtc: bundle().createdAtUtc,
      application: bundle().application,
      kind: bundle().kind,
      config: bundle().config,
      game: bundle().game,
      actionTrail: bundle().actionTrail,
      logs: logs,
      sanitizerVersion: '1.0.0',
      missingCapabilities: const <String>[],
    );

    final DiagnosticBundleV1 decoded = DiagnosticBundleCodec.decode(
      DiagnosticBundleCodec.encode(oversized),
    );

    expect(decoded.logs, startsWith('[... oldest logs truncated ...]\n'));
    expect(decoded.logs, endsWith('log-4999 $padding'));
    expect(utf8.encode(decoded.logs!).length, lessThanOrEqualTo(64 * 1024));
    expect(
      decoded.missingCapabilities,
      contains('oldest logs truncated to 64 KiB'),
    );
  });

  test('GlitchTip transport sends exact bundle once without retry', () async {
    final String encoded = DiagnosticBundleCodec.encode(bundle());
    int requestCount = 0;
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      requestCount++;
      captured = request;
      return http.Response('unavailable', 503);
    });

    await expectLater(
      GlitchTipDiagnosticTransport.send(
        dsn: 'https://public-key@errors.example/42',
        bundleText: encoded,
        bundle: bundle(),
        client: client,
      ),
      throwsA(isA<HttpException>()),
    );

    expect(requestCount, 1);
    expect(captured.url.path, '/api/42/envelope/');
    final Map<String, dynamic> event =
        jsonDecode(captured.body.split('\n')[2]) as Map<String, dynamic>;
    expect(
      (event['extra'] as Map<String, dynamic>)['sanmillDiagnosticBundle'],
      encoded,
    );
    expect(
      (event['tags'] as Map<String, dynamic>)['application_id'],
      'com.calcitem.sanmill',
    );
  });
}
