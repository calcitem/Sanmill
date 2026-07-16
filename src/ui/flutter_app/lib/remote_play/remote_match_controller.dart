// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'remote_models.dart';

/// Game-specific bridge used by every remote authority model.
///
/// Peer-hosted transports and server-authoritative transports intentionally
/// share this narrow surface so the board never depends on a wire protocol.
abstract interface class RemoteGameAdapter {
  RemoteSeat get activeSeat;

  String get fen;

  Future<void> configure(RemoteMatchConfig config);

  Future<bool> applyAction(String notation);

  Future<void> restoreSnapshot(RemoteStateSnapshot snapshot);

  Future<void> undoActions(int steps);

  Future<void> forceWinner(RemoteSeat winner);

  Future<void> abandon();
}

sealed class RemoteMatchEvent {
  const RemoteMatchEvent();
}

class RemoteMatchStateChanged extends RemoteMatchEvent {
  const RemoteMatchStateChanged(this.state);

  final RemoteConnectionState state;
}

class RemotePeerApprovalRequested extends RemoteMatchEvent {
  const RemotePeerApprovalRequested(this.peer);

  final RemotePeerInfo peer;
}

class RemoteMatchReady extends RemoteMatchEvent {
  const RemoteMatchReady(this.meta, this.config, {required this.resumed});

  final RemoteSessionMeta meta;
  final RemoteMatchConfig config;
  final bool resumed;
}

class RemoteMatchUpgradeRequired extends RemoteMatchEvent {
  const RemoteMatchUpgradeRequired(this.peerVersion);

  final String peerVersion;
}

class RemoteMatchActionRejected extends RemoteMatchEvent {
  const RemoteMatchActionRejected(this.reason);

  /// Stable protocol reason token. Never display this value directly.
  final String reason;
}

class RemoteTakeBackApprovalRequested extends RemoteMatchEvent {
  const RemoteTakeBackApprovalRequested(this.requestId, this.steps);

  final String requestId;
  final int steps;
}

class RemoteRestartApprovalRequested extends RemoteMatchEvent {
  const RemoteRestartApprovalRequested(this.requestId);

  final String requestId;
}

class RemoteOpponentResigned extends RemoteMatchEvent {
  const RemoteOpponentResigned();
}

class RemoteOpponentConnectionChanged extends RemoteMatchEvent {
  const RemoteOpponentConnectionChanged({required this.connected});

  final bool connected;
}

class RemoteOpponentLeft extends RemoteMatchEvent {
  const RemoteOpponentLeft();
}

class RemoteReconnectExhausted extends RemoteMatchEvent {
  const RemoteReconnectExhausted();
}

class RemoteOnlineFailure extends RemoteMatchEvent {
  const RemoteOnlineFailure(this.failure);

  final OnlineFailure failure;
}

class RemoteMatchAborted extends RemoteMatchEvent {
  const RemoteMatchAborted(this.reason);

  final String reason;
}

class RemoteMatchFailure extends RemoteMatchEvent {
  const RemoteMatchFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// Authority-neutral controller consumed by [GameController] and game UI.
///
/// Hosting, discovery, room creation and invitation are deliberately absent:
/// those setup operations belong to the concrete LAN/BLE or cloud flow.
abstract interface class RemoteMatchController {
  ValueListenable<RemoteConnectionState> get stateNotifier;

  Stream<RemoteMatchEvent> get events;

  RemoteConnectionState get state;

  RemoteMatchConfig? get config;

  RemoteSessionMeta? get meta;

  int get revision;

  bool get isConnected;

  bool get isHost;

  bool get isLocalTurn;

  List<String> get actionLog;

  Map<String, Object?> get diagnosticSnapshot;

  Future<bool> submitLocalAction(String notation);

  Future<bool> requestTakeBack(int steps);

  Future<void> respondToTakeBack({
    required String requestId,
    required int steps,
    required bool accepted,
  });

  Future<bool> requestRestart();

  Future<void> respondToRestart({
    required String requestId,
    required bool accepted,
  });

  Future<void> resign();

  Future<void> leave();

  Future<void> retryConnection();

  Future<void> dispose();
}
