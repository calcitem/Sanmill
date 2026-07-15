// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/remote_match_coordinator.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/remote_play/remote_protocol.dart';
import 'package:sanmill/remote_play/remote_transport.dart';

const bool _runExtendedRemoteTests = bool.fromEnvironment(
  'remote_extended_tests',
);

void main() {
  test(
    'host approval, authoritative actions, and take-back stay in sync',
    () async {
      final _MemoryTransport hostTransport = _MemoryTransport(
        role: RemoteRole.host,
      );
      final _MemoryTransport joinTransport = _MemoryTransport(
        role: RemoteRole.join,
      );
      hostTransport.peer = joinTransport;
      joinTransport.peer = hostTransport;
      final _FakeGame hostGame = _FakeGame();
      final _FakeGame joinGame = _FakeGame();
      final RemoteMatchCoordinator host = RemoteMatchCoordinator(
        transport: hostTransport,
        game: hostGame,
        localPeer: _peer('host'),
      );
      final RemoteMatchCoordinator join = RemoteMatchCoordinator(
        transport: joinTransport,
        game: joinGame,
        localPeer: _peer('join'),
      );
      addTearDown(host.dispose);
      addTearDown(join.dispose);

      final Future<RemotePeerApprovalRequested> approval = host.events
          .where(
            (RemoteMatchEvent event) => event is RemotePeerApprovalRequested,
          )
          .cast<RemotePeerApprovalRequested>()
          .first;
      await host.startHost(
        options: const RemoteHostOptions(),
        ruleSettings: const <String, Object?>{'piecesCount': 9},
        initialFen: 'start',
        hostPlaysFirst: true,
      );
      await join.join(const RemoteEndpoint(id: 'host', label: 'host'));
      expect((await approval).peer.peerId, 'join');

      final Future<RemoteMatchReady> hostReady = host.events
          .where((RemoteMatchEvent event) => event is RemoteMatchReady)
          .cast<RemoteMatchReady>()
          .first;
      final Future<RemoteMatchReady> joinReady = join.events
          .where((RemoteMatchEvent event) => event is RemoteMatchReady)
          .cast<RemoteMatchReady>()
          .first;
      await host.approvePeer(accepted: true);
      await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
        hostReady,
        joinReady,
      ]).timeout(const Duration(seconds: 2));

      expect(await host.submitLocalAction('a1'), isTrue);
      await _eventLoop();
      expect(hostGame.fen, 'start|a1');
      expect(joinGame.fen, hostGame.fen);
      expect(host.revision, 1);
      expect(join.revision, 1);

      expect(await join.submitLocalAction('b2'), isTrue);
      await _eventLoop();
      expect(hostGame.fen, 'start|a1|b2');
      expect(joinGame.fen, hostGame.fen);

      final Future<RemoteTakeBackApprovalRequested> takeBack = join.events
          .where(
            (RemoteMatchEvent event) =>
                event is RemoteTakeBackApprovalRequested,
          )
          .cast<RemoteTakeBackApprovalRequested>()
          .first;
      final Future<bool> request = host.requestTakeBack(1);
      final RemoteTakeBackApprovalRequested received = await takeBack;
      await join.respondToTakeBack(
        requestId: received.requestId,
        steps: received.steps,
        accepted: true,
      );
      expect(await request, isTrue);
      await _eventLoop();
      expect(hostGame.fen, 'start|a1');
      expect(joinGame.fen, hostGame.fen);
    },
  );

  test('host rejects an unapproved peer without starting a match', () async {
    final _MemoryTransport hostTransport = _MemoryTransport(
      role: RemoteRole.host,
    );
    final _MemoryTransport joinTransport = _MemoryTransport(
      role: RemoteRole.join,
    );
    hostTransport.peer = joinTransport;
    joinTransport.peer = hostTransport;
    final RemoteMatchCoordinator host = RemoteMatchCoordinator(
      transport: hostTransport,
      game: _FakeGame(),
      localPeer: _peer('host'),
    );
    final RemoteMatchCoordinator join = RemoteMatchCoordinator(
      transport: joinTransport,
      game: _FakeGame(),
      localPeer: _peer('join'),
    );
    addTearDown(host.dispose);
    addTearDown(join.dispose);

    final Future<RemotePeerApprovalRequested> approval = host.events
        .where((RemoteMatchEvent event) => event is RemotePeerApprovalRequested)
        .cast<RemotePeerApprovalRequested>()
        .first;
    await host.startHost(
      options: const RemoteHostOptions(),
      ruleSettings: const <String, Object?>{'piecesCount': 9},
      initialFen: 'start',
      hostPlaysFirst: true,
    );
    await join.join(const RemoteEndpoint(id: 'host', label: 'host'));
    await approval;

    await host.approvePeer(accepted: false);
    await _eventLoop();

    expect(host.state, RemoteConnectionState.listening);
    expect(join.isConnected, isFalse);
  });

  test(
    'approval timeout rejects a peer and returns the host to listening',
    () async {
      final _MemoryTransport hostTransport = _MemoryTransport(
        role: RemoteRole.host,
      );
      final _MemoryTransport joinTransport = _MemoryTransport(
        role: RemoteRole.join,
      );
      hostTransport.peer = joinTransport;
      joinTransport.peer = hostTransport;
      final RemoteMatchCoordinator host = RemoteMatchCoordinator(
        transport: hostTransport,
        game: _FakeGame(),
        localPeer: _peer('host'),
        approvalWaitTimeout: const Duration(milliseconds: 30),
      );
      final RemoteMatchCoordinator join = RemoteMatchCoordinator(
        transport: joinTransport,
        game: _FakeGame(),
        localPeer: _peer('join'),
      );
      addTearDown(host.dispose);
      addTearDown(join.dispose);
      final Future<RemoteMatchActionRejected> rejected = join.events
          .where((RemoteMatchEvent event) => event is RemoteMatchActionRejected)
          .cast<RemoteMatchActionRejected>()
          .first;

      await host.startHost(
        options: const RemoteHostOptions(),
        ruleSettings: const <String, Object?>{'piecesCount': 9},
        initialFen: 'start',
        hostPlaysFirst: true,
      );
      await join.join(const RemoteEndpoint(id: 'host', label: 'host'));

      expect(
        (await rejected.timeout(const Duration(seconds: 1))).reason,
        'hostRejected',
      );
      await _eventLoop();
      expect(host.state, RemoteConnectionState.listening);
    },
  );

  test('disconnect while awaiting approval releases the host slot', () async {
    final _MemoryTransport hostTransport = _MemoryTransport(
      role: RemoteRole.host,
    );
    final _MemoryTransport joinTransport = _MemoryTransport(
      role: RemoteRole.join,
    );
    hostTransport.peer = joinTransport;
    joinTransport.peer = hostTransport;
    final RemoteMatchCoordinator host = RemoteMatchCoordinator(
      transport: hostTransport,
      game: _FakeGame(),
      localPeer: _peer('host'),
    );
    final RemoteMatchCoordinator join = RemoteMatchCoordinator(
      transport: joinTransport,
      game: _FakeGame(),
      localPeer: _peer('join'),
    );
    addTearDown(host.dispose);
    addTearDown(join.dispose);

    final Future<RemotePeerApprovalRequested> firstApproval = host.events
        .where((RemoteMatchEvent event) => event is RemotePeerApprovalRequested)
        .cast<RemotePeerApprovalRequested>()
        .first;
    await host.startHost(
      options: const RemoteHostOptions(),
      ruleSettings: const <String, Object?>{'piecesCount': 9},
      initialFen: 'start',
      hostPlaysFirst: true,
    );
    await join.join(const RemoteEndpoint(id: 'host', label: 'host'));
    await firstApproval;
    await _eventLoop();

    joinTransport.forceDisconnect('left before approval');
    await _eventLoop();
    expect(host.state, RemoteConnectionState.listening);

    final Future<RemotePeerApprovalRequested> secondApproval = host.events
        .where((RemoteMatchEvent event) => event is RemotePeerApprovalRequested)
        .cast<RemotePeerApprovalRequested>()
        .first;
    await join.join(const RemoteEndpoint(id: 'host', label: 'host'));
    expect(
      (await secondApproval.timeout(const Duration(seconds: 1))).peer.peerId,
      'join',
    );
  });

  test(
    'duplicates, stale revisions, and illegal actions are rejected',
    () async {
      final _ReadyPair pair = await _ReadyPair.create();
      addTearDown(pair.dispose);

      expect(await pair.host.submitLocalAction('a1'), isTrue);
      await _eventLoop();
      expect(await pair.join.submitLocalAction('illegal'), isFalse);
      expect(pair.host.revision, 1);
      expect(pair.join.revision, 1);

      final RemoteEnvelope stale = RemoteEnvelope(
        type: RemoteMessageType.actionRequest,
        sessionId: pair.host.config!.sessionId,
        roundId: pair.host.config!.roundId,
        messageId: 'stale-action',
        revision: 0,
        payload: const <String, Object?>{
          'requestId': 'stale-request',
          'expectedRevision': 0,
          'action': 'b2',
        },
      );
      pair.hostTransport.inject(RemoteFrameCodec.encode(stale));
      await _eventLoop();
      expect(pair.host.revision, 1);

      final RemoteEnvelope ping = RemoteEnvelope(
        type: RemoteMessageType.ping,
        sessionId: pair.host.config!.sessionId,
        roundId: pair.host.config!.roundId,
        messageId: 'duplicate-ping',
        revision: pair.host.revision,
        payload: const <String, Object?>{'sentAt': 'test'},
      );
      final Uint8List bytes = RemoteFrameCodec.encode(ping);
      pair.hostTransport.inject(bytes);
      pair.hostTransport.inject(bytes);
      await _eventLoop();
      expect(pair.host.diagnostics.duplicateMessages, 1);

      final RemoteEnvelope oldRound = RemoteEnvelope(
        type: RemoteMessageType.ping,
        sessionId: pair.host.config!.sessionId,
        roundId: 'old-round',
        messageId: 'old-round-ping',
        revision: pair.host.revision,
        payload: const <String, Object?>{'sentAt': 'test'},
      );
      pair.hostTransport.inject(RemoteFrameCodec.encode(oldRound));
      await _eventLoop();
      expect(pair.host.diagnostics.rejectedMessages, greaterThanOrEqualTo(3));
    },
  );

  test(
    'restart preserves rules and seats, and resignation is one-sided',
    () async {
      final _ReadyPair pair = await _ReadyPair.create(hostPlaysFirst: false);
      addTearDown(pair.dispose);
      final String firstRound = pair.host.config!.roundId;
      final Future<RemoteRestartApprovalRequested> restartApproval = pair
          .host
          .events
          .where(
            (RemoteMatchEvent event) => event is RemoteRestartApprovalRequested,
          )
          .cast<RemoteRestartApprovalRequested>()
          .first;
      final Future<bool> restart = pair.join.requestRestart();
      final RemoteRestartApprovalRequested request = await restartApproval;
      await pair.host.respondToRestart(
        requestId: request.requestId,
        accepted: true,
      );

      expect(await restart.timeout(const Duration(seconds: 2)), isTrue);
      expect(pair.host.config!.roundId, isNot(firstRound));
      expect(pair.join.config!.roundId, pair.host.config!.roundId);
      expect(pair.host.config!.ruleSettings, <String, Object?>{
        'piecesCount': 9,
      });
      expect(pair.host.meta!.localSeat, RemoteSeat.second);
      expect(pair.join.meta!.localSeat, RemoteSeat.first);

      final Future<RemoteOpponentResigned> resignation = pair.host.events
          .where((RemoteMatchEvent event) => event is RemoteOpponentResigned)
          .cast<RemoteOpponentResigned>()
          .first;
      await pair.join.resign();
      await resignation.timeout(const Duration(seconds: 1));
      expect(pair.hostGame.forcedWinner, RemoteSeat.second);
      expect(pair.joinGame.forcedWinner, RemoteSeat.second);
    },
  );

  test('unexpected disconnect resumes with a mandatory snapshot', () async {
    final _ReadyPair pair = await _ReadyPair.create();
    addTearDown(pair.dispose);
    expect(await pair.host.submitLocalAction('a1'), isTrue);
    await _eventLoop();
    final Future<RemoteMatchReady> hostResumed = pair.host.events
        .where(
          (RemoteMatchEvent event) =>
              event is RemoteMatchReady && event.resumed,
        )
        .cast<RemoteMatchReady>()
        .first;
    final Future<RemoteMatchReady> joinResumed = pair.join.events
        .where(
          (RemoteMatchEvent event) =>
              event is RemoteMatchReady && event.resumed,
        )
        .cast<RemoteMatchReady>()
        .first;

    pair.joinTransport.forceDisconnect('fault injection');
    await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
      hostResumed,
      joinResumed,
    ]).timeout(const Duration(seconds: 3));

    expect(pair.host.state, RemoteConnectionState.ready);
    expect(pair.join.state, RemoteConnectionState.ready);
    expect(pair.hostGame.fen, pair.joinGame.fen);
    expect(pair.join.diagnostics.reconnectAttempts, greaterThanOrEqualTo(1));
  });

  test(
    'extended synchronization survives 200 rounds and 100 reconnects',
    () async {
      final _ReadyPair pair = await _ReadyPair.create(
        reconnectTimeout: const Duration(seconds: 2),
        reconnectBackoffBase: const Duration(milliseconds: 1),
      );
      final StreamSubscription<RemoteMatchEvent> approvalSubscription = pair
          .host
          .events
          .listen((RemoteMatchEvent event) {
            if (event case final RemoteRestartApprovalRequested request) {
              unawaited(
                pair.host.respondToRestart(
                  requestId: request.requestId,
                  accepted: true,
                ),
              );
            }
          });
      addTearDown(approvalSubscription.cancel);
      addTearDown(pair.dispose);

      const int rounds = 200;
      const int actionsPerRound = 50;
      int acceptedActions = 0;
      int reconnects = 0;

      for (int round = 0; round < rounds; round++) {
        for (int action = 0; action < actionsPerRound; action++) {
          final RemoteMatchCoordinator mover = pair.host.isLocalTurn
              ? pair.host
              : pair.join;
          expect(await mover.submitLocalAction('r${round}a$action'), isTrue);
          await _waitForSynchronization(pair);
          acceptedActions++;

          if (acceptedActions % 100 == 0) {
            final Future<RemoteMatchReady> hostResumed = _nextResume(pair.host);
            final Future<RemoteMatchReady> joinResumed = _nextResume(pair.join);
            pair.joinTransport.forceDisconnect(
              'extended fault ${reconnects + 1}',
            );
            await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
              hostResumed,
              joinResumed,
            ]).timeout(const Duration(seconds: 2));
            await _waitForSynchronization(pair);
            reconnects++;
          }
        }

        if (round != rounds - 1) {
          expect(
            await pair.join.requestRestart().timeout(
              const Duration(seconds: 2),
            ),
            isTrue,
          );
          await _waitForSynchronization(pair);
        }
      }

      expect(acceptedActions, 10000);
      expect(reconnects, 100);
      expect(pair.hostGame.fen, pair.joinGame.fen);
      expect(
        pair.join.diagnostics.resynchronizations,
        greaterThanOrEqualTo(100),
      );
      expect(
        pair.join.diagnostics.reconnectAttempts,
        greaterThanOrEqualTo(100),
      );
    },
    skip: !_runExtendedRemoteTests,
  );
}

