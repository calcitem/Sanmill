// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/remote_play/lan_transport.dart';
import 'package:sanmill/remote_play/remote_match_coordinator.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/remote_play/remote_transport.dart';

void main() {
  test('real LAN coordinators synchronize a full match lifecycle', () async {
    final LanTransport hostTransport = LanTransport(
      role: RemoteRole.host,
      enableDiscoveryResponder: false,
    );
    final LanTransport joinTransport = LanTransport(role: RemoteRole.join);
    final _IntegrationGame hostGame = _IntegrationGame();
    final _IntegrationGame joinGame = _IntegrationGame();
    final RemoteMatchCoordinator host = RemoteMatchCoordinator(
      transport: hostTransport,
      game: hostGame,
      localPeer: _peer('loopback-host'),
      reconnectTimeout: const Duration(seconds: 8),
    );
    final RemoteMatchCoordinator join = RemoteMatchCoordinator(
      transport: joinTransport,
      game: joinGame,
      localPeer: _peer('loopback-join'),
      reconnectTimeout: const Duration(seconds: 8),
    );
    addTearDown(join.dispose);
    addTearDown(host.dispose);

    final Future<RemotePeerApprovalRequested> approval = host.events
        .where((RemoteMatchEvent event) => event is RemotePeerApprovalRequested)
        .cast<RemotePeerApprovalRequested>()
        .first;
    await host.startHost(
      options: const RemoteHostOptions(
        bindAddress: '127.0.0.1',
        port: 0,
        advertisedLabel: 'Integration host',
      ),
      ruleSettings: const <String, Object?>{'piecesCount': 12, 'mayFly': true},
      initialFen: 'twelve-men-start',
      hostPlaysFirst: true,
    );
    final RemoteEndpoint endpoint = RemoteEndpoint(
      id: '127.0.0.1:${hostTransport.serverSocket!.port}',
      label: 'loopback',
      address: '127.0.0.1',
      port: hostTransport.serverSocket!.port,
    );
    final Future<RemoteMatchReady> firstHostReady = _nextReady(host);
    final Future<RemoteMatchReady> firstJoinReady = _nextReady(join);
    await join.join(endpoint);
    expect((await approval).peer.peerId, 'loopback-join');
    await host.approvePeer(accepted: true);
    await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
      firstHostReady,
      firstJoinReady,
    ]).timeout(const Duration(seconds: 3));

    expect(join.config!.ruleSettings, host.config!.ruleSettings);
    expect(join.config!.initialFen, 'twelve-men-start');
    expect(await host.submitLocalAction('place:a1'), isTrue);
    await _waitUntil(() => join.revision == 1);
    expect(await join.submitLocalAction('place:b2'), isTrue);
    await _waitUntil(() => host.revision == 2 && join.revision == 2);
    expect(joinGame.fen, hostGame.fen);
    expect(host.revision, 2);

    final Future<RemoteTakeBackApprovalRequested> takeBackApproval = join.events
        .where(
          (RemoteMatchEvent event) => event is RemoteTakeBackApprovalRequested,
        )
        .cast<RemoteTakeBackApprovalRequested>()
        .first;
    final Future<bool> takeBack = host.requestTakeBack(1);
    final RemoteTakeBackApprovalRequested takeBackRequest =
        await takeBackApproval;
    await join.respondToTakeBack(
      requestId: takeBackRequest.requestId,
      steps: takeBackRequest.steps,
      accepted: true,
    );
    expect(await takeBack.timeout(const Duration(seconds: 2)), isTrue);
    await _eventLoop();
    expect(joinGame.fen, hostGame.fen);

    final Future<RemoteMatchReady> resumedHost = _nextReady(
      host,
      resumed: true,
    );
    final Future<RemoteMatchReady> resumedJoin = _nextReady(
      join,
      resumed: true,
    );
    await joinTransport.disconnectPeer(reason: 'injected socket loss');
    await Future.wait<RemoteMatchReady>(<Future<RemoteMatchReady>>[
      resumedHost,
      resumedJoin,
    ]).timeout(const Duration(seconds: 6));
    expect(joinGame.fen, hostGame.fen);
    expect(join.revision, host.revision);

    final String previousRound = host.config!.roundId;
    final Future<RemoteRestartApprovalRequested> restartApproval = host.events
        .where(
          (RemoteMatchEvent event) => event is RemoteRestartApprovalRequested,
        )
        .cast<RemoteRestartApprovalRequested>()
        .first;
    final Future<bool> restart = join.requestRestart();
    final RemoteRestartApprovalRequested restartRequest = await restartApproval;
    await host.respondToRestart(
      requestId: restartRequest.requestId,
      accepted: true,
    );
    expect(await restart.timeout(const Duration(seconds: 3)), isTrue);
    expect(host.config!.roundId, isNot(previousRound));
    expect(join.config!.ruleSettings, host.config!.ruleSettings);
    expect(host.meta!.localSeat, RemoteSeat.first);
    expect(join.meta!.localSeat, RemoteSeat.second);
    expect(joinGame.fen, hostGame.fen);

    final Future<RemoteOpponentResigned> resigned = host.events
        .where((RemoteMatchEvent event) => event is RemoteOpponentResigned)
        .cast<RemoteOpponentResigned>()
        .first;
    await join.resign();
    await resigned.timeout(const Duration(seconds: 2));
    expect(hostGame.forcedWinner, RemoteSeat.first);
    expect(joinGame.forcedWinner, RemoteSeat.first);
  });
}

Future<RemoteMatchReady> _nextReady(
  RemoteMatchCoordinator coordinator, {
  bool? resumed,
}) {
  return coordinator.events
      .where(
        (RemoteMatchEvent event) =>
            event is RemoteMatchReady &&
            (resumed == null || event.resumed == resumed),
      )
      .cast<RemoteMatchReady>()
      .first;
}

RemotePeerInfo _peer(String id) {
  return RemotePeerInfo(
    peerId: id,
    label: id,
    platform: 'test',
    appVersion: '2.0.0',
    appBuild: '2',
  );
}

Future<void> _eventLoop() => Future<void>.delayed(Duration.zero);

Future<void> _waitUntil(bool Function() predicate) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Remote integration condition timed out.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _IntegrationGame implements RemoteGameAdapter {
  String _initialFen = '';
  final List<String> _actions = <String>[];
  RemoteSeat _activeSeat = RemoteSeat.first;
  RemoteSeat? forcedWinner;
  bool abandoned = false;

  @override
  RemoteSeat get activeSeat => _activeSeat;

  @override
  String get fen => <String>[_initialFen, ..._actions].join('|');

  @override
  Future<void> configure(RemoteMatchConfig config) async {
    _initialFen = config.initialFen;
    _actions.clear();
    _activeSeat = RemoteSeat.first;
    forcedWinner = null;
    abandoned = false;
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
  Future<void> abandon() async {
    abandoned = true;
  }
}
