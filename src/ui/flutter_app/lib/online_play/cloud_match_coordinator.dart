// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../remote_play/remote_match_controller.dart';
import '../remote_play/remote_models.dart';
import 'online_models.dart';
import 'online_room_api.dart';
import 'online_session_store.dart';
import 'online_socket_client.dart';

class CloudMatchCoordinator implements RemoteMatchController {
  CloudMatchCoordinator({
    required this.definition,
    required OnlineRoomSession session,
    required this.roomApi,
    required this.socket,
    required this.game,
    required this.sessionStore,
    this.reconnectWindow = const Duration(seconds: 60),
    this.commandTimeout = const Duration(seconds: 20),
    this.controlTimeout = const Duration(seconds: 40),
    this.welcomeTimeout = const Duration(seconds: 12),
  }) : _session = session,
       _revision = session.snapshot.revision,
       _actionLog = List<String>.of(session.snapshot.actions) {
    _socketSubscription = socket.events.listen(_onSocketEvent);
  }

  static const Uuid _uuid = Uuid();

  final OnlineRoomApi roomApi;
  final OnlineGameDefinition definition;
  final OnlineSocketClient socket;
  final RemoteGameAdapter game;
  final OnlineSessionStore sessionStore;
  final Duration reconnectWindow;
  final Duration commandTimeout;
  final Duration controlTimeout;
  final Duration welcomeTimeout;

  @override
  final ValueNotifier<RemoteConnectionState> stateNotifier =
      ValueNotifier<RemoteConnectionState>(RemoteConnectionState.idle);
  final StreamController<RemoteMatchEvent> _events =
      StreamController<RemoteMatchEvent>.broadcast(sync: true);
  final Map<String, _PendingCommand> _pendingCommands =
      <String, _PendingCommand>{};
  final Map<String, Completer<bool>> _pendingControls =
      <String, Completer<bool>>{};

  late final StreamSubscription<OnlineSocketEvent> _socketSubscription;
  OnlineRoomSession _session;
  RemoteMatchConfig? _config;
  RemoteSessionMeta? _meta;
  late List<String> _actionLog;
  Future<void> _inboundSerial = Future<void>.value();
  Completer<void>? _welcomeCompleter;
  int _revision;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _everWelcomed = false;
  bool _reconnectLoopRunning = false;
  bool _ending = false;
  String? _lastInboundControlRequestId;

  OnlineRoomSession get roomSession => _session;

  @override
  Stream<RemoteMatchEvent> get events => _events.stream;

  @override
  RemoteConnectionState get state => stateNotifier.value;

  @override
  RemoteMatchConfig? get config => _config;

  @override
  RemoteSessionMeta? get meta => _meta;

  @override
  int get revision => _revision;

  @override
  bool get isConnected => state == RemoteConnectionState.ready;

  @override
  bool get isHost => _session.role == RemoteRole.host;

  @override
  bool get isLocalTurn =>
      isConnected && _meta != null && game.activeSeat == _meta!.localSeat;

  @override
  List<String> get actionLog => List<String>.unmodifiable(_actionLog);

  @override
  Map<String, Object?> get diagnosticSnapshot => <String, Object?>{
    'transport': RemoteTransportKind.cloud.name,
    'role': _session.role.name,
    'state': state.name,
    'room': _shortId(_session.room.roomId),
    'revision': _revision,
    'reconnectAttempts': _reconnectAttempts,
    'pendingCommands': _pendingCommands.length,
    'expiresAt': _session.room.expiresAt.toIso8601String(),
  };

  Future<void> start() async {
    _assertUsable();
    _installConfiguration();
    await game.configure(_config!);
    await game.restoreSnapshot(_session.snapshot);
    await sessionStore.write(_session);
    _setState(RemoteConnectionState.connecting);
    try {
      await _connectAndAwaitWelcome();
    } on OnlineApiException catch (error) {
      if (isTerminalOnlineFailure(error.failure)) {
        await _handleTerminalApiFailure(error.failure);
      } else {
        _events.add(RemoteOnlineFailure(error.failure));
        _setState(RemoteConnectionState.error);
      }
      rethrow;
    } on Object catch (error, stackTrace) {
      _events.add(
        RemoteMatchFailure(_sanitizedDiagnosticError(error), stackTrace),
      );
      _events.add(const RemoteOnlineFailure(OnlineFailure.serviceUnavailable));
      _setState(RemoteConnectionState.error);
      throw const OnlineApiException(OnlineFailure.serviceUnavailable);
    }
  }