Future<RemoteMatchReady> _nextResume(RemoteMatchCoordinator coordinator) {
  return coordinator.events
      .where(
        (RemoteMatchEvent event) => event is RemoteMatchReady && event.resumed,
      )
      .cast<RemoteMatchReady>()
      .first;
}

Future<void> _waitForSynchronization(_ReadyPair pair) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 1));
  do {
    if (pair.host.state == RemoteConnectionState.ready &&
        pair.join.state == RemoteConnectionState.ready &&
        pair.host.revision == pair.join.revision &&
        pair.hostGame.fen == pair.joinGame.fen) {
      return;
    }
    await _eventLoop();
  } while (DateTime.now().isBefore(deadline));
  fail(
    'Remote peers did not synchronize: '
    'host=${pair.host.state}/${pair.host.revision}/${pair.hostGame.fen} '
    'join=${pair.join.state}/${pair.join.revision}/${pair.joinGame.fen}',
  );
}

class _ReadyPair {
  _ReadyPair({
    required this.host,
    required this.join,
    required this.hostTransport,
    required this.joinTransport,
    required this.hostGame,
    required this.joinGame,
  });

  static Future<_ReadyPair> create({
    bool hostPlaysFirst = true,
    Duration reconnectTimeout = const Duration(seconds: 3),
    Duration reconnectBackoffBase = const Duration(seconds: 1),
  }) async {
    final _MemoryTransport hostTransport = _MemoryTransport(
      role: RemoteRole.host,
    );
    final _MemoryTransport joinTransport = _MemoryTransport(
      role: RemoteRole.join,
    );
    hostTransport.peer = joinTransport;
    joinTransport.peer = hostTransport;
    final _FakeGame hostGame = _FakeGame();
    final _FakeGame joinGame = _FakeGame();
    final RemoteMatchCoordinator host = RemoteMatchCoordinator(
      transport: hostTransport,
      game: hostGame,
      localPeer: _peer('host'),
      reconnectTimeout: reconnectTimeout,
      reconnectBackoffBase: reconnectBackoffBase,
    );
    final RemoteMatchCoordinator join = RemoteMatchCoordinator(
      transport: joinTransport,
      game: joinGame,
      localPeer: _peer('join'),
      reconnectTimeout: reconnectTimeout,
      reconnectBackoffBase: reconnectBackoffBase,
    );
    final Future<RemotePeerApprovalRequested> approval = host.events
        .where((RemoteMatchEvent event) => event is RemotePeerApprovalRequested)
        .cast<RemotePeerApprovalRequested>()
        .first;
    final Future<RemoteMatchReady> hostReady = host.events
        .where((RemoteMatchEvent event) => event is RemoteMatchReady)
        .cast<RemoteMatchReady>()
        .first;
    final Future<RemoteMatchReady> joinReady = join.events
        .where((RemoteMatchEvent event) => event is RemoteMatchReady)
        .cast<RemoteMatchReady>()
        .first;
    await host.startHost(
      options: const RemoteHostOptions(),
      ruleSettings: const <String, Object?>{'piecesCount': 9},
      initialFen: 'start',
      hostPlaysFirst: hostPlaysFirst,
    );
    await join.join(const RemoteEndpoint(id: 'host', label: 'host'));
    await approval;
    await host.approvePeer(accepted: true);
    await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
      hostReady,
      joinReady,
    ]).timeout(const Duration(seconds: 2));
    return _ReadyPair(
      host: host,
      join: join,
      hostTransport: hostTransport,
      joinTransport: joinTransport,
      hostGame: hostGame,
      joinGame: joinGame,
    );
  }

  final RemoteMatchCoordinator host;
  final RemoteMatchCoordinator join;
  final _MemoryTransport hostTransport;
  final _MemoryTransport joinTransport;
  final _FakeGame hostGame;
  final _FakeGame joinGame;

  Future<void> dispose() async {
    await join.dispose();
    await host.dispose();
  }
}

