// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import '../remote_play/remote_models.dart';
import '../rule_settings/models/rule_settings.dart';

const int onlineProtocolVersion = 1;
const String onlineAppId = 'sanmill';
const String onlineMillGameId = 'mill';
const String onlineMillRulesetId = 'custom-v1';

enum OnlineSidePreference { first, second, random }

@immutable
class OnlineServiceConfig {
  const OnlineServiceConfig(this.baseUri);

  factory OnlineServiceConfig.fromEnvironment() {
    const String source = String.fromEnvironment('SANMILL_ONLINE_BASE_URL');
    final Uri? uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'SANMILL_ONLINE_BASE_URL must be an HTTPS origin.',
      );
    }
    return OnlineServiceConfig(uri.replace(path: ''));
  }

  final Uri baseUri;

  Uri resolve(String path) => baseUri.resolve(path);
}

@immutable
class OnlineInvite {
  const OnlineInvite({
    required this.roomId,
    required this.inviteToken,
    required this.uri,
  });

  static final RegExp _roomPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static OnlineInvite? tryParse(String source, OnlineServiceConfig service) {
    final Uri? uri = Uri.tryParse(source.trim());
    if (uri == null || uri.query.isNotEmpty) {
      return null;
    }
    final bool isHttpsInvite =
        uri.scheme == service.baseUri.scheme &&
        uri.host == service.baseUri.host &&
        uri.port == service.baseUri.port &&
        uri.userInfo.isEmpty &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'invite';
    final bool isAppInvite =
        uri.scheme == 'sanmill' &&
        uri.host == 'invite' &&
        uri.pathSegments.length == 1;
    if (!isHttpsInvite && !isAppInvite) {
      return null;
    }
    final String roomId = isHttpsInvite
        ? uri.pathSegments[1]
        : uri.pathSegments.first;
    if (!_roomPattern.hasMatch(roomId) ||
        !_tokenPattern.hasMatch(uri.fragment)) {
      return null;
    }
    return OnlineInvite(roomId: roomId, inviteToken: uri.fragment, uri: uri);
  }

  final String roomId;
  final String inviteToken;
  final Uri uri;
}

@immutable
class OnlineRoomDescriptor {
  const OnlineRoomDescriptor({
    required this.roomId,
    required this.appId,
    required this.gameId,
    required this.rulesetId,
    required this.ruleOptions,
    required this.creatorSeat,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.endReason,
    this.winnerSeat,
  });

  factory OnlineRoomDescriptor.fromJson(Map<String, Object?> json) {
    final Object? rawOptions = json['ruleOptions'];
    if (rawOptions is! Map) {
      throw const FormatException('room.ruleOptions must be an object.');
    }
    return OnlineRoomDescriptor(
      roomId: _requiredString(json, 'roomId'),
      appId: _requiredString(json, 'appId'),
      gameId: _requiredString(json, 'gameId'),
      rulesetId: _requiredString(json, 'rulesetId'),
      ruleOptions: rawOptions.cast<String, Object?>(),
      creatorSeat: _seat(json['creatorSeat']),
      status: _requiredString(json, 'status'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _requiredInt(json, 'createdAt'),
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        _requiredInt(json, 'expiresAt'),
        isUtc: true,
      ),
      endReason: json['endReason'] as String?,
      winnerSeat: json['winnerSeat'] == null ? null : _seat(json['winnerSeat']),
    );
  }

  final String roomId;
  final String appId;
  final String gameId;
  final String rulesetId;
  final Map<String, Object?> ruleOptions;
  final RemoteSeat creatorSeat;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? endReason;
  final RemoteSeat? winnerSeat;

  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';

  OnlineRoomDescriptor copyWith({String? status}) {
    return OnlineRoomDescriptor(
      roomId: roomId,
      appId: appId,
      gameId: gameId,
      rulesetId: rulesetId,
      ruleOptions: ruleOptions,
      creatorSeat: creatorSeat,
      status: status ?? this.status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      endReason: endReason,
      winnerSeat: winnerSeat,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'roomId': roomId,
    'appId': appId,
    'gameId': gameId,
    'rulesetId': rulesetId,
    'ruleOptions': ruleOptions,
    'creatorSeat': creatorSeat.name,
    'status': status,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    if (endReason != null) 'endReason': endReason,
    if (winnerSeat != null) 'winnerSeat': winnerSeat!.name,
  };
}

@immutable
class OnlineRoomSession {
  const OnlineRoomSession({
    required this.serviceBaseUri,
    required this.room,
    required this.role,
    required this.localSeat,
    required this.seatToken,
    required this.snapshot,
    this.inviteUri,
  });

