// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'remote_diagnostics.dart';
import 'remote_models.dart';
import 'remote_protocol.dart';
import 'remote_transport.dart';

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

class RemoteMatchAborted extends RemoteMatchEvent {
  const RemoteMatchAborted(this.reason);

  final String reason;
}

class RemoteMatchFailure extends RemoteMatchEvent {
  const RemoteMatchFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class RemoteMatchCoordinator {
  RemoteMatchCoordinator({
    required this.transport,
    required this.game,
    required this.localPeer,
    this.heartbeatEvery = heartbeatInterval,
    this.heartbeatSilenceTimeout = heartbeatTimeout,
    this.reconnectTimeout = reconnectWindow,
    this.reconnectBackoffBase = const Duration(seconds: 1),
    this.reconnectBackoffMaximum = const Duration(seconds: 5),
    this.approvalWaitTimeout = approvalTimeout,
    this.controlRequestTimeout = requestTimeout,
  }) : assert(reconnectBackoffBase > Duration.zero),
       assert(reconnectBackoffMaximum >= reconnectBackoffBase),
       _log = RemoteLogContext(
         transport: transport.kind,
         role: transport.role,
       ) {
    _transportSubscription = transport.events.listen(_onTransportEvent);
  }

  static const Duration heartbeatInterval = Duration(seconds: 5);
  static const Duration heartbeatTimeout = Duration(seconds: 15);
  static const Duration reconnectWindow = Duration(seconds: 60);
  static const Duration approvalTimeout = Duration(seconds: 30);
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int _maxRememberedMessageIds = 512;
  static const Uuid _uuid = Uuid();

  final RemoteTransport transport;
  final RemoteGameAdapter game;
  final RemotePeerInfo localPeer;
  final Duration heartbeatEvery;
  final Duration heartbeatSilenceTimeout;
  final Duration reconnectTimeout;
  final Duration reconnectBackoffBase;
  final Duration reconnectBackoffMaximum;
  final Duration approvalWaitTimeout;
  final Duration controlRequestTimeout;
  final RemoteDiagnostics diagnostics = RemoteDiagnostics();
  final RemoteLogContext _log;
  final RemoteFrameDecoder _decoder = RemoteFrameDecoder();
  final StreamController<RemoteMatchEvent> _events =
      StreamController<RemoteMatchEvent>.broadcast(sync: true);
  final ValueNotifier<RemoteConnectionState> stateNotifier =
      ValueNotifier<RemoteConnectionState>(RemoteConnectionState.idle);
  final Set<String> _seenMessageIds = <String>{};
  final Queue<String> _messageIdOrder = Queue<String>();
  final List<String> _actionLog = <String>[];

  late final StreamSubscription<RemoteTransportEvent> _transportSubscription;
  Future<void> _inboundSerial = Future<void>.value();
  Future<void> _outboundSerial = Future<void>.value();
  RemoteMatchConfig? _config;
  RemoteSessionMeta? _meta;
  RemotePeerInfo? _remotePeer;
  RemotePeerInfo? _pendingApprovalPeer;
  Timer? _approvalTimer;
  Timer? _heartbeatTimer;
  Timer? _reconnectDeadlineTimer;
  Timer? _incomingControlTimer;
  DateTime _lastInboundAt = DateTime.now();
  DateTime? _reconnectDeadline;
  String? _resumeToken;
  int _revision = 0;
  bool _disposed = false;
  bool _reconnectLoopRunning = false;
  bool _resuming = false;
  Completer<bool>? _pendingAction;
  String? _pendingActionRequestId;
  Completer<bool>? _pendingControl;
  String? _pendingControlRequestId;
  String? _acceptedControlRequestId;
  String? _incomingControlRequestId;
  int? _incomingControlRevision;

  Stream<RemoteMatchEvent> get events => _events.stream;

  RemoteConnectionState get state => stateNotifier.value;

  RemoteMatchConfig? get config => _config;

  RemoteSessionMeta? get meta => _meta;

  RemotePeerInfo? get remotePeer => _remotePeer;

  int get revision => _revision;

  bool get isConnected => state == RemoteConnectionState.ready;

  bool get isHost => transport.role == RemoteRole.host;

  bool get isLocalTurn => _meta != null && game.activeSeat == _meta!.localSeat;

  List<String> get actionLog => List<String>.unmodifiable(_actionLog);

  Map<String, Object?> get diagnosticSnapshot => <String, Object?>{
    'transport': transport.kind.name,
    'role': transport.role.name,
    'state': state.name,
    'sessionId': RemoteLogContext.shortId(_config?.sessionId ?? ''),
    'roundId': RemoteLogContext.shortId(_config?.roundId ?? ''),
    'peerId': RemoteLogContext.shortId(_remotePeer?.peerId ?? ''),
    'resumeTokenDigest': RemoteLogContext.secretDigest(_resumeToken ?? ''),
    ...diagnostics.toJson(),
  };

  Future<void> startHost({
    required RemoteHostOptions options,
    required Map<String, Object?> ruleSettings,
    required String initialFen,
    required bool hostPlaysFirst,
  }) async {
    _assertUsable();
    if (!isHost) {
      throw StateError('A join coordinator cannot start hosting.');
    }
    final String sessionId = _uuid.v4();
    final String roundId = _uuid.v4();
    final RemoteMatchConfig config = RemoteMatchConfig(
      sessionId: sessionId,
      roundId: roundId,
      ruleSchemaVersion: 1,
      ruleSettings: ruleSettings,
      initialFen: initialFen,
      hostPlaysFirst: hostPlaysFirst,
    );
    _installConfig(config);
    _meta = RemoteSessionMeta(
      transportKind: transport.kind,
      role: RemoteRole.host,
      localSeat: hostPlaysFirst ? RemoteSeat.first : RemoteSeat.second,
      hostPlaysFirst: hostPlaysFirst,
      sessionId: sessionId,
    );
    await game.configure(config);
    await transport.startHost(options);
    _setState(RemoteConnectionState.listening);
  }

  Future<List<RemoteEndpoint>> discover({
    Duration timeout = const Duration(seconds: 5),
    String? localAddress,
  }) async {
    _assertUsable();
    return transport.discover(timeout: timeout, localAddress: localAddress);
  }

  Future<void> join(RemoteEndpoint endpoint) async {
    _assertUsable();
    if (isHost) {
      throw StateError('A host coordinator cannot join another host.');
    }
    await transport.join(endpoint);
  }

  Future<void> approvePeer({required bool accepted}) async {
    _assertUsable();
    final RemotePeerInfo? peer = _pendingApprovalPeer;
    if (!isHost || peer == null) {
      throw StateError('There is no peer awaiting approval.');
    }
    _approvalTimer?.cancel();
    _approvalTimer = null;
    _pendingApprovalPeer = null;
    if (!accepted) {
      _log.info('REMOTE_PEER_APPROVAL_REJECTED', 'peer=${peer.shortId}');
      await _send(RemoteMessageType.helloRejected, <String, Object?>{
        'reason': 'hostRejected',
      });
      await transport.disconnectPeer(
        reason: 'Host rejected the peer.',
        expected: true,
      );
      _setState(RemoteConnectionState.listening);
      return;
    }
    _remotePeer = peer;
    _log.peerId = peer.peerId;
    _updateTransportLogContext(peerId: peer.peerId);
    _resumeToken = _newResumeToken();
    _log.info(
      'REMOTE_PEER_APPROVAL_ACCEPTED',
      'peer=${peer.shortId} tokenDigest='
          '${RemoteLogContext.secretDigest(_resumeToken!)}',
    );
    await _sendHelloAccepted(resumed: false);
    await _send(RemoteMessageType.matchConfig, _config!.toJson(), revision: 0);
    _setState(RemoteConnectionState.negotiating);
  }

  Future<bool> submitLocalAction(String notation) async {
    _assertUsable();
    if (!isConnected ||
        !isLocalTurn ||
        notation.isEmpty ||
        _hasPendingControl) {
      _log.warning(
        'REMOTE_LOCAL_ACTION_BLOCKED',
        'ready=$isConnected localTurn=$isLocalTurn '
            'pendingControl=$_hasPendingControl action=$notation',
      );
      return false;
    }
    if (isHost) {
      return _commitHostAction(notation, requestId: _uuid.v4());
    }
    if (_pendingAction != null && !_pendingAction!.isCompleted) {
      _log.warning(
        'REMOTE_LOCAL_ACTION_BLOCKED',
        'reason=pendingAction action=$notation',
      );
      return false;
    }
    final String requestId = _uuid.v4();
    final Completer<bool> completer = Completer<bool>();
    _pendingAction = completer;
    _pendingActionRequestId = requestId;
    await _send(RemoteMessageType.actionRequest, <String, Object?>{
      'requestId': requestId,
      'expectedRevision': _revision,
      'action': notation,
    });
    return completer.future.timeout(
      controlRequestTimeout,
      onTimeout: () {
        _log.warning(
          'REMOTE_ACTION_REQUEST_TIMEOUT',
          'request=${RemoteLogContext.shortId(requestId)} action=$notation',
        );
        _clearPendingAction(false);
        return false;
      },
    );
  }

  Future<bool> requestTakeBack(int steps) async {
    _assertUsable();
    if (!isConnected || steps <= 0 || steps > _actionLog.length) {
      return false;
    }
    return _sendControlRequest(
      RemoteMessageType.takeBackRequest,
      <String, Object?>{'steps': steps},
    );
  }

  Future<void> respondToTakeBack({
    required String requestId,
    required int steps,
    required bool accepted,
  }) async {
    _assertUsable();
    final bool canAccept = accepted && steps > 0 && steps <= _actionLog.length;
    final bool revisionMatches =
        requestId == _incomingControlRequestId &&
        _incomingControlRevision == _revision;
    await _send(RemoteMessageType.takeBackResponse, <String, Object?>{
      'requestId': requestId,
      'accepted': canAccept && revisionMatches,
      'steps': steps,
      'expectedRevision': _incomingControlRevision ?? _revision,
    });
    _clearIncomingControl(requestId);
    if (canAccept && revisionMatches && isHost) {
      await _applyTakeBackAsHost(steps);
    }
  }

  Future<bool> requestRestart() async {
    _assertUsable();
    if (!isConnected) {
      return false;
    }
    return _sendControlRequest(
      RemoteMessageType.restartRequest,
      const <String, Object?>{},
    );
  }

  Future<void> respondToRestart({
    required String requestId,
    required bool accepted,
  }) async {
    _assertUsable();
    final bool revisionMatches =
        requestId == _incomingControlRequestId &&
        _incomingControlRevision == _revision;
    await _send(RemoteMessageType.restartResponse, <String, Object?>{
      'requestId': requestId,
      'accepted': accepted && revisionMatches,
      'expectedRevision': _incomingControlRevision ?? _revision,
    });
    _clearIncomingControl(requestId);
    if (accepted && revisionMatches && isHost) {
      await _restartAsHost();
    }
  }

  Future<void> resign() async {
    _assertUsable();
    if (!isConnected || _meta == null) {
      return;
    }
    await _send(RemoteMessageType.resign, const <String, Object?>{});
    await game.forceWinner(_oppositeSeat(_meta!.localSeat));
    _log.info('REMOTE_LOCAL_RESIGNED', 'revision=$_revision');
  }

  void _onTransportEvent(RemoteTransportEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case RemoteTransportStateChanged():
        if (event.state != RemoteConnectionState.negotiating &&
            event.state != RemoteConnectionState.reconnecting) {
          _setState(event.state);
        }
      case RemoteTransportConnected():
        _lastInboundAt = DateTime.now();
        diagnostics.connectedAt = DateTime.now();
        _log.info(
          'REMOTE_TRANSPORT_CONNECTED',
          'endpoint=${event.endpoint.id}',
        );
        if (!isHost) {
          unawaited(_sendHello());
        }
      case RemoteTransportData():
        diagnostics.bytesReceived += event.bytes.length;
        _inboundSerial = _inboundSerial
            .catchError((Object error, StackTrace stackTrace) {
              _log.error('REMOTE_INBOUND_QUEUE_RECOVERED', error, stackTrace);
            })
            .then<void>((_) => _consumeBytes(event.bytes));
      case RemoteTransportProtocolMismatch():
        _events.add(RemoteMatchUpgradeRequired(event.peerVersion));
      case RemoteTransportDisconnected():
        _handleDisconnected(event.reason, expected: event.expected);
      case RemoteTransportFailure():
        _events.add(RemoteMatchFailure(event.error, event.stackTrace));
    }
  }