RemotePeerInfo _peer(String id) {
  return RemotePeerInfo(
    peerId: id,
    label: id,
    platform: 'test',
    appVersion: '1.0.0',
    appBuild: '1',
  );
}

Future<void> _eventLoop() => Future<void>.delayed(Duration.zero);

class _FakeGame implements RemoteGameAdapter {
  RemoteSeat _activeSeat = RemoteSeat.first;
  String _initialFen = '';
  final List<String> _actions = <String>[];
  RemoteSeat? forcedWinner;

  @override
  RemoteSeat get activeSeat => _activeSeat;

  @override
  String get fen => <String>[_initialFen, ..._actions].join('|');

  @override
  Future<void> configure(RemoteMatchConfig config) async {
    _initialFen = config.initialFen;
    _actions.clear();
    _activeSeat = RemoteSeat.first;
  }

  @override
  Future<bool> applyAction(String notation) async {
    if (notation.isEmpty || notation == 'illegal') {
      return false;
    }
    _actions.add(notation);
    _activeSeat = _activeSeat == RemoteSeat.first
        ? RemoteSeat.second
        : RemoteSeat.first;
    return true;
  }

  @override
  Future<void> restoreSnapshot(RemoteStateSnapshot snapshot) async {
    _initialFen = snapshot.initialFen;
    _actions
      ..clear()
      ..addAll(snapshot.actions);
    _activeSeat = _actions.length.isEven ? RemoteSeat.first : RemoteSeat.second;
  }

