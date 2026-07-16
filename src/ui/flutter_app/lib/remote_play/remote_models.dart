// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:meta/meta.dart';

/// The physical link used by a remote Sanmill match.
enum RemoteTransportKind { lan, bluetooth, cloud }

enum RemoteRole { host, join }

enum RemoteSeat { first, second }

/// Transport and match lifecycle states shared by LAN and Bluetooth.
enum RemoteConnectionState {
  idle,
  listening,
  scanning,
  connecting,
  awaitingApproval,
  negotiating,
  ready,
  reconnecting,
  ended,
  error,
}

/// Stable online-service failures mapped to localized UI copy.
///
/// Raw HTTP bodies and exception strings must never cross into widgets.
enum OnlineFailure {
  invalidInvite,
  inviteExpired,
  inviteAlreadyUsed,
  roomUnavailable,
  roomFull,
  versionMismatch,
  serviceUnavailable,
  unauthorized,
  protocolError,
}

@immutable
class RemotePeerInfo {
  const RemotePeerInfo({
    required this.peerId,
    required this.label,
    required this.platform,
    required this.appVersion,
    required this.appBuild,
  });

  factory RemotePeerInfo.fromJson(Map<String, Object?> json) {
    return RemotePeerInfo(
      peerId: _requiredString(json, 'peerId'),
      label: _requiredString(json, 'label'),
      platform: _requiredString(json, 'platform'),
      appVersion: _requiredString(json, 'appVersion'),
      appBuild: _requiredString(json, 'appBuild'),
    );
  }

  final String peerId;
  final String label;
  final String platform;
  final String appVersion;
  final String appBuild;

  String get shortId => peerId.length <= 8 ? peerId : peerId.substring(0, 8);

  Map<String, Object?> toJson() => <String, Object?>{
    'peerId': peerId,
    'label': label,
    'platform': platform,
    'appVersion': appVersion,
    'appBuild': appBuild,
  };
}

/// Immutable ownership information attached to the active game session.
@immutable
class RemoteSessionMeta {
  const RemoteSessionMeta({
    required this.transportKind,
    required this.role,
    required this.localSeat,
    required this.hostPlaysFirst,
    required this.sessionId,
  });

  final RemoteTransportKind transportKind;
  final RemoteRole role;
  final RemoteSeat localSeat;
  final bool hostPlaysFirst;
  final String sessionId;

  bool get isHost => role == RemoteRole.host;

  bool get isOpponentSeatFirst => localSeat == RemoteSeat.second;
}

/// Host-authored configuration for one remote round.
@immutable
class RemoteMatchConfig {
  const RemoteMatchConfig({
    required this.sessionId,
    required this.roundId,
    required this.ruleSchemaVersion,
    required this.ruleSettings,
    required this.initialFen,
    required this.hostPlaysFirst,
    this.clockEnabled = false,
  });

  factory RemoteMatchConfig.fromJson(Map<String, Object?> json) {
    final Object? rawRules = json['ruleSettings'];
    if (rawRules is! Map) {
      throw const FormatException('ruleSettings must be an object.');
    }
    return RemoteMatchConfig(
      sessionId: _requiredString(json, 'sessionId'),
      roundId: _requiredString(json, 'roundId'),
      ruleSchemaVersion: _requiredInt(json, 'ruleSchemaVersion'),
      ruleSettings: rawRules.map<String, Object?>(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>(key! as String, value),
      ),
      initialFen: _requiredString(json, 'initialFen'),
      hostPlaysFirst: _requiredBool(json, 'hostPlaysFirst'),
      clockEnabled: json['clockEnabled'] == true,
    );
  }

  final String sessionId;
  final String roundId;
  final int ruleSchemaVersion;
  final Map<String, Object?> ruleSettings;
  final String initialFen;
  final bool hostPlaysFirst;
  final bool clockEnabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'roundId': roundId,
    'ruleSchemaVersion': ruleSchemaVersion,
    'ruleSettings': ruleSettings,
    'initialFen': initialFen,
    'hostPlaysFirst': hostPlaysFirst,
    'clockEnabled': clockEnabled,
  };
}

@immutable
class RemoteStateSnapshot {
  const RemoteStateSnapshot({
    required this.revision,
    required this.initialFen,
    required this.actions,
    required this.resultFen,
  });

  factory RemoteStateSnapshot.fromJson(Map<String, Object?> json) {
    final Object? rawActions = json['actions'];
    if (rawActions is! List || rawActions.any((Object? e) => e is! String)) {
      throw const FormatException('actions must be a string array.');
    }
    return RemoteStateSnapshot(
      revision: _requiredInt(json, 'revision'),
      initialFen: _requiredString(json, 'initialFen'),
      actions: rawActions.cast<String>(),
      resultFen: _requiredString(json, 'resultFen'),
    );
  }

  final int revision;
  final String initialFen;
  final List<String> actions;
  final String resultFen;

  Map<String, Object?> toJson() => <String, Object?>{
    'revision': revision,
    'initialFen': initialFen,
    'actions': actions,
    'resultFen': resultFen,
  };
}

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

bool _requiredBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}