  factory OnlineRoomSession.fromResponse({
    required Uri serviceBaseUri,
    required RemoteRole role,
    required Map<String, Object?> json,
  }) {
    final Object? rawRoom = json['room'];
    final Object? rawSnapshot = json['snapshot'];
    if (rawRoom is! Map || rawSnapshot is! Map) {
      throw const FormatException('Room response is incomplete.');
    }
    final String? inviteSource = json['inviteUrl'] as String?;
    return OnlineRoomSession(
      serviceBaseUri: serviceBaseUri,
      room: OnlineRoomDescriptor.fromJson(rawRoom.cast<String, Object?>()),
      role: role,
      localSeat: _seat(json['seat']),
      seatToken: _requiredString(json, 'seatToken'),
      snapshot: RemoteStateSnapshot.fromJson(
        rawSnapshot.cast<String, Object?>(),
      ),
      inviteUri: inviteSource == null ? null : Uri.tryParse(inviteSource),
    );
  }

  factory OnlineRoomSession.fromJson(Map<String, Object?> json) {
    final Object? rawRoom = json['room'];
    final Object? rawSnapshot = json['snapshot'];
    if (rawRoom is! Map || rawSnapshot is! Map) {
      throw const FormatException('Stored room session is incomplete.');
    }
    final String? inviteSource = json['inviteUri'] as String?;
    return OnlineRoomSession(
      serviceBaseUri: Uri.parse(_requiredString(json, 'serviceBaseUri')),
      room: OnlineRoomDescriptor.fromJson(rawRoom.cast<String, Object?>()),
      role: RemoteRole.values.byName(_requiredString(json, 'role')),
      localSeat: _seat(json['localSeat']),
      seatToken: _requiredString(json, 'seatToken'),
      snapshot: RemoteStateSnapshot.fromJson(
        rawSnapshot.cast<String, Object?>(),
      ),
      inviteUri: inviteSource == null ? null : Uri.tryParse(inviteSource),
    );
  }

  final Uri serviceBaseUri;
  final OnlineRoomDescriptor room;
  final RemoteRole role;
  final RemoteSeat localSeat;
  final String seatToken;
  final RemoteStateSnapshot snapshot;
  final Uri? inviteUri;