  @override
  Future<void> undoActions(int steps) async {
    _actions.removeRange(_actions.length - steps, _actions.length);
    _activeSeat = _actions.length.isEven ? RemoteSeat.first : RemoteSeat.second;
  }

  @override
  Future<void> forceWinner(RemoteSeat winner) async {
    forcedWinner = winner;
  }

  @override
  Future<void> abandon() async {}
}

class _MemoryTransport implements RemoteTransport {
  _MemoryTransport({required this.role});

  @override
  final RemoteRole role;

  _MemoryTransport? peer;
  final StreamController<RemoteTransportEvent> _events =
      StreamController<RemoteTransportEvent>.broadcast(sync: true);
  RemoteConnectionState _state = RemoteConnectionState.idle;
  bool _connected = false;
  bool _closed = false;

  @override
  RemoteTransportKind get kind => RemoteTransportKind.lan;

  @override
  RemoteConnectionState get state => _state;

  @override
  bool get isConnected => _connected;

  @override
  Stream<RemoteTransportEvent> get events => _events.stream;

  @override
  Future<void> startHost(RemoteHostOptions options) async {
    _setState(RemoteConnectionState.listening);
  }

  @override
  Future<List<RemoteEndpoint>> discover({
    Duration timeout = const Duration(seconds: 5),
    String? localAddress,
  }) async {
    return const <RemoteEndpoint>[RemoteEndpoint(id: 'host', label: 'host')];
  }