  Future<void> _consumeBytes(Uint8List bytes) async {
    try {
      final List<RemoteEnvelope> frames = _decoder.add(bytes);
      for (final RemoteEnvelope envelope in frames) {
        diagnostics.framesReceived++;
        _lastInboundAt = DateTime.now();
        _log.debug(
          'REMOTE_FRAME_RECEIVED',
          'type=${envelope.type.name} message='
              '${RemoteLogContext.shortId(envelope.messageId)} '
              'revision=${envelope.revision} bytes=${bytes.length}',
        );
        if (!_rememberMessage(envelope.messageId)) {
          diagnostics.duplicateMessages++;
          _log.warning(
            'REMOTE_DUPLICATE_MESSAGE',
            'message=${RemoteLogContext.shortId(envelope.messageId)} '
                'type=${envelope.type.name}',
          );
          continue;
        }
        await _handleEnvelope(envelope);
      }
    } on Object catch (error, stackTrace) {
      diagnostics.rejectedMessages++;
      _log.error('REMOTE_PROTOCOL_DECODE_FAILED', error, stackTrace);
      _events.add(RemoteMatchFailure(error, stackTrace));
      await transport.disconnectPeer(reason: 'Invalid remote protocol frame.');
    }
  }

  Future<void> _handleEnvelope(RemoteEnvelope envelope) async {
    final bool isHandshakeMessage =
        envelope.type == RemoteMessageType.hello ||
        envelope.type == RemoteMessageType.helloAccepted ||
        envelope.type == RemoteMessageType.helloRejected ||
        envelope.type == RemoteMessageType.busy;
    if (!isHandshakeMessage &&
        _config != null &&
        envelope.sessionId != _config!.sessionId) {
      diagnostics.rejectedMessages++;
      _log.warning(
        'REMOTE_SESSION_MISMATCH',
        'messageSession=${RemoteLogContext.shortId(envelope.sessionId)}',
      );
      return;
    }
    if (!isHandshakeMessage &&
        envelope.type != RemoteMessageType.matchConfig &&
        _config != null &&
        envelope.roundId != _config!.roundId) {
      diagnostics.rejectedMessages++;
      _log.warning(
        'REMOTE_ROUND_MISMATCH',
        'messageRound=${RemoteLogContext.shortId(envelope.roundId)} '
            'activeRound=${RemoteLogContext.shortId(_config!.roundId)}',
      );
      return;
    }

    switch (envelope.type) {
      case RemoteMessageType.hello:
        await _handleHello(envelope);
      case RemoteMessageType.helloAccepted:
        await _handleHelloAccepted(envelope);
      case RemoteMessageType.helloRejected:
        _setState(RemoteConnectionState.error);
        final String rejectionReason =
            envelope.payload['reason']?.toString() ?? 'hostRejected';
        _events.add(RemoteMatchActionRejected(rejectionReason));
        await transport.disconnectPeer(reason: rejectionReason, expected: true);
      case RemoteMessageType.busy:
        _setState(RemoteConnectionState.error);
        final String busyReason =
            envelope.payload['reason']?.toString() ?? 'hostBusy';
        _events.add(RemoteMatchActionRejected(busyReason));
        await transport.disconnectPeer(reason: busyReason, expected: true);
      case RemoteMessageType.matchConfig:
        await _handleMatchConfig(envelope);
      case RemoteMessageType.ready:
        await _handleReady(envelope);
      case RemoteMessageType.actionRequest:
        await _handleActionRequest(envelope);
      case RemoteMessageType.actionCommitted:
        await _handleActionCommitted(envelope);
      case RemoteMessageType.actionRejected:
        _handleActionRejected(envelope);
      case RemoteMessageType.snapshotRequest:
        if (isHost) {
          await _sendSnapshot();
        }
      case RemoteMessageType.snapshot:
        await _handleSnapshot(envelope);
      case RemoteMessageType.takeBackRequest:
        await _handleTakeBackRequest(envelope);
      case RemoteMessageType.takeBackResponse:
        await _handleTakeBackResponse(envelope);
      case RemoteMessageType.restartRequest:
        await _handleRestartRequest(envelope);
      case RemoteMessageType.restartResponse:
        await _handleRestartResponse(envelope);
      case RemoteMessageType.resign:
        await _handleRemoteResignation();
      case RemoteMessageType.ping:
        await _send(RemoteMessageType.pong, <String, Object?>{
          'echo': envelope.payload['sentAt'],
        });
      case RemoteMessageType.pong:
        _log.trace('REMOTE_HEARTBEAT_PONG', 'echo=${envelope.payload['echo']}');
      case RemoteMessageType.disconnect:
        await _handlePeerDisconnect(
          envelope.payload['reason']?.toString() ?? 'Peer left.',
        );
    }
  }