  OnlineRoomSession copyWith({
    OnlineRoomDescriptor? room,
    RemoteStateSnapshot? snapshot,
    bool clearInvite = false,
  }) {
    return OnlineRoomSession(
      serviceBaseUri: serviceBaseUri,
      room: room ?? this.room,
      role: role,
      localSeat: localSeat,
      seatToken: seatToken,
      snapshot: snapshot ?? this.snapshot,
      inviteUri: clearInvite ? null : inviteUri,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'serviceBaseUri': serviceBaseUri.toString(),
    'room': room.toJson(),
    'role': role.name,
    'localSeat': localSeat.name,
    'seatToken': seatToken,
    'snapshot': snapshot.toJson(),
    if (inviteUri != null) 'inviteUri': inviteUri.toString(),
  };
}

Map<String, Object?> onlineOptionsFromRuleSettings(RuleSettings rules) {
  Map<String, Object?> capture({
    required bool enabled,
    required bool square,
    required bool cross,
    required bool diagonal,
    required bool placing,
    required bool moving,
    required bool onlyLeq3,
  }) => <String, Object?>{
    'enabled': enabled,
    'onSquareEdges': square,
    'onCrossLines': cross,
    'onDiagonalLines': diagonal,
    'inPlacingPhase': placing,
    'inMovingPhase': moving,
    'onlyAvailableWhenOwnPiecesLeq3': onlyLeq3,
  };

  return <String, Object?>{
    'pieceCount': rules.piecesCount,
    'flyPieceCount': rules.flyPieceCount,
    'piecesAtLeastCount': rules.piecesAtLeastCount,
    'mayFly': rules.mayFly,
    'hasDiagonalLines': rules.hasDiagonalLines,
    'millFormationActionInPlacingPhase':
        (rules.millFormationActionInPlacingPhase ??
                MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard)
            .name,
    'mayRemoveFromMillsAlways': rules.mayRemoveFromMillsAlways,
    'mayRemoveMultiple': rules.mayRemoveMultiple,
    'nMoveRule': rules.nMoveRule,
    'endgameNMoveRule': rules.endgameNMoveRule,
    'mayMoveInPlacingPhase': rules.mayMoveInPlacingPhase,
    'isDefenderMoveFirst': rules.isDefenderMoveFirst,
    'restrictRepeatedMillsFormation': rules.restrictRepeatedMillsFormation,
    'oneTimeUseMill': rules.oneTimeUseMill,
    'stopPlacingWhenTwoEmptySquares': rules.stopPlacingWhenTwoEmptySquares,
    'boardFullAction':
        (rules.boardFullAction ?? BoardFullAction.firstPlayerLose).name,
    'threefoldRepetitionRule': rules.threefoldRepetitionRule,
    'custodianCapture': capture(
      enabled: rules.enableCustodianCapture,
      square: rules.custodianCaptureOnSquareEdges,
      cross: rules.custodianCaptureOnCrossLines,
      diagonal: rules.custodianCaptureOnDiagonalLines,
      placing: rules.custodianCaptureInPlacingPhase,
      moving: rules.custodianCaptureInMovingPhase,
      onlyLeq3: rules.custodianCaptureOnlyWhenOwnPiecesLeq3,
    ),
    'interventionCapture': capture(
      enabled: rules.enableInterventionCapture,
      square: rules.interventionCaptureOnSquareEdges,
      cross: rules.interventionCaptureOnCrossLines,
      diagonal: rules.interventionCaptureOnDiagonalLines,
      placing: rules.interventionCaptureInPlacingPhase,
      moving: rules.interventionCaptureInMovingPhase,
      onlyLeq3: rules.interventionCaptureOnlyWhenOwnPiecesLeq3,
    ),
    'leapCapture': capture(
      enabled: rules.enableLeapCapture,
      square: rules.leapCaptureOnSquareEdges,
      cross: rules.leapCaptureOnCrossLines,
      diagonal: rules.leapCaptureOnDiagonalLines,
      placing: rules.leapCaptureInPlacingPhase,
      moving: rules.leapCaptureInMovingPhase,
      onlyLeq3: rules.leapCaptureOnlyWhenOwnPiecesLeq3,
    ),
    'stalemateAction':
        (rules.stalemateAction ?? StalemateAction.endWithStalemateLoss).name,
  };
}

RuleSettings ruleSettingsFromOnlineOptions(Map<String, Object?> options) {
  Map<String, Object?> capture(String key) {
    final Object? value = options[key];
    if (value is! Map) {
      throw FormatException('$key must be an object.');
    }
    return value.cast<String, Object?>();
  }

  final Map<String, Object?> custodian = capture('custodianCapture');
  final Map<String, Object?> intervention = capture('interventionCapture');
  final Map<String, Object?> leap = capture('leapCapture');
  return RuleSettings(
    piecesCount: _optionInt(options, 'pieceCount'),
    flyPieceCount: _optionInt(options, 'flyPieceCount'),
    piecesAtLeastCount: _optionInt(options, 'piecesAtLeastCount'),
    mayFly: _optionBool(options, 'mayFly'),
    hasDiagonalLines: _optionBool(options, 'hasDiagonalLines'),
    millFormationActionInPlacingPhase: MillFormationActionInPlacingPhase.values
        .byName(_requiredString(options, 'millFormationActionInPlacingPhase')),
    mayRemoveFromMillsAlways: _optionBool(options, 'mayRemoveFromMillsAlways'),
    mayRemoveMultiple: _optionBool(options, 'mayRemoveMultiple'),
    nMoveRule: _optionInt(options, 'nMoveRule'),
    endgameNMoveRule: _optionInt(options, 'endgameNMoveRule'),
    mayMoveInPlacingPhase: _optionBool(options, 'mayMoveInPlacingPhase'),
    isDefenderMoveFirst: _optionBool(options, 'isDefenderMoveFirst'),
    restrictRepeatedMillsFormation: _optionBool(
      options,
      'restrictRepeatedMillsFormation',
    ),
    oneTimeUseMill: _optionBool(options, 'oneTimeUseMill'),
    stopPlacingWhenTwoEmptySquares: _optionBool(
      options,
      'stopPlacingWhenTwoEmptySquares',
    ),
    boardFullAction: BoardFullAction.values.byName(
      _requiredString(options, 'boardFullAction'),
    ),
    threefoldRepetitionRule: _optionBool(options, 'threefoldRepetitionRule'),
    enableCustodianCapture: _optionBool(custodian, 'enabled'),
    custodianCaptureOnSquareEdges: _optionBool(custodian, 'onSquareEdges'),
    custodianCaptureOnCrossLines: _optionBool(custodian, 'onCrossLines'),
    custodianCaptureOnDiagonalLines: _optionBool(custodian, 'onDiagonalLines'),
    custodianCaptureInPlacingPhase: _optionBool(custodian, 'inPlacingPhase'),
    custodianCaptureInMovingPhase: _optionBool(custodian, 'inMovingPhase'),
    custodianCaptureOnlyWhenOwnPiecesLeq3: _optionBool(
      custodian,
      'onlyAvailableWhenOwnPiecesLeq3',
    ),
    enableInterventionCapture: _optionBool(intervention, 'enabled'),
    interventionCaptureOnSquareEdges: _optionBool(
      intervention,
      'onSquareEdges',
    ),
    interventionCaptureOnCrossLines: _optionBool(intervention, 'onCrossLines'),
    interventionCaptureOnDiagonalLines: _optionBool(
      intervention,
      'onDiagonalLines',
    ),
    interventionCaptureInPlacingPhase: _optionBool(
      intervention,
      'inPlacingPhase',
    ),
    interventionCaptureInMovingPhase: _optionBool(
      intervention,
      'inMovingPhase',
    ),
    interventionCaptureOnlyWhenOwnPiecesLeq3: _optionBool(
      intervention,
      'onlyAvailableWhenOwnPiecesLeq3',
    ),
    enableLeapCapture: _optionBool(leap, 'enabled'),
    leapCaptureOnSquareEdges: _optionBool(leap, 'onSquareEdges'),
    leapCaptureOnCrossLines: _optionBool(leap, 'onCrossLines'),
    leapCaptureOnDiagonalLines: _optionBool(leap, 'onDiagonalLines'),
    leapCaptureInPlacingPhase: _optionBool(leap, 'inPlacingPhase'),
    leapCaptureInMovingPhase: _optionBool(leap, 'inMovingPhase'),
    leapCaptureOnlyWhenOwnPiecesLeq3: _optionBool(
      leap,
      'onlyAvailableWhenOwnPiecesLeq3',
    ),
    stalemateAction: StalemateAction.values.byName(
      _requiredString(options, 'stalemateAction'),
    ),
  );
}

abstract interface class OnlineGameDefinition {
  String get appId;