  @override
  Future<void> join(RemoteEndpoint endpoint) async {
    final _MemoryTransport remote = peer!;
    _connected = true;
    remote._connected = true;
    _setState(RemoteConnectionState.negotiating);
    remote._setState(RemoteConnectionState.negotiating);
    remote._events.add(
      const RemoteTransportConnected(RemoteEndpoint(id: 'join', label: 'join')),
    );
    _events.add(RemoteTransportConnected(endpoint));
  }

  @override
  Future<void> reconnect() =>
      join(const RemoteEndpoint(id: 'host', label: 'host'));

  @override
  Future<void> send(Uint8List bytes) async {
    if (!_connected) {
      throw StateError('not connected');
    }
    peer!._events.add(RemoteTransportData(Uint8List.fromList(bytes)));
  }

  void inject(Uint8List bytes) {
    _events.add(RemoteTransportData(Uint8List.fromList(bytes)));
  }

  void forceDisconnect(String reason) {
    if (!_connected) {
      return;
    }
    _connected = false;
    peer!._connected = false;
    _setState(RemoteConnectionState.reconnecting);
    peer!._setState(RemoteConnectionState.reconnecting);
    _events.add(RemoteTransportDisconnected(reason: reason));
    peer!._events.add(RemoteTransportDisconnected(reason: reason));
  }

  @override
  Future<void> disconnectPeer({
    required String reason,
    bool expected = false,
  }) async {
    if (!_connected) {
      return;
    }
    _connected = false;
    peer!._connected = false;
    _events.add(
      RemoteTransportDisconnected(reason: reason, expected: expected),
    );
    peer!._events.add(RemoteTransportDisconnected(reason: reason));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _connected = false;
    _setState(RemoteConnectionState.ended);
    await _events.close();
  }

  void _setState(RemoteConnectionState next) {
    _state = next;
    _events.add(RemoteTransportStateChanged(next));
  }
}