  Future<void> _handleHello(RemoteEnvelope envelope) async {
    if (!isHost) {
      diagnostics.rejectedMessages++;
      return;
    }
    final Object? rawPeer = envelope.payload['peer'];
    if (rawPeer is! Map) {
      throw const FormatException('hello.peer must be an object.');
    }
    final RemotePeerInfo peer = RemotePeerInfo.fromJson(
      rawPeer.cast<String, Object?>(),
    );
    final String resumeToken = envelope.payload['resumeToken'] is String
        ? envelope.payload['resumeToken']! as String
        : '';
    final bool validResume =
        _resumeToken != null &&
        resumeToken.isNotEmpty &&
        _constantTimeEquals(resumeToken, _resumeToken!) &&
        envelope.sessionId == _config?.sessionId;
    if (validResume) {
      _remotePeer = peer;
      _log.peerId = peer.peerId;
      _updateTransportLogContext(peerId: peer.peerId);
      _resuming = true;
      _log.info(
        'REMOTE_RESUME_AUTHENTICATED',
        'peer=${peer.shortId} peerRevision=${envelope.payload['revision']}',
      );
      await _sendHelloAccepted(resumed: true);
      await _sendSnapshot();
      _setState(RemoteConnectionState.negotiating);
      return;
    }

    if (_remotePeer != null && _resumeToken != null) {
      _log.warning(
        'REMOTE_UNAUTHENTICATED_RECONNECT_REJECTED',
        'peer=${peer.shortId}',
      );
      await _send(RemoteMessageType.busy, const <String, Object?>{
        'reason': 'activeSession',
      });
      await transport.disconnectPeer(
        reason: 'Invalid resume credentials.',
        expected: true,
      );
      return;
    }

    if (_pendingApprovalPeer != null) {
      if (_pendingApprovalPeer!.peerId == peer.peerId) {
        _log.warning('REMOTE_DUPLICATE_APPROVAL_HELLO', 'peer=${peer.shortId}');
        return;
      }
      _log.warning('REMOTE_DUPLICATE_APPROVAL_ATTEMPT', 'peer=${peer.shortId}');
      await _send(RemoteMessageType.busy, const <String, Object?>{
        'reason': 'approvalPending',
      });
      return;
    }

    _pendingApprovalPeer = peer;
    _setState(RemoteConnectionState.awaitingApproval);
    _events.add(RemotePeerApprovalRequested(peer));
    _log.info(
      'REMOTE_PEER_APPROVAL_REQUESTED',
      'peer=${peer.shortId} label=${peer.label} platform=${peer.platform}',
    );
    _approvalTimer?.cancel();
    _approvalTimer = Timer(approvalWaitTimeout, () {
      if (_pendingApprovalPeer != null && !_disposed) {
        unawaited(approvePeer(accepted: false));
      }
    });
  }