  String get gameId;

  String get rulesetId;

  RemoteMatchConfig remoteConfigFor(OnlineRoomSession session);
}

class MillOnlineGameDefinition implements OnlineGameDefinition {
  const MillOnlineGameDefinition();

  @override
  String get appId => onlineAppId;

  @override
  String get gameId => onlineMillGameId;

  @override
  String get rulesetId => onlineMillRulesetId;

  @override
  RemoteMatchConfig remoteConfigFor(OnlineRoomSession session) {
    final RuleSettings settings = ruleSettingsFromOnlineOptions(
      session.room.ruleOptions,
    );
    return RemoteMatchConfig(
      sessionId: session.room.roomId,
      roundId: '${session.room.roomId}:1',
      ruleSchemaVersion: onlineProtocolVersion,
      ruleSettings: Map<String, Object?>.from(settings.toJson()),
      initialFen: session.snapshot.initialFen,
      hostPlaysFirst: session.room.creatorSeat == RemoteSeat.first,
    );
  }
}

const OnlineGameDefinition onlineMillGameDefinition =
    MillOnlineGameDefinition();

RemoteSeat _seat(Object? value) => switch (value) {
  'first' => RemoteSeat.first,
  'second' => RemoteSeat.second,
  _ => throw const FormatException('Invalid player seat.'),
};

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer.');
  }
  return value;
}

int _optionInt(Map<String, Object?> json, String key) =>
    _requiredInt(json, key);

bool _optionBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}
