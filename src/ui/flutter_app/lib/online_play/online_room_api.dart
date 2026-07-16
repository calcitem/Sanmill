// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../remote_play/remote_models.dart';
import 'online_models.dart';

abstract interface class OnlineRoomApi {
  Future<OnlineRoomSession> createRoom({
    required Map<String, Object?> ruleOptions,
    required OnlineSidePreference sidePreference,
  });

  Future<OnlineRoomSession> joinRoom(OnlineInvite invite);

  Future<String> issueTicket(OnlineRoomSession session);

  Future<void> cancelRoom(OnlineRoomSession session);
}

class OnlineApiException implements Exception {
  const OnlineApiException(this.failure, {this.statusCode});

  final OnlineFailure failure;
  final int? statusCode;

  @override
  String toString() => 'OnlineApiException(${failure.name}, $statusCode)';
}

class HttpOnlineRoomApi implements OnlineRoomApi {
  HttpOnlineRoomApi({
    required this.service,
    required this.definition,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final OnlineServiceConfig service;
  final OnlineGameDefinition definition;
  final Duration requestTimeout;
  final http.Client _client;

  @override
  Future<OnlineRoomSession> createRoom({
    required Map<String, Object?> ruleOptions,
    required OnlineSidePreference sidePreference,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'protocolVersion': onlineProtocolVersion,
      'appId': definition.appId,
      'gameId': definition.gameId,
      'rulesetId': definition.rulesetId,
      'ruleOptions': ruleOptions,
      'sidePreference': sidePreference.name,
    };
    final Map<String, Object?> json = await _requestJson(
      'POST',
      service.resolve('/v1/rooms'),
      body: body,
      expectedStatus: 201,
    );
    return OnlineRoomSession.fromResponse(
      serviceBaseUri: service.baseUri,
      role: RemoteRole.host,
      json: json,
    );
  }

  @override
  Future<OnlineRoomSession> joinRoom(OnlineInvite invite) async {
    final Map<String, Object?> json = await _requestJson(
      'POST',
      service.resolve('/v1/rooms/${invite.roomId}/join'),
      body: <String, Object?>{
        'protocolVersion': onlineProtocolVersion,
        'appId': definition.appId,
        'inviteToken': invite.inviteToken,
        'supportedGames': <String>[definition.gameId],
        'supportedRulesets': <String>[definition.rulesetId],
      },
    );
    return OnlineRoomSession.fromResponse(
      serviceBaseUri: service.baseUri,
      role: RemoteRole.join,
      json: json,
    );
  }

  @override
  Future<String> issueTicket(OnlineRoomSession session) async {
    final Map<String, Object?> json = await _requestJson(
      'POST',
      service.resolve('/v1/rooms/${session.room.roomId}/ticket'),
      bearerToken: session.seatToken,
      body: const <String, Object?>{},
    );
    final Object? ticket = json['ticket'];
    if (ticket is! String || ticket.isEmpty) {
      throw const OnlineApiException(OnlineFailure.protocolError);
    }
    return ticket;
  }

  @override
  Future<void> cancelRoom(OnlineRoomSession session) async {
    await _requestJson(
      'DELETE',
      service.resolve('/v1/rooms/${session.room.roomId}'),
      bearerToken: session.seatToken,
      expectedStatus: 204,
    );
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    String? bearerToken,
    int expectedStatus = 200,
  }) async {
    try {
      final http.Request request = http.Request(method, uri);
      request.headers['accept'] = 'application/json';
      if (bearerToken != null) {
        request.headers['authorization'] = 'Bearer $bearerToken';
      }
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(requestTimeout);
      final String source = await streamed.stream.bytesToString();
      if (streamed.statusCode != expectedStatus) {
        throw OnlineApiException(
          _failureFromResponse(source, streamed.statusCode),
          statusCode: streamed.statusCode,
        );
      }
      if (streamed.statusCode == 204) {
        return const <String, Object?>{};
      }
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const OnlineApiException(OnlineFailure.protocolError);
      }
      return decoded.cast<String, Object?>();
    } on OnlineApiException {
      rethrow;
    } on TimeoutException {
      throw const OnlineApiException(OnlineFailure.serviceUnavailable);
    } on FormatException {
      throw const OnlineApiException(OnlineFailure.protocolError);
    } on Object {
      throw const OnlineApiException(OnlineFailure.serviceUnavailable);
    }
  }

  OnlineFailure _failureFromResponse(String source, int statusCode) {
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is Map && decoded['error'] is String) {
        return switch (decoded['error']) {
          'invalid_invite' || 'invalid_request' => OnlineFailure.invalidInvite,
          'invite_expired' => OnlineFailure.inviteExpired,
          'invite_already_used' => OnlineFailure.inviteAlreadyUsed,
          'room_unavailable' => OnlineFailure.roomUnavailable,
          'room_full' => OnlineFailure.roomFull,
          'version_mismatch' ||
          'invalid_ruleset' => OnlineFailure.versionMismatch,
          'unauthorized' => OnlineFailure.unauthorized,
          'service_unavailable' => OnlineFailure.serviceUnavailable,
          _ => OnlineFailure.protocolError,
        };
      }
    } on FormatException {
      return OnlineFailure.protocolError;
    }
    return statusCode == 429 || statusCode >= 500
        ? OnlineFailure.serviceUnavailable
        : OnlineFailure.protocolError;
  }
}