  Future<void> _sendHello() async {
    await _send(RemoteMessageType.hello, <String, Object?>{
      'peer': localPeer.toJson(),
      'resumeToken': _resumeToken ?? '',
      'revision': _revision,
    });
    _setState(RemoteConnectionState.negotiating);
  }

  Future<void> _sendHelloAccepted({required bool resumed}) async {
    await _send(RemoteMessageType.helloAccepted, <String, Object?>{
      'resumeToken': _resumeToken,
      'resumed': resumed,
      'peer': localPeer.toJson(),
    });
  }

  Future<void> _handleHelloAccepted(RemoteEnvelope envelope) async {
    if (isHost) {
      return;
    }
    final Object? token = envelope.payload['resumeToken'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('helloAccepted.resumeToken is required.');
    }
    _resumeToken = token;
    final Object? rawPeer = envelope.payload['peer'];
    if (rawPeer is Map) {
      _remotePeer = RemotePeerInfo.fromJson(rawPeer.cast<String, Object?>());
      _log.peerId = _remotePeer!.peerId;
      _updateTransportLogContext(peerId: _remotePeer!.peerId);
    }
    _resuming = envelope.payload['resumed'] == true;
    _log.info(
      'REMOTE_HELLO_ACCEPTED',
      'resumed=$_resuming tokenDigest='
          '${RemoteLogContext.secretDigest(token)}',
    );
  }

  Future<void> _handleMatchConfig(RemoteEnvelope envelope) async {
    if (isHost) {
      return;
    }
    final RemoteMatchConfig config = RemoteMatchConfig.fromJson(
      envelope.payload,
    );
    if (config.ruleSchemaVersion != 1 || config.clockEnabled) {
      throw const FormatException('Unsupported remote match configuration.');
    }
    _installConfig(config);
    _meta = RemoteSessionMeta(
      transportKind: transport.kind,
      role: RemoteRole.join,
      localSeat: config.hostPlaysFirst ? RemoteSeat.second : RemoteSeat.first,
      hostPlaysFirst: config.hostPlaysFirst,
      sessionId: config.sessionId,
    );
    _actionLog.clear();
    _revision = 0;
    await game.configure(config);
    await _send(RemoteMessageType.ready, const <String, Object?>{
      'ack': false,
    }, revision: 0);
    _setState(RemoteConnectionState.negotiating);
    _log.info(
      'REMOTE_MATCH_CONFIG_APPLIED',
      'rulesSchema=${config.ruleSchemaVersion} fen=${_fenSummary(game.fen)}',
    );
  }

  Future<void> _handleReady(RemoteEnvelope envelope) async {
    final bool ack = envelope.payload['ack'] == true;
    if (isHost && !ack) {
      await _send(RemoteMessageType.ready, const <String, Object?>{
        'ack': true,
      });
      _markReady(resumed: _resuming);
      return;
    }
    if (!isHost && ack) {
      _markReady(resumed: _resuming);
    }
  }

