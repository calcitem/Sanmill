// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanmill/online_play/online_models.dart';
import 'package:sanmill/online_play/online_room_api.dart';
import 'package:sanmill/remote_play/remote_models.dart';

void main() {
  test('distinguishes capacity from a cloud service fault', () async {
    expect(
      await _createFailure(
        _responseClient(429, '{"error":"service_unavailable"}'),
      ),
      OnlineFailure.serviceAtCapacity,
    );
    expect(
      await _createFailure(
        _responseClient(503, '{"error":"capacity_reached"}'),
      ),
      OnlineFailure.serviceAtCapacity,
    );
    expect(
      await _createFailure(
        _responseClient(503, '{"error":"service_unavailable"}'),
      ),
      OnlineFailure.serviceUnavailable,
    );
    expect(
      await _createFailure(_responseClient(500, '<html>failure</html>')),
      OnlineFailure.serviceUnavailable,
    );
  });

  test('keeps authorization and protocol failures distinct', () async {
    expect(
      await _createFailure(_responseClient(401, '{"error":"unauthorized"}')),
      OnlineFailure.unauthorized,
    );
    expect(
      await _createFailure(_responseClient(418, '<html>unexpected</html>')),
      OnlineFailure.protocolError,
    );
  });

  test('maps client and timeout exceptions to connection failure', () async {
    final MockClient disconnected = MockClient(
      (http.Request request) => Future<http.Response>.error(
        http.ClientException('offline', request.url),
      ),
    );
    expect(await _createFailure(disconnected), OnlineFailure.connectionFailed);

    final MockClient stalled = MockClient(
      (http.Request request) => Completer<http.Response>().future,
    );
    expect(
      await _createFailure(
        stalled,
        requestTimeout: const Duration(milliseconds: 1),
      ),
      OnlineFailure.connectionFailed,
    );
  });
}

MockClient _responseClient(int statusCode, String body) => MockClient(
  (http.Request request) async => http.Response(
    body,
    statusCode,
    headers: <String, String>{'content-type': 'application/json'},
    request: request,
  ),
);

Future<OnlineFailure> _createFailure(
  http.Client client, {
  Duration requestTimeout = const Duration(seconds: 1),
}) async {
  final HttpOnlineRoomApi api = HttpOnlineRoomApi(
    service: OnlineServiceConfig(Uri.parse('https://online.example')),
    definition: onlineMillGameDefinition,
    client: client,
    requestTimeout: requestTimeout,
  );
  try {
    await api.createRoom(
      ruleOptions: const <String, Object?>{},
      sidePreference: OnlineSidePreference.first,
      eloRating: 1400,
    );
  } on OnlineApiException catch (error) {
    return error.failure;
  }
  throw StateError('Expected the online request to fail.');
}
