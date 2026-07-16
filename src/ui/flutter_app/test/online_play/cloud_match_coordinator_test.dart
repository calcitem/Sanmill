// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/online_play/cloud_match_coordinator.dart';
import 'package:sanmill/online_play/online_models.dart';
import 'package:sanmill/online_play/online_room_api.dart';
import 'package:sanmill/online_play/online_session_store.dart';
import 'package:sanmill/online_play/online_socket_client.dart';
import 'package:sanmill/remote_play/remote_match_controller.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  test('waits for an opponent and commits an authoritative action', () async {
    final OnlineRoomSession session = _session(status: 'waiting');
    final _FakeSocket socket = _FakeSocket();
    final _MemoryStore store = _MemoryStore();
    final _FakeGame game = _FakeGame();
    socket.onConnect = () => socket.emit(_welcome(session));
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: onlineMillGameDefinition,
      session: session,
      roomApi: _FakeApi(),
      socket: socket,
      game: game,
      sessionStore: store,
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();
    expect(coordinator.state, RemoteConnectionState.listening);
    expect(store.value, isNotNull);

    socket.emit(<String, Object?>{
      ..._stateEvent(
        session,
        type: 'opponentJoined',
        status: 'active',
        revision: 1,
      ),
      'connected': true,
    });
    await _flushEvents();
    expect(coordinator.state, RemoteConnectionState.ready);
    expect(coordinator.isLocalTurn, isTrue);

    final Future<bool> submitted = coordinator.submitLocalAction('a7');
    final Map<String, Object?> command = socket.sent.single;
    expect(command, containsPair('expectedSeq', 1));
    expect(command, containsPair('type', 'action'));
    socket.emit(
      _stateEvent(
        session,
        status: 'active',
        revision: 2,
        actions: const <String>['a7'],
        commandId: command['commandId']! as String,
      ),
    );

    expect(await submitted, isTrue);
    expect(coordinator.revision, 2);
    expect(coordinator.actionLog, const <String>['a7']);
    expect(game.snapshots.last.actions, const <String>['a7']);
  });

  test('rejects stale action and restores the server snapshot', () async {
    final OnlineRoomSession session = _session(status: 'active');
    final _FakeSocket socket = _FakeSocket();
    final _FakeGame game = _FakeGame();
    socket.onConnect = () => socket.emit(_welcome(session));
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: onlineMillGameDefinition,
      session: session,
      roomApi: _FakeApi(),
      socket: socket,
      game: game,
      sessionStore: _MemoryStore(),
    );
    addTearDown(coordinator.dispose);
    final List<RemoteMatchEvent> events = <RemoteMatchEvent>[];
    final StreamSubscription<RemoteMatchEvent> subscription = coordinator.events
        .listen(events.add);
    addTearDown(subscription.cancel);

    await coordinator.start();
    final Future<bool> submitted = coordinator.submitLocalAction('a7');
    final String commandId = socket.sent.single['commandId']! as String;
    socket.emit(<String, Object?>{
      ..._stateEvent(session, status: 'active', revision: 0),
      'type': 'error',
      'error': 'stale_revision',
      'commandId': commandId,
    });

    expect(await submitted, isFalse);
    await _flushEvents();
    expect(
      events.whereType<RemoteMatchActionRejected>().single.reason,
      'stale_revision',
    );
    expect(game.snapshots.last.revision, 0);
  });

  test('keeps recovery credentials after a non-terminal dispose', () async {
    final OnlineRoomSession session = _session(status: 'active');
    final _FakeSocket socket = _FakeSocket();
    final _MemoryStore store = _MemoryStore();
    socket.onConnect = () => socket.emit(_welcome(session));
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: onlineMillGameDefinition,
      session: session,
      roomApi: _FakeApi(),
      socket: socket,
      game: _FakeGame(),
      sessionStore: store,
    );

    await coordinator.start();
    await coordinator.dispose();

    expect(store.value?.seatToken, session.seatToken);
    expect(store.deleted, isFalse);
  });

  test(
    'keeps credentials when the online service is temporarily unavailable',
    () async {
      final OnlineRoomSession session = _session(status: 'active');
      final _MemoryStore store = _MemoryStore();
      final _FakeApi api = _FakeApi()
        ..ticketFailure = OnlineFailure.serviceUnavailable;
      final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
        definition: onlineMillGameDefinition,
        session: session,
        roomApi: api,
        socket: _FakeSocket(),
        game: _FakeGame(),
        sessionStore: store,
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.start(),
        throwsA(isA<OnlineApiException>()),
      );
      expect(coordinator.state, RemoteConnectionState.error);
      expect(store.deleted, isFalse);
      expect(store.value, isNotNull);
    },
  );

  test('deletes credentials after terminal authorization failure', () async {
    final _MemoryStore store = _MemoryStore();
    final _FakeApi api = _FakeApi()..ticketFailure = OnlineFailure.unauthorized;
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: onlineMillGameDefinition,
      session: _session(status: 'active'),
      roomApi: api,
      socket: _FakeSocket(),
      game: _FakeGame(),
      sessionStore: store,
    );
    addTearDown(coordinator.dispose);

    await expectLater(coordinator.start(), throwsA(isA<OnlineApiException>()));
    expect(store.deleted, isTrue);
  });

  test('locks actions while the opponent is disconnected', () async {
    final OnlineRoomSession session = _session(status: 'active');
    final _FakeSocket socket = _FakeSocket();
    socket.onConnect = () => socket.emit(_welcome(session));
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: onlineMillGameDefinition,
      session: session,
      roomApi: _FakeApi(),
      socket: socket,
      game: _FakeGame(),
      sessionStore: _MemoryStore(),
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();
    socket.emit(<String, Object?>{
      'type': 'opponentConnection',
      'connected': false,
      'seq': 0,
    });
    await _flushEvents();
    expect(coordinator.state, RemoteConnectionState.listening);
    expect(await coordinator.submitLocalAction('a7'), isFalse);

    socket.emit(<String, Object?>{
      'type': 'opponentConnection',
      'connected': true,
      'seq': 0,
    });
    await _flushEvents();
    expect(coordinator.state, RemoteConnectionState.ready);
  });

  test(
    'reconnects with a fresh ticket and marks the session resumed',
    () async {
      final OnlineRoomSession session = _session(status: 'active');
      final _FakeSocket socket = _FakeSocket();
      final _FakeApi api = _FakeApi();
      final List<RemoteMatchReady> readyEvents = <RemoteMatchReady>[];
      socket.onConnect = () => socket.emit(_welcome(session));
      final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
        definition: onlineMillGameDefinition,
        session: session,
        roomApi: api,
        socket: socket,
        game: _FakeGame(),
        sessionStore: _MemoryStore(),
        reconnectWindow: const Duration(seconds: 1),
      );
      addTearDown(coordinator.dispose);
      final StreamSubscription<RemoteMatchEvent> subscription = coordinator
          .events
          .listen((RemoteMatchEvent event) {
            if (event is RemoteMatchReady) {
              readyEvents.add(event);
            }
          });
      addTearDown(subscription.cancel);

      await coordinator.start();
      socket.connected = false;
      socket.controller.add(const OnlineSocketClosed(1006, 'network'));
      await _flushEvents();
      await _flushEvents();

      expect(coordinator.state, RemoteConnectionState.ready);
      expect(api.tickets, 2);
      expect(readyEvents.last.resumed, isTrue);
    },
  );

  test(
    'restores an opponent control request from a welcome snapshot',
    () async {
      final OnlineRoomSession session = _session(status: 'active');
      final _FakeSocket socket = _FakeSocket();
      socket.onConnect = () => socket.emit(<String, Object?>{
        ..._welcome(session),
        'pendingControl': <String, Object?>{
          'kind': 'takeBack',
          'requestId': 'takeback-restored',
          'requester': 'second',
          'steps': 2,
          'expiresAt': DateTime.now().millisecondsSinceEpoch + 30000,
        },
      });
      final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
        definition: onlineMillGameDefinition,
        session: session,
        roomApi: _FakeApi(),
        socket: socket,
        game: _FakeGame(),
        sessionStore: _MemoryStore(),
      );
      addTearDown(coordinator.dispose);
      final List<RemoteTakeBackApprovalRequested> requests =
          <RemoteTakeBackApprovalRequested>[];
      final StreamSubscription<RemoteMatchEvent> subscription = coordinator
          .events
          .listen((RemoteMatchEvent event) {
            if (event is RemoteTakeBackApprovalRequested) {
              requests.add(event);
            }
          });
      addTearDown(subscription.cancel);

      await coordinator.start();
      expect(requests, hasLength(1));
      expect(requests.single.requestId, 'takeback-restored');
      expect(requests.single.steps, 2);

      socket.emit(<String, Object?>{
        'type': 'controlRequest',
        'kind': 'takeBack',
        'requestId': 'takeback-restored',
        'steps': 2,
        'seq': 0,
      });
      await _flushEvents();
      expect(requests, hasLength(1));
    },
  );
}