  void _installConfiguration() {
    final RemoteMatchConfig nextConfig = definition.remoteConfigFor(_session);
    _config = nextConfig;
    _meta = RemoteSessionMeta(
      transportKind: RemoteTransportKind.cloud,
      role: _session.role,
      localSeat: _session.localSeat,
      hostPlaysFirst: nextConfig.hostPlaysFirst,
      sessionId: _session.room.roomId,
    );
  }

  Future<void> _connectAndAwaitWelcome() async {
    _assertUsable();
    final String ticket = await roomApi.issueTicket(_session);
    final Uri base = _session.serviceBaseUri;
    final Uri socketUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/rooms/${_session.room.roomId}/socket',
      queryParameters: <String, String>{'ticket': ticket},
      fragment: '',
    );
    final Completer<void> welcome = Completer<void>();
    _welcomeCompleter = welcome;
    await socket.connect(socketUri);
    await welcome.future.timeout(welcomeTimeout);
  }

  void _onSocketEvent(OnlineSocketEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case OnlineSocketMessage():
        _inboundSerial = _inboundSerial
            .then((_) => _handleMessage(event.json))
            .catchError((Object error, StackTrace stackTrace) {
              _events.add(
                RemoteMatchFailure(
                  _sanitizedDiagnosticError(error),
                  stackTrace,
                ),
              );
              _events.add(
                const RemoteOnlineFailure(OnlineFailure.protocolError),
              );
            });
      case OnlineSocketClosed():
        _handleSocketLoss();
      case OnlineSocketError():
        _events.add(
          RemoteMatchFailure(
            _sanitizedDiagnosticError(event.error),
            event.stackTrace,
          ),
        );
        _handleSocketLoss();
    }
  }

  Future<void> _handleMessage(Map<String, Object?> message) async {
    final String type = _requiredString(message, 'type');
    switch (type) {
      case 'welcome':
        await _handleWelcome(message);
      case 'state':
        await _applyStateMessage(message);
      case 'opponentJoined':
        await _applyStateMessage(message);
        final bool connected = message['connected'] == true;
        if (!connected) {
          _setState(RemoteConnectionState.listening);
        }
        _events.add(RemoteOpponentConnectionChanged(connected: connected));
      case 'error':
        await _handleErrorMessage(message);
      case 'controlRequest':
        _revision = _requiredInt(message, 'seq');
        _emitControlRequest(message);
      case 'controlResult':
        await _applyStateMessage(message);
        final String requestId = _requiredString(message, 'requestId');
        if (_lastInboundControlRequestId == requestId) {
          _lastInboundControlRequestId = null;
        }
        _pendingControls
            .remove(requestId)
            ?.complete(message['accepted'] == true);
      case 'opponentResigned':
        _revision = _requiredInt(message, 'seq');
        await game.forceWinner(_session.localSeat);
        _ending = true;
        _setState(RemoteConnectionState.ended);
        await sessionStore.delete();
        _events.add(const RemoteOpponentResigned());
      case 'opponentLeft':
        _revision = _requiredInt(message, 'seq');
        await game.abandon();
        _ending = true;
        _setState(RemoteConnectionState.ended);
        await sessionStore.delete();
        _events.add(const RemoteOpponentLeft());
      case 'opponentConnection':
        _revision = _requiredInt(message, 'seq');
        final bool connected = message['connected'] == true;
        if (_session.room.isActive) {
          _setState(
            connected
                ? RemoteConnectionState.ready
                : RemoteConnectionState.listening,
          );
        }
        _events.add(RemoteOpponentConnectionChanged(connected: connected));
      default:
        throw FormatException('Unknown online event type: $type');
    }
  }

  Future<void> _handleWelcome(Map<String, Object?> message) async {
    final Object? rawRoom = message['room'];
    if (rawRoom is! Map) {
      throw const FormatException('Welcome message has no room descriptor.');
    }
    final OnlineRoomDescriptor room = OnlineRoomDescriptor.fromJson(
      rawRoom.cast<String, Object?>(),
    );
    if (room.roomId != _session.room.roomId ||
        room.appId != definition.appId ||
        room.gameId != definition.gameId ||
        room.rulesetId != definition.rulesetId) {
      throw const FormatException('Welcome room does not match credentials.');
    }
    _session = _session.copyWith(room: room);
    _installConfiguration();
    await game.configure(_config!);
    await _applyStateMessage(message, emitReady: false);
    final bool resumed = _everWelcomed;
    _everWelcomed = true;
    _reconnectAttempts = 0;
    if (room.isEnded) {
      if (room.endReason == 'resign' && room.winnerSeat != null) {
        await game.forceWinner(room.winnerSeat!);
        if (room.winnerSeat == _session.localSeat) {
          _events.add(const RemoteOpponentResigned());
        }
      } else if (room.endReason == 'left') {
        await game.abandon();
        _events.add(const RemoteOpponentLeft());
      }
      _ending = true;
      _setState(RemoteConnectionState.ended);
      await sessionStore.delete();
    } else if (room.isActive) {
      _setState(
        message['opponentConnected'] == true
            ? RemoteConnectionState.ready
            : RemoteConnectionState.listening,
      );
      _events.add(RemoteMatchReady(_meta!, _config!, resumed: resumed));
    } else {
      _setState(RemoteConnectionState.listening);
    }
    for (final _PendingCommand pending in _pendingCommands.values) {
      socket.send(pending.message);
    }
    final Completer<void>? welcome = _welcomeCompleter;
    _welcomeCompleter = null;
    if (welcome != null && !welcome.isCompleted) {
      welcome.complete();
    }
  }

  Future<void> _applyStateMessage(
    Map<String, Object?> message, {
    bool emitReady = true,
    bool completeCommand = true,
  }) async {
    final Object? rawSnapshot = message['snapshot'];
    if (rawSnapshot is! Map) {
      throw const FormatException('State event has no snapshot.');
    }
    final RemoteStateSnapshot snapshot = RemoteStateSnapshot.fromJson(
      rawSnapshot.cast<String, Object?>(),
    );
    if (snapshot.revision < _revision) {
      return;
    }
    await game.restoreSnapshot(snapshot);
    _revision = snapshot.revision;
    _actionLog = List<String>.of(snapshot.actions);
    final String? status = message['status'] as String?;
    if (status != null) {
      _session = _session.copyWith(
        room: _session.room.copyWith(status: status),
        snapshot: snapshot,
      );
    } else {
      _session = _session.copyWith(snapshot: snapshot);
    }
    if (_session.room.isEnded) {
      _ending = true;
      _setState(RemoteConnectionState.ended);
      await sessionStore.delete();
    } else {
      await sessionStore.write(_session);
      if (_session.room.isActive && state != RemoteConnectionState.ready) {
        _setState(RemoteConnectionState.ready);
        if (emitReady) {
          _events.add(RemoteMatchReady(_meta!, _config!, resumed: false));
        }
      }
    }
    _restorePendingControl(message);
    final String? commandId = message['commandId'] as String?;
    if (completeCommand && commandId != null) {
      _completeCommand(commandId, true);
    }
  }

  void _restorePendingControl(Map<String, Object?> message) {
    if (!message.containsKey('pendingControl')) {
      return;
    }
    final Object? rawPending = message['pendingControl'];
    if (rawPending == null) {
      _lastInboundControlRequestId = null;
      return;
    }
    if (rawPending is! Map) {
      throw const FormatException('pendingControl must be an object.');
    }
    final Map<String, Object?> pending = rawPending.cast<String, Object?>();
    if (_requiredString(pending, 'requester') == _session.localSeat.name) {
      return;
    }
    _emitControlRequest(pending);
  }

  void _emitControlRequest(Map<String, Object?> message) {
    final String requestId = _requiredString(message, 'requestId');
    if (_lastInboundControlRequestId == requestId) {
      return;
    }
    _lastInboundControlRequestId = requestId;
    switch (_requiredString(message, 'kind')) {
      case 'takeBack':
        _events.add(
          RemoteTakeBackApprovalRequested(
            requestId,
            _requiredInt(message, 'steps'),
          ),
        );
      case 'restart':
        _events.add(RemoteRestartApprovalRequested(requestId));
      default:
        throw const FormatException('Unknown control request kind.');
    }
  }

  Future<void> _handleErrorMessage(Map<String, Object?> message) async {
    final Object? rawSnapshot = message['snapshot'];
    if (rawSnapshot is Map) {
      await _applyStateMessage(<String, Object?>{
        ...message,
        'type': 'state',
        'status': _session.room.status,
      }, completeCommand: false);
    }
    final String code = _requiredString(message, 'error');
    final String? commandId = message['commandId'] as String?;
    if (commandId != null) {
      _completeCommand(commandId, false);
    }
    if (code == 'action_rejected' || code == 'stale_revision') {
      _events.add(RemoteMatchActionRejected(code));
      return;
    }
    final OnlineFailure failure = onlineFailureForCode(code);
    _events.add(RemoteOnlineFailure(failure));
    if (failure == OnlineFailure.roomUnavailable ||
        failure == OnlineFailure.inviteExpired ||
        failure == OnlineFailure.unauthorized) {
      await _handleTerminalApiFailure(failure);
    }
  }

  void _handleSocketLoss() {
    final Completer<void>? welcome = _welcomeCompleter;
    _welcomeCompleter = null;
    if (welcome != null && !welcome.isCompleted) {
      welcome.completeError(StateError('Socket closed before welcome.'));
    }
    if (_disposed || _ending || state == RemoteConnectionState.ended) {
      return;
    }
    if (!_everWelcomed) {
      return;
    }
    _setState(RemoteConnectionState.reconnecting);
    unawaited(_runReconnectLoop());
  }

  Future<void> _runReconnectLoop() async {
    if (_reconnectLoopRunning || _disposed || _ending) {
      return;
    }
    _reconnectLoopRunning = true;
    final DateTime deadline = DateTime.now().add(reconnectWindow);
    try {
      while (!_disposed && !_ending && DateTime.now().isBefore(deadline)) {
        _reconnectAttempts += 1;
        try {
          await _connectAndAwaitWelcome();
          return;
        } on OnlineApiException catch (error) {
          if (isTerminalOnlineFailure(error.failure)) {
            await _handleTerminalApiFailure(error.failure);
            return;
          }
        } on Object {
          // The next bounded retry obtains a fresh one-time ticket.
        }
        final int seconds = _reconnectAttempts.clamp(1, 5);
        await Future<void>.delayed(Duration(seconds: seconds));
      }
      if (!_disposed && !_ending) {
        _setState(RemoteConnectionState.error);
        _events.add(const RemoteReconnectExhausted());
      }
    } finally {
      _reconnectLoopRunning = false;
    }
  }

  @override
  Future<void> retryConnection() async {
    _assertUsable();
    if (isConnected || _reconnectLoopRunning) {
      return;
    }
    _setState(RemoteConnectionState.reconnecting);
    await _runReconnectLoop();
  }

  @override
  Future<bool> submitLocalAction(String notation) {
    if (!isLocalTurn || notation.isEmpty) {
      return Future<bool>.value(false);
    }
    return _sendCommand('action', <String, Object?>{'action': notation});
  }

  @override
  Future<bool> requestTakeBack(int steps) async {
    if (!isConnected || steps <= 0) {
      return false;
    }
    final String requestId = _uuid.v4();
    final Completer<bool> result = Completer<bool>();
    _pendingControls[requestId] = result;
    final bool sent = await _sendCommand('takeBackRequest', <String, Object?>{
      'steps': steps,
    }, commandId: requestId);
    if (!sent) {
      _pendingControls.remove(requestId);
      return false;
    }
    return result.future.timeout(
      controlTimeout,
      onTimeout: () {
        _pendingControls.remove(requestId);
        return false;
      },
    );
  }

  @override
  Future<void> respondToTakeBack({
    required String requestId,
    required int steps,
    required bool accepted,
  }) async {
    await _sendCommand('takeBackResponse', <String, Object?>{
      'requestId': requestId,
      'accepted': accepted,
      'steps': steps,
    });
  }

  @override
  Future<bool> requestRestart() async {
    if (!isConnected) {
      return false;
    }
    final String requestId = _uuid.v4();
    final Completer<bool> result = Completer<bool>();
    _pendingControls[requestId] = result;
    final bool sent = await _sendCommand(
      'restartRequest',
      const <String, Object?>{},
      commandId: requestId,
    );
    if (!sent) {
      _pendingControls.remove(requestId);
      return false;
    }
    return result.future.timeout(
      controlTimeout,
      onTimeout: () {
        _pendingControls.remove(requestId);
        return false;
      },
    );
  }

  @override
  Future<void> respondToRestart({
    required String requestId,
    required bool accepted,
  }) async {
    await _sendCommand('restartResponse', <String, Object?>{
      'requestId': requestId,
      'accepted': accepted,
    });
  }

  @override
  Future<void> resign() async {
    if (!isConnected || _meta == null) {
      return;
    }
    final bool accepted = await _sendCommand(
      'resign',
      const <String, Object?>{},
    );
    if (accepted) {
      await game.forceWinner(_opposite(_meta!.localSeat));
      _ending = true;
      _setState(RemoteConnectionState.ended);
      await sessionStore.delete();
    }
  }

  @override
  Future<void> leave() async {
    if (_disposed) {
      return;
    }
    if (socket.isConnected && !_ending) {
      await _sendCommand('leave', const <String, Object?>{});
    }
    _ending = true;
    await game.abandon();
    await sessionStore.delete();
  }

  Future<bool> _sendCommand(
    String type,
    Map<String, Object?> payload, {
    String? commandId,
  }) {
    if (!socket.isConnected || _disposed || _ending) {
      return Future<bool>.value(false);
    }
    final String id = commandId ?? _uuid.v4();
    final Map<String, Object?> message = <String, Object?>{
      'protocolVersion': onlineProtocolVersion,
      'commandId': id,
      'expectedSeq': _revision,
      'type': type,
      'payload': payload,
    };
    final Completer<bool> completer = Completer<bool>();
    final Timer timer = Timer(commandTimeout, () {
      final _PendingCommand? pending = _pendingCommands.remove(id);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.complete(false);
      }
    });
    _pendingCommands[id] = _PendingCommand(message, completer, timer);
    try {
      socket.send(message);
    } on Object {
      _completeCommand(id, false);
    }
    return completer.future;
  }

  void _completeCommand(String id, bool accepted) {
    final _PendingCommand? pending = _pendingCommands.remove(id);
    if (pending == null) {
      return;
    }
    pending.timer.cancel();
    if (!pending.completer.isCompleted) {
      pending.completer.complete(accepted);
    }
  }

  Future<void> _handleTerminalApiFailure(OnlineFailure failure) async {
    _ending = true;
    _setState(RemoteConnectionState.error);
    await sessionStore.delete();
    _events.add(RemoteOnlineFailure(failure));
  }

  void _setState(RemoteConnectionState next) {
    if (_disposed || stateNotifier.value == next) {
      return;
    }
    stateNotifier.value = next;
    _events.add(RemoteMatchStateChanged(next));
  }

  void _assertUsable() {
    if (_disposed) {
      throw StateError('CloudMatchCoordinator has been disposed.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _welcomeCompleter = null;
    for (final _PendingCommand pending in _pendingCommands.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.complete(false);
      }
    }
    _pendingCommands.clear();
    for (final Completer<bool> pending in _pendingControls.values) {
      if (!pending.isCompleted) {
        pending.complete(false);
      }
    }
    _pendingControls.clear();
    await _socketSubscription.cancel();
    await socket.close();
    await _events.close();
    stateNotifier.dispose();
  }
}