  void _markReady({required bool resumed}) {
    final RemoteMatchConfig? config = _config;
    final RemoteSessionMeta? meta = _meta;
    if (config == null || meta == null) {
      throw StateError('Ready received before match configuration.');
    }
    _resuming = false;
    _setState(RemoteConnectionState.ready);
    _startHeartbeat();
    _cancelReconnectDeadline();
    if (_acceptedControlRequestId == _pendingControlRequestId) {
      _completePendingControl(true);
    }
    _events.add(RemoteMatchReady(meta, config, resumed: resumed));
    _log.info(
      'REMOTE_MATCH_READY',
      'resumed=$resumed revision=$_revision actions=${_actionLog.length}',
    );
  }

  Future<void> _handleActionRequest(RemoteEnvelope envelope) async {
    if (!isHost || state != RemoteConnectionState.ready || _meta == null) {
      return;
    }
    final String? requestId = envelope.payload['requestId'] as String?;
    final String? action = envelope.payload['action'] as String?;
    final int? expectedRevision = envelope.payload['expectedRevision'] as int?;
    if (requestId == null || action == null || expectedRevision == null) {
      diagnostics.rejectedMessages++;
      return;
    }
    if (expectedRevision != _revision || game.activeSeat == _meta!.localSeat) {
      await _rejectAction(
        requestId,
        expectedRevision != _revision ? 'staleRevision' : 'notYourTurn',
      );
      return;
    }
    if (!await _commitHostAction(action, requestId: requestId)) {
      await _rejectAction(requestId, 'illegalAction');
    }
  }

  Future<bool> _commitHostAction(
    String notation, {
    required String requestId,
  }) async {
    final bool applied = await game.applyAction(notation);
    if (!applied) {
      diagnostics.rejectedMessages++;
      _log.warning(
        'REMOTE_ACTION_ILLEGAL',
        'request=${RemoteLogContext.shortId(requestId)} action=$notation',
      );
      return false;
    }
    _revision++;
    _actionLog.add(notation);
    diagnostics.lastRevision = _revision;
    final String resultFen = game.fen;
    await _send(RemoteMessageType.actionCommitted, <String, Object?>{
      'requestId': requestId,
      'action': notation,
      'resultFen': resultFen,
    }, revision: _revision);
    _log.debug(
      'REMOTE_ACTION_COMMITTED',
      'request=${RemoteLogContext.shortId(requestId)} action=$notation '
          'revision=$_revision fen=${_fenSummary(resultFen)}',
    );
    return true;
  }

  Future<void> _rejectAction(String requestId, String reason) async {
    diagnostics.rejectedMessages++;
    await _send(RemoteMessageType.actionRejected, <String, Object?>{
      'requestId': requestId,
      'reason': reason,
    });
    _log.warning(
      'REMOTE_ACTION_REJECTED',
      'request=${RemoteLogContext.shortId(requestId)} reason=$reason',
    );
  }

  Future<void> _handleActionCommitted(RemoteEnvelope envelope) async {
    if (isHost) {
      return;
    }
    final String? requestId = envelope.payload['requestId'] as String?;
    final String? action = envelope.payload['action'] as String?;
    final String? resultFen = envelope.payload['resultFen'] as String?;
    if (requestId == null || action == null || resultFen == null) {
      diagnostics.rejectedMessages++;
      return;
    }
    if (envelope.revision != _revision + 1) {
      await _requestSnapshot('revisionGap');
      return;
    }
    final bool applied = await game.applyAction(action);
    if (!applied || game.fen != resultFen) {
      _log.warning(
        'REMOTE_FEN_DIVERGENCE',
        'action=$action applied=$applied local=${_fenSummary(game.fen)} '
            'host=${_fenSummary(resultFen)}',
      );
      await _requestSnapshot('fenMismatch');
      return;
    }
    _revision = envelope.revision;
    _actionLog.add(action);
    diagnostics.lastRevision = _revision;
    if (requestId == _pendingActionRequestId) {
      _clearPendingAction(true);
    }
    _log.debug(
      'REMOTE_ACTION_APPLIED',
      'action=$action revision=$_revision fen=${_fenSummary(resultFen)}',
    );
  }

  void _handleActionRejected(RemoteEnvelope envelope) {
    final String reason =
        envelope.payload['reason']?.toString() ?? 'actionRejected';
    final String? requestId = envelope.payload['requestId'] as String?;
    if (requestId == _pendingActionRequestId) {
      _clearPendingAction(false);
    }
    _events.add(RemoteMatchActionRejected(reason));
  }

  Future<void> _requestSnapshot(String reason) async {
    diagnostics.resyncRequests++;
    await _send(RemoteMessageType.snapshotRequest, <String, Object?>{
      'reason': reason,
      'localRevision': _revision,
    });
    _log.warning(
      'REMOTE_SNAPSHOT_REQUESTED',
      'reason=$reason localRevision=$_revision',
    );
  }

  Future<void> _sendSnapshot() async {
    final RemoteMatchConfig? config = _config;
    if (!isHost || config == null) {
      return;
    }
    final RemoteStateSnapshot snapshot = RemoteStateSnapshot(
      revision: _revision,
      initialFen: config.initialFen,
      actions: List<String>.unmodifiable(_actionLog),
      resultFen: game.fen,
    );
    await _send(
      RemoteMessageType.snapshot,
      snapshot.toJson(),
      revision: _revision,
    );
    _log.info(
      'REMOTE_SNAPSHOT_SENT',
      'revision=$_revision actions=${_actionLog.length} '
          'fen=${_fenSummary(game.fen)}',
    );
  }