OnlineRoomSession _session({required String status}) {
  final String roomId = List<String>.filled(22, 'A').join();
  final String seatToken = List<String>.filled(43, 'S').join();
  final String inviteToken = List<String>.filled(43, 'I').join();
  final Map<String, Object?> options = onlineOptionsFromRuleSettings(
    const RuleSettings(),
  );
  return OnlineRoomSession(
    serviceBaseUri: Uri.parse('https://online.example'),
    room: OnlineRoomDescriptor(
      roomId: roomId,
      appId: onlineAppId,
      gameId: onlineMillGameId,
      rulesetId: onlineMillRulesetId,
      ruleOptions: options,
      creatorSeat: RemoteSeat.first,
      status: status,
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2027, 1, 2),
    ),
    role: RemoteRole.host,
    localSeat: RemoteSeat.first,
    seatToken: seatToken,
    snapshot: const RemoteStateSnapshot(
      revision: 0,
      initialFen: 'initial',
      actions: <String>[],
      resultFen: 'initial',
    ),
    inviteUri: Uri.parse('https://online.example/invite/$roomId#$inviteToken'),
  );
}

Map<String, Object?> _welcome(OnlineRoomSession session) => <String, Object?>{
  ..._stateEvent(
    session,
    type: 'welcome',
    status: session.room.status,
    revision: session.snapshot.revision,
  ),
  'room': session.room.toJson(),
  'seat': session.localSeat.name,
  'opponentConnected': session.room.isActive,
};

