// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/online_play/cloud_match_coordinator.dart';
import 'package:sanmill/online_play/online_friend_game_page.dart';
import 'package:sanmill/online_play/online_game_registration.dart';
import 'package:sanmill/online_play/online_models.dart';
import 'package:sanmill/online_play/online_room_api.dart';
import 'package:sanmill/online_play/online_session_store.dart';
import 'package:sanmill/online_play/online_socket_client.dart';
import 'package:sanmill/remote_play/remote_match_controller.dart';
import 'package:sanmill/remote_play/remote_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  testWidgets('Mill registration localizes the selected variant name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            final String label = const MillOnlineGameRegistration()
                .variantLabel(
                  context,
                  onlineOptionsFromRuleSettings(const RuleSettings()),
                );
            return Text(label);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('莫里斯九子棋'), findsOneWidget);
  });

  testWidgets('home explains Cloudflare and exposes create and join actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: OnlineFriendGamePage(
          registration: _TestRegistration(),
          service: OnlineServiceConfig(Uri.parse('https://online.example')),
          roomApi: _UnusedApi(),
          sessionStore: _EmptyStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Online friend game'), findsOneWidget);
    expect(find.textContaining('Cloudflare'), findsOneWidget);
    expect(find.byKey(const Key('online_create_game')), findsOneWidget);
    expect(find.byKey(const Key('online_join_game')), findsOneWidget);
    expect(tester.getSemantics(find.textContaining('Cloudflare')), isNotNull);
  });

  testWidgets(
    'create sheet exposes fixed unlimited settings and stable errors',
    (WidgetTester tester) async {
      final _UnusedApi api = _UnusedApi(
        createFailure: OnlineFailure.serviceUnavailable,
      );
      await tester.pumpWidget(_testApp(api: api));
      await tester.pump();

      await tester.tap(find.byKey(const Key('online_create_game')));
      await tester.pumpAndSettle();
      expect(find.text('Friend game settings'), findsOneWidget);
      expect(find.text('Unlimited'), findsOneWidget);
      expect(find.text('Play first'), findsOneWidget);
      expect(find.text('Play second'), findsOneWidget);
      expect(find.text('Random side'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Create a game').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(api.createCalls, 1);
    },
  );

  testWidgets('join sheet rejects malformed invitation links locally', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp(api: _UnusedApi()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('online_join_game')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('online_invite_field')),
      'https://online.example/invite/not-a-room#not-a-token',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();

    expect(find.text('This invite link is invalid.'), findsOneWidget);
  });

  testWidgets('home remains usable with large text in landscape', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _testApp(api: _UnusedApi(), textScaler: const TextScaler.linear(2)),
    );
    await tester.pump();

    expect(find.byKey(const Key('online_create_game')), findsOneWidget);
    expect(find.byKey(const Key('online_join_game')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting page presents the invitation QR and cancellation', (
    WidgetTester tester,
  ) async {
    final OnlineRoomSession session = _waitingSession();
    final _UnusedApi api = _UnusedApi(createdSession: session);
    final _TestRegistration registration = _TestRegistration();
    await tester.pumpWidget(
      _testApp(
        api: api,
        registration: registration,
        socketFactory: () => _WelcomeSocket(session),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('online_create_game')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create a game').last);
    await tester.pumpAndSettle();

    expect(find.text('Waiting for an opponent…'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Copy invite link'), findsOneWidget);
    expect(find.text('Share invite link'), findsOneWidget);
    expect(find.textContaining('Anyone with this link'), findsOneWidget);
    expect(find.text(session.inviteUri.toString()), findsOneWidget);

    final Finder cancel = find.widgetWithText(TextButton, 'Cancel');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(api.cancelCalls, 1);
    expect(registration._coordinator, isNull);
    expect(find.byKey(const Key('online_create_game')), findsOneWidget);
  });
}

Widget _testApp({
  required _UnusedApi api,
  TextScaler textScaler = TextScaler.noScaling,
  _TestRegistration? registration,
  OnlineSocketClientFactory? socketFactory,
}) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: OnlineFriendGamePage(
        registration: registration ?? _TestRegistration(),
        service: OnlineServiceConfig(Uri.parse('https://online.example')),
        roomApi: api,
        sessionStore: _EmptyStore(),
        socketFactory: socketFactory,
      ),
    ),
  );
}

class _EmptyStore implements OnlineSessionStore {
  @override
  Future<void> delete() async {}

  @override
  Future<OnlineRoomSession?> read() async => null;

  @override
  Future<void> write(OnlineRoomSession session) async {}
}

class _UnusedApi implements OnlineRoomApi {
  _UnusedApi({this.createFailure, this.createdSession});

  final OnlineFailure? createFailure;
  final OnlineRoomSession? createdSession;
  int createCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancelRoom(OnlineRoomSession session) async {
    cancelCalls += 1;
  }

  @override
  Future<OnlineRoomSession> createRoom({
    required Map<String, Object?> ruleOptions,
    required OnlineSidePreference sidePreference,
  }) async {
    createCalls += 1;
    final OnlineFailure? failure = createFailure;
    if (failure != null) {
      throw OnlineApiException(failure);
    }
    if (createdSession != null) {
      return createdSession!;
    }
    throw UnimplementedError();
  }

  @override
  Future<String> issueTicket(OnlineRoomSession session) async => 'ticket';

  @override
  Future<OnlineRoomSession> joinRoom(OnlineInvite invite) =>
      throw UnimplementedError();
}

class _TestRegistration implements OnlineGameRegistration {
  CloudMatchCoordinator? _coordinator;

  @override
  OnlineGameDefinition get definition => onlineMillGameDefinition;

  @override
  Map<String, Object?> createRuleOptions() =>
      onlineOptionsFromRuleSettings(const RuleSettings());

  @override
  Widget buildBoard(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> disposeCoordinator() async {
    final CloudMatchCoordinator? coordinator = _coordinator;
    _coordinator = null;
    unawaited(coordinator?.dispose());
  }

  @override
  Future<CloudMatchCoordinator> installCoordinator({
    required OnlineRoomSession session,
    required OnlineRoomApi roomApi,
    required OnlineSocketClient socket,
    required OnlineSessionStore sessionStore,
  }) async {
    final CloudMatchCoordinator coordinator = CloudMatchCoordinator(
      definition: definition,
      session: session,
      roomApi: roomApi,
      socket: socket,
      game: _PageGame(),
      sessionStore: sessionStore,
    );
    _coordinator = coordinator;
    return coordinator;
  }

  @override
  String variantLabel(BuildContext context, Map<String, Object?> ruleOptions) =>
      '9';
}

OnlineRoomSession _waitingSession() {
  final String roomId = List<String>.filled(22, 'A').join();
  final String seatToken = List<String>.filled(43, 'S').join();
  final String inviteToken = List<String>.filled(43, 'I').join();
  return OnlineRoomSession(
    serviceBaseUri: Uri.parse('https://online.example'),
    room: OnlineRoomDescriptor(
      roomId: roomId,
      appId: onlineAppId,
      gameId: onlineMillGameId,
      rulesetId: onlineMillRulesetId,
      ruleOptions: onlineOptionsFromRuleSettings(const RuleSettings()),
      creatorSeat: RemoteSeat.first,
      status: 'waiting',
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2027),
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

class _WelcomeSocket implements OnlineSocketClient {
  _WelcomeSocket(this.session);

  final OnlineRoomSession session;
  final StreamController<OnlineSocketEvent> _events =
      StreamController<OnlineSocketEvent>.broadcast(sync: true);
  bool _connected = false;

  @override
  Stream<OnlineSocketEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Uri uri) async {
    _connected = true;
    scheduleMicrotask(() {
      _events.add(
        OnlineSocketMessage(<String, Object?>{
          'type': 'welcome',
          'seq': 0,
          'status': 'waiting',
          'pendingControl': null,
          'room': session.room.toJson(),
          'seat': 'first',
          'opponentConnected': false,
          'snapshot': session.snapshot.toJson(),
        }),
      );
    });
  }

  @override
  void send(Map<String, Object?> message) {}

  @override
  Future<void> close() async {
    _connected = false;
    await _events.close();
  }
}

class _PageGame implements RemoteGameAdapter {
  @override
  RemoteSeat get activeSeat => RemoteSeat.first;

  @override
  String get fen => 'initial';

  @override
  Future<void> abandon() async {}

  @override
  Future<bool> applyAction(String notation) async => true;

  @override
  Future<void> configure(RemoteMatchConfig config) async {}

  @override
  Future<void> forceWinner(RemoteSeat winner) async {}

  @override
  Future<void> restoreSnapshot(RemoteStateSnapshot snapshot) async {}

  @override
  Future<void> undoActions(int steps) async {}
}