  Future<void> _handleSnapshot(RemoteEnvelope envelope) async {
    if (isHost) {
      return;
    }
    final RemoteStateSnapshot snapshot = RemoteStateSnapshot.fromJson(
      envelope.payload,
    );
    if (snapshot.revision != envelope.revision ||
        snapshot.revision < _revision) {
      diagnostics.rejectedMessages++;
      _log.warning(
        'REMOTE_SNAPSHOT_REVISION_REJECTED',
        'envelope=${envelope.revision} snapshot=${snapshot.revision} '
            'local=$_revision',
      );
      return;
    }
    await game.restoreSnapshot(snapshot);
    if (game.fen != snapshot.resultFen) {
      throw StateError(
        'Snapshot replay diverged: local=${game.fen}, '
        'host=${snapshot.resultFen}.',
      );
    }
    _actionLog
      ..clear()
      ..addAll(snapshot.actions);
    _revision = snapshot.revision;
    diagnostics.lastRevision = _revision;
    diagnostics.resynchronizations++;
    if (_acceptedControlRequestId == _pendingControlRequestId) {
      _completePendingControl(true);
    }
    _acceptedControlRequestId = null;
    _log.info(
      'REMOTE_SNAPSHOT_APPLIED',
      'revision=$_revision actions=${_actionLog.length} '
          'fen=${_fenSummary(game.fen)}',
    );
    if (_resuming) {
      await _send(RemoteMessageType.ready, const <String, Object?>{
        'ack': false,
      });
    }
  }

  Future<void> _handleTakeBackRequest(RemoteEnvelope envelope) async {
    final String? requestId = envelope.payload['requestId'] as String?;
    final int? steps = envelope.payload['steps'] as int?;
    final int? expectedRevision = envelope.payload['expectedRevision'] as int?;
    if (requestId == null ||
        steps == null ||
        steps <= 0 ||
        expectedRevision == null) {
      diagnostics.rejectedMessages++;
      return;
    }
    if (state != RemoteConnectionState.ready ||
        expectedRevision != _revision ||
        _hasPendingControl) {
      diagnostics.rejectedMessages++;
      await _send(RemoteMessageType.takeBackResponse, <String, Object?>{
        'requestId': requestId,
        'accepted': false,
        'steps': steps,
        'expectedRevision': expectedRevision,
        'reason': expectedRevision != _revision
            ? 'staleRevision'
            : 'controlPending',
      });
      return;
    }
    _setIncomingControl(requestId, expectedRevision);
    _events.add(RemoteTakeBackApprovalRequested(requestId, steps));
  }

  Future<void> _handleTakeBackResponse(RemoteEnvelope envelope) async {
    final String? requestId = envelope.payload['requestId'] as String?;
    final bool accepted = envelope.payload['accepted'] == true;
    final int? steps = envelope.payload['steps'] as int?;
    final int? expectedRevision = envelope.payload['expectedRevision'] as int?;
    if (requestId == null || requestId != _pendingControlRequestId) {
      return;
    }
    if (!accepted ||
        steps == null ||
        expectedRevision != _revision ||
        envelope.revision != _revision) {
      _completePendingControl(false);
      return;
    }
    if (isHost) {
      await _applyTakeBackAsHost(steps);
      _completePendingControl(true);
    } else {
      _acceptedControlRequestId = requestId;
    }
  }

  Future<void> _applyTakeBackAsHost(int steps) async {
    if (steps <= 0 || steps > _actionLog.length) {
      throw RangeError.range(steps, 1, _actionLog.length, 'steps');
    }
    await game.undoActions(steps);
    _actionLog.removeRange(_actionLog.length - steps, _actionLog.length);
    _revision++;
    diagnostics.lastRevision = _revision;
    await _sendSnapshot();
    _log.info(
      'REMOTE_TAKE_BACK_APPLIED',
      'steps=$steps revision=$_revision actions=${_actionLog.length}',
    );
  }

  Future<void> _handleRestartRequest(RemoteEnvelope envelope) async {
    final String? requestId = envelope.payload['requestId'] as String?;
    final int? expectedRevision = envelope.payload['expectedRevision'] as int?;
    if (requestId == null || expectedRevision == null) {
      diagnostics.rejectedMessages++;
      return;
    }
    if (state != RemoteConnectionState.ready ||
        expectedRevision != _revision ||
        _hasPendingControl) {
      diagnostics.rejectedMessages++;
      await _send(RemoteMessageType.restartResponse, <String, Object?>{
        'requestId': requestId,
        'accepted': false,
        'expectedRevision': expectedRevision,
        'reason': expectedRevision != _revision
            ? 'staleRevision'
            : 'controlPending',
      });
      return;
    }
    _setIncomingControl(requestId, expectedRevision);
    _events.add(RemoteRestartApprovalRequested(requestId));
  }

  Future<void> _handleRestartResponse(RemoteEnvelope envelope) async {
    final String? requestId = envelope.payload['requestId'] as String?;
    final bool accepted = envelope.payload['accepted'] == true;
    final int? expectedRevision = envelope.payload['expectedRevision'] as int?;
    if (requestId == null || requestId != _pendingControlRequestId) {
      return;
    }
    if (!accepted ||
        expectedRevision != _revision ||
        envelope.revision != _revision) {
      _completePendingControl(false);
      return;
    }
    if (isHost) {
      await _restartAsHost();
      _completePendingControl(true);
    } else {
      _acceptedControlRequestId = requestId;
    }
  }

  Future<void> _restartAsHost() async {
    final RemoteMatchConfig current = _config!;
    final RemoteMatchConfig next = RemoteMatchConfig(
      sessionId: current.sessionId,
      roundId: _uuid.v4(),
      ruleSchemaVersion: current.ruleSchemaVersion,
      ruleSettings: current.ruleSettings,
      initialFen: current.initialFen,
      hostPlaysFirst: current.hostPlaysFirst,
    );
    _installConfig(next);
    _revision = 0;
    _actionLog.clear();
    await game.configure(next);
    await _send(RemoteMessageType.matchConfig, next.toJson(), revision: 0);
    _setState(RemoteConnectionState.negotiating);
    _log.info('REMOTE_RESTART_STARTED', 'round=${_log.roundId}');
  }