Map<String, Object?> _stateEvent(
  OnlineRoomSession session, {
  String type = 'state',
  required String status,
  required int revision,
  List<String> actions = const <String>[],
  String? commandId,
}) => <String, Object?>{
  'type': type,
  'seq': revision,
  'status': status,
  'commandId': ?commandId,
  'snapshot': <String, Object?>{
    'revision': revision,
    'initialFen': session.snapshot.initialFen,
    'actions': actions,
    'resultFen': actions.isEmpty ? 'initial' : 'after',
  },
};

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _FakeApi implements OnlineRoomApi {
  int tickets = 0;
  OnlineFailure? ticketFailure;

  @override
  Future<String> issueTicket(OnlineRoomSession session) async {
    final OnlineFailure? failure = ticketFailure;
    if (failure != null) {
      throw OnlineApiException(failure);
    }
    return 'ticket-${tickets++}';
  }

  @override
  Future<void> cancelRoom(OnlineRoomSession session) async {}

  @override
  Future<OnlineRoomSession> createRoom({
    required Map<String, Object?> ruleOptions,
    required OnlineSidePreference sidePreference,
  }) => throw UnimplementedError();

  @override
  Future<OnlineRoomSession> joinRoom(OnlineInvite invite) =>
      throw UnimplementedError();
}

class _FakeSocket implements OnlineSocketClient {
  final StreamController<OnlineSocketEvent> controller =
      StreamController<OnlineSocketEvent>.broadcast(sync: true);
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  void Function()? onConnect;
  bool connected = false;

  @override
  Stream<OnlineSocketEvent> get events => controller.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect(Uri uri) async {
    connected = true;
    scheduleMicrotask(() => onConnect?.call());
  }

  void emit(Map<String, Object?> value) {
    controller.add(OnlineSocketMessage(value));
  }

  @override
  void send(Map<String, Object?> message) {
    sent.add(Map<String, Object?>.of(message));
  }

  @override
  Future<void> close() async {
    connected = false;
    await controller.close();
  }
}

class _MemoryStore implements OnlineSessionStore {
  OnlineRoomSession? value;
  bool deleted = false;

  @override
  Future<void> delete() async {
    deleted = true;
    value = null;
  }

  @override
  Future<OnlineRoomSession?> read() async => value;

  @override
  Future<void> write(OnlineRoomSession session) async {
    value = session;
  }
}

class _FakeGame implements RemoteGameAdapter {
  final List<RemoteStateSnapshot> snapshots = <RemoteStateSnapshot>[];
  RemoteMatchConfig? configured;
  RemoteSeat seat = RemoteSeat.first;

  @override
  RemoteSeat get activeSeat => seat;

  @override
  String get fen => snapshots.isEmpty ? 'initial' : snapshots.last.resultFen;

  @override
  Future<void> configure(RemoteMatchConfig config) async {
    configured = config;
    seat = RemoteSeat.first;
  }

  @override
  Future<bool> applyAction(String notation) async => true;

  @override
  Future<void> restoreSnapshot(RemoteStateSnapshot snapshot) async {
    snapshots.add(snapshot);
    seat = snapshot.actions.length.isEven
        ? RemoteSeat.first
        : RemoteSeat.second;
  }

  @override
  Future<void> undoActions(int steps) async {}

  @override
  Future<void> forceWinner(RemoteSeat winner) async {}

  @override
  Future<void> abandon() async {}
}