bool isTerminalOnlineFailure(OnlineFailure failure) =>
    failure == OnlineFailure.roomUnavailable ||
    failure == OnlineFailure.unauthorized ||
    failure == OnlineFailure.inviteExpired;

OnlineFailure onlineFailureForCode(String code) => switch (code) {
  'invalid_invite' || 'invalid_request' => OnlineFailure.invalidInvite,
  'invite_expired' => OnlineFailure.inviteExpired,
  'invite_already_used' => OnlineFailure.inviteAlreadyUsed,
  'room_unavailable' => OnlineFailure.roomUnavailable,
  'room_full' => OnlineFailure.roomFull,
  'version_mismatch' => OnlineFailure.versionMismatch,
  'unauthorized' => OnlineFailure.unauthorized,
  'service_unavailable' => OnlineFailure.serviceUnavailable,
  _ => OnlineFailure.protocolError,
};

class _PendingCommand {
  const _PendingCommand(this.message, this.completer, this.timer);

  final Map<String, Object?> message;
  final Completer<bool> completer;
  final Timer timer;
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

RemoteSeat _opposite(RemoteSeat seat) =>
    seat == RemoteSeat.first ? RemoteSeat.second : RemoteSeat.first;

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

Object _sanitizedDiagnosticError(Object error) =>
    StateError('Online transport failure (${error.runtimeType})');