  Future<void> _handleRemoteResignation() async {
    final RemoteSessionMeta? meta = _meta;
    if (meta == null) {
      return;
    }
    await game.forceWinner(meta.localSeat);
    _events.add(const RemoteOpponentResigned());
    _log.info('REMOTE_OPPONENT_RESIGNED', 'revision=$_revision');
  }

  Future<void> _handlePeerDisconnect(String reason) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _clearPendingAction(false);
    _completePendingControl(false);
    _clearIncomingControl();
    await game.abandon();
    _setState(RemoteConnectionState.ended);
    _events.add(RemoteMatchAborted(reason));
    _log.info('REMOTE_PEER_LEFT', 'reason=$reason');
    await transport.close();
  }

  Future<bool> _sendControlRequest(
    RemoteMessageType type,
    Map<String, Object?> payload,
  ) async {
    if (_hasPendingControl) {
      return false;
    }
    final String requestId = _uuid.v4();
    final Completer<bool> completer = Completer<bool>();
    _pendingControl = completer;
    _pendingControlRequestId = requestId;
    await _send(type, <String, Object?>{
      'requestId': requestId,
      'expectedRevision': _revision,
      ...payload,
    });
    return completer.future.timeout(
      controlRequestTimeout,
      onTimeout: () {
        _log.warning(
          'REMOTE_CONTROL_REQUEST_TIMEOUT',
          'type=${type.name} request=${RemoteLogContext.shortId(requestId)}',
        );
        _completePendingControl(false);
        return false;
      },
    );
  }

  Future<void> _send(
    RemoteMessageType type,
    Map<String, Object?> payload, {
    int? revision,
  }) {
    final String messageId = _uuid.v4();
    final RemoteEnvelope envelope = RemoteEnvelope(
      type: type,
      sessionId: _config?.sessionId ?? '',
      roundId: _config?.roundId ?? '',
      messageId: messageId,
      revision: revision ?? _revision,
      payload: payload,
    );
    final Uint8List bytes = RemoteFrameCodec.encode(envelope);
    final Completer<void> result = Completer<void>();
    _outboundSerial = _outboundSerial.then<void>((_) async {
      try {
        await transport.send(bytes);
        diagnostics.bytesSent += bytes.length;
        diagnostics.framesSent++;
        _log.debug(
          'REMOTE_FRAME_SENT',
          'type=${type.name} message=${RemoteLogContext.shortId(messageId)} '
              'revision=${envelope.revision} bytes=${bytes.length}',
        );
        result.complete();
      } on Object catch (error, stackTrace) {
        _log.error('REMOTE_FRAME_SEND_FAILED', error, stackTrace);
        if (!result.isCompleted) {
          result.completeError(error, stackTrace);
        }
      }
    });
    return result.future;
  }

  void _handleDisconnected(String reason, {required bool expected}) {
    if (_disposed) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _decoder.reset();
    _clearPendingAction(false);
    _completePendingControl(false);
    _clearIncomingControl();
    _log.warning(
      'REMOTE_LINK_DISCONNECTED',
      'expected=$expected reason=$reason '
          'diagnostics=${jsonEncode(diagnosticSnapshot)}',
    );
    if (expected) {
      return;
    }
    if (_resumeToken == null || _config == null) {
      if (isHost) {
        _approvalTimer?.cancel();
        _approvalTimer = null;
        _pendingApprovalPeer = null;
        _setState(RemoteConnectionState.listening);
        _log.info('REMOTE_UNAPPROVED_PEER_CLEARED', 'reason=$reason');
        return;
      }
      _setState(RemoteConnectionState.error);
      _events.add(RemoteMatchAborted(reason));
      return;
    }
    _setState(RemoteConnectionState.reconnecting);
    _reconnectDeadline = DateTime.now().add(reconnectTimeout);
    _reconnectDeadlineTimer?.cancel();
    _reconnectDeadlineTimer = Timer(reconnectTimeout, () {
      unawaited(_abortAfterReconnectTimeout());
    });
    _log.warning(
      'REMOTE_RECONNECT_WINDOW_STARTED',
      'reason=$reason milliseconds=${reconnectTimeout.inMilliseconds}',
    );
    if (!isHost) {
      unawaited(_runReconnectLoop());
    }
  }

  Future<void> _runReconnectLoop() async {
    if (_reconnectLoopRunning || _disposed) {
      return;
    }
    _reconnectLoopRunning = true;
    int attempt = 0;
    try {
      while (!_disposed &&
          state == RemoteConnectionState.reconnecting &&
          DateTime.now().isBefore(_reconnectDeadline!)) {
        attempt++;
        diagnostics.reconnectAttempts++;
        final int multiplier = 1 << min(attempt - 1, 3);
        final int delayMilliseconds = min(
          reconnectBackoffMaximum.inMilliseconds,
          reconnectBackoffBase.inMilliseconds * multiplier,
        );
        _log.info(
          'REMOTE_RECONNECT_ATTEMPT',
          'attempt=$attempt nextDelayMs=$delayMilliseconds',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMilliseconds));
        if (_disposed || state != RemoteConnectionState.reconnecting) {
          return;
        }
        try {
          await transport.reconnect();
          if (state == RemoteConnectionState.ready) {
            return;
          }
        } on Object catch (error) {
          _log.warning(
            'REMOTE_RECONNECT_ATTEMPT_FAILED',
            'attempt=$attempt error=$error',
          );
        }
      }
    } finally {
      _reconnectLoopRunning = false;
    }
  }

  Future<void> _abortAfterReconnectTimeout() async {
    if (_disposed || state != RemoteConnectionState.reconnecting) {
      return;
    }
    await game.abandon();
    _setState(RemoteConnectionState.ended);
    _events.add(
      RemoteMatchAborted(
        'Reconnect timed out after ${reconnectTimeout.inSeconds} seconds.',
      ),
    );
    _log.warning(
      'REMOTE_RECONNECT_TIMEOUT',
      'diagnostics=${jsonEncode(diagnosticSnapshot)}',
    );
    await transport.close();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastInboundAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(heartbeatEvery, (Timer timer) {
      if (_disposed || state != RemoteConnectionState.ready) {
        return;
      }
      final Duration silence = DateTime.now().difference(_lastInboundAt);
      if (silence >= heartbeatSilenceTimeout) {
        _log.warning(
          'REMOTE_HEARTBEAT_TIMEOUT',
          'silenceMs=${silence.inMilliseconds}',
        );
        unawaited(
          transport.disconnectPeer(reason: 'Remote heartbeat timed out.'),
        );
        return;
      }
      unawaited(
        _send(RemoteMessageType.ping, <String, Object?>{
          'sentAt': DateTime.now().toIso8601String(),
        }),
      );
    });
  }

  void _installConfig(RemoteMatchConfig config) {
    _config = config;
    _log.sessionId = config.sessionId;
    _log.roundId = config.roundId;
    _updateTransportLogContext(
      sessionId: config.sessionId,
      roundId: config.roundId,
    );
  }

  void _updateTransportLogContext({
    String? sessionId,
    String? roundId,
    String? peerId,
  }) {
    final RemoteTransport current = transport;
    if (current is RemoteTransportLogContextSink) {
      (current as RemoteTransportLogContextSink).updateLogContext(
        sessionId: sessionId,
        roundId: roundId,
        peerId: peerId,
      );
    }
  }

  void _setState(RemoteConnectionState next) {
    if (_disposed || state == next) {
      return;
    }
    final RemoteConnectionState previous = state;
    stateNotifier.value = next;
    _log.state = next;
    _events.add(RemoteMatchStateChanged(next));
    _log.info(
      'REMOTE_MATCH_STATE_CHANGED',
      'from=${previous.name} to=${next.name}',
    );
  }

  bool _rememberMessage(String id) {
    if (!_seenMessageIds.add(id)) {
      return false;
    }
    _messageIdOrder.addLast(id);
    if (_messageIdOrder.length > _maxRememberedMessageIds) {
      _seenMessageIds.remove(_messageIdOrder.removeFirst());
    }
    return true;
  }

  void _clearPendingAction(bool result) {
    final Completer<bool>? completer = _pendingAction;
    _pendingAction = null;
    _pendingActionRequestId = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _completePendingControl(bool result) {
    final Completer<bool>? completer = _pendingControl;
    _pendingControl = null;
    _pendingControlRequestId = null;
    _acceptedControlRequestId = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  bool get _hasPendingControl =>
      (_pendingControl != null && !_pendingControl!.isCompleted) ||
      _incomingControlRequestId != null;

  void _setIncomingControl(String requestId, int revision) {
    _incomingControlRequestId = requestId;
    _incomingControlRevision = revision;
    _incomingControlTimer?.cancel();
    _incomingControlTimer = Timer(controlRequestTimeout, () {
      if (_incomingControlRequestId == requestId) {
        _log.warning(
          'REMOTE_INCOMING_CONTROL_TIMEOUT',
          'request=${RemoteLogContext.shortId(requestId)} revision=$revision',
        );
        _clearIncomingControl(requestId);
      }
    });
  }

  void _clearIncomingControl([String? requestId]) {
    if (requestId != null && requestId != _incomingControlRequestId) {
      return;
    }
    _incomingControlTimer?.cancel();
    _incomingControlTimer = null;
    _incomingControlRequestId = null;
    _incomingControlRevision = null;
  }

  void _cancelReconnectDeadline() {
    _reconnectDeadlineTimer?.cancel();
    _reconnectDeadlineTimer = null;
    _reconnectDeadline = null;
  }

  void _assertUsable() {
    if (_disposed) {
      throw StateError('RemoteMatchCoordinator is disposed.');
    }
  }

  static RemoteSeat _oppositeSeat(RemoteSeat seat) {
    return seat == RemoteSeat.first ? RemoteSeat.second : RemoteSeat.first;
  }

  static String _fenSummary(String fen) {
    return sha256.convert(utf8.encode(fen)).toString().substring(0, 12);
  }

  static String _newResumeToken() {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256), growable: false),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String left, String right) {
    final List<int> a = utf8.encode(left);
    final List<int> b = utf8.encode(right);
    if (a.isEmpty || b.isEmpty) {
      return a.isEmpty && b.isEmpty;
    }
    int difference = a.length ^ b.length;
    final int length = max(a.length, b.length);
    for (int i = 0; i < length; i++) {
      difference |= a[i % a.length] ^ b[i % b.length];
    }
    return difference == 0;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (transport.isConnected) {
      try {
        await _send(RemoteMessageType.disconnect, const <String, Object?>{
          'reason': 'Local player left.',
        }).timeout(const Duration(seconds: 1));
      } on Object catch (error) {
        _log.warning('REMOTE_DISCONNECT_NOTICE_FAILED', 'error=$error');
      }
    }
    _log.info(
      'REMOTE_COORDINATOR_DISPOSE',
      'diagnostics=${jsonEncode(diagnosticSnapshot)}',
    );
    _disposed = true;
    _approvalTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectDeadlineTimer?.cancel();
    _clearIncomingControl();
    _clearPendingAction(false);
    _completePendingControl(false);
    await _transportSubscription.cancel();
    await transport.close();
    await _events.close();
    stateNotifier.dispose();
  }
}
