// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_platform.dart';
import 'package:sanmill/games/demo_probe/demo_probe_game_module.dart';
import 'package:sanmill/games/demo_probe/demo_probe_notation_port.dart';
import 'package:sanmill/games/demo_probe/demo_probe_rules_port.dart';

void main() {
  test('GameFeatureFlags supports legacy booleans and capabilities', () {
    const GameFeatureFlags flags = GameFeatureFlags(
      supportsAi: true,
      capabilities: <GameCapability>{GameCapability.analysis},
    );

    expect(flags.supports(GameCapability.ai), isTrue);
    expect(flags.supports(GameCapability.analysis), isTrue);
    expect(flags.supports(GameCapability.lan), isFalse);
  });

  test('StaticGameSession exposes stable initial state', () {
    const GameId id = GameId('session_test');
    final StaticGameSession session = StaticGameSession(
      const GameStateSnapshot(
        gameId: id,
        activeSeat: PlayerSeat.first,
        outcome: GameOutcome.ongoing(),
      ),
    );

    expect(session.state.value.gameId, id);
    expect(session.outcome.isTerminal, isFalse);

    session.dispose();
  });

  test('GameRegistry rejects overlapping Hive typeId ranges in debug mode', () {
    final GameRegistry registry = GameRegistry.instance;
    const GameId firstId = GameId('range_test_first');
    const GameId secondId = GameId('range_test_second');

    registry.register(_FakeModule(firstId, 300, 310));

    expect(
      () => registry.register(_FakeModule(secondId, 305, 315)),
      throwsA(isA<AssertionError>()),
    );
  });

  test('NativeEngineRouter dispatches by game id', () async {
    const GameId id = GameId('engine_test');
    final NativeEngineRouter router = NativeEngineRouter();
    final _FakeEnginePort port = _FakeEnginePort();
    const GameEngineConfig config = GameEngineConfig(gameId: id);

    router.register(id, port);
    await router.start(config);

    expect(port.startedWith, config);
    expect(router.eventsFor(id), isA<Stream<EngineEvent>>());
  });

  test('DemoProbeGameModule provides a real session handle', () {
    final DemoProbeGameModule module = DemoProbeGameModule();
    final GameSessionHandle session = module.startSession();

    expect(session.state.value.gameId, GameId.demoProbe);
    expect(session.state.value.phase, 'play');

    session.dispose();
  });

  test('DemoProbeGameModule is the board-game module template', () {
    final DemoProbeGameModule module = DemoProbeGameModule();

    expect(module.boardGeometry.points, isNotEmpty);
    expect(module.boardGeometry.edges, isNotEmpty);
    expect(module.rulesPort, isA<DemoProbeRulesPort>());
    expect(module.notationPort, isA<DemoProbeNotationPort>());
    expect(module.enginePort, isNull);
    expect(module.persistenceScope.gameId, GameId.demoProbe);
  });

  test('DemoProbeRulesPort detects tic-tac-toe wins', () {
    final DemoProbeRulesPort rules = DemoProbeRulesPort();

    rules
      ..apply(const GameAction(type: 'place', to: BoardCoordinate(0)))
      ..apply(const GameAction(type: 'place', to: BoardCoordinate(3)))
      ..apply(const GameAction(type: 'place', to: BoardCoordinate(1)))
      ..apply(const GameAction(type: 'place', to: BoardCoordinate(4)))
      ..apply(const GameAction(type: 'place', to: BoardCoordinate(2)));

    expect(rules.snapshot.outcome.kind, GameOutcomeKind.win);
    expect(rules.snapshot.outcome.winner, PlayerSeat.first);
    expect(rules.legalActions, isEmpty);
  });

  test('DemoProbeNotationPort encodes and decodes moves', () {
    const DemoProbeNotationPort notation = DemoProbeNotationPort();
    const List<GameAction> actions = <GameAction>[
      GameAction(type: 'place', to: BoardCoordinate(0)),
      GameAction(type: 'place', to: BoardCoordinate(8)),
    ];

    final String encoded = notation.encodeMoveList(actions);
    final List<GameAction> decoded = notation.decodeMoveList(encoded);

    expect(encoded, '0 8');
    expect(decoded.map((GameAction action) => action.to!.value), <int>[0, 8]);
  });
}

class _FakeModule extends GameModule {
  _FakeModule(this._id, this._min, this._max);

  final GameId _id;
  final int _min;
  final int _max;

  @override
  BoardGeometry get boardGeometry =>
      const BoardGeometry(points: <BoardPoint>[], edges: <BoardEdge>[]);

  @override
  GameFeatureFlags get features => const GameFeatureFlags();

  @override
  GameModuleMetadata get metadata =>
      GameModuleMetadata(id: _id, shortLabel: _id.value);

  @override
  GamePersistenceScope get persistenceScope => GamePersistenceScope(
    gameId: _id,
    hiveTypeIdMin: _min,
    hiveTypeIdMax: _max,
  );

  @override
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  }) {
    return SizedBox(key: key);
  }

  @override
  GameSessionHandle startSession() => _FakeSession(_id);
}

class _FakeSession extends StaticGameSession implements GameSessionHandle {
  _FakeSession(GameId id)
    : super(
        GameStateSnapshot(
          gameId: id,
          activeSeat: PlayerSeat.first,
          outcome: const GameOutcome.ongoing(),
        ),
      );
}

class _FakeEnginePort implements EnginePort {
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();

  GameEngineConfig? startedWith;

  @override
  Future<void> analyze(EngineSearchRequest request) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }

  @override
  Stream<String> get eventLines => const Stream<String>.empty();

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> search(EngineSearchRequest request) async {}

  @override
  void sendRawCommand(String command) {
    assert(command.isNotEmpty, 'command must not be empty');
  }

  @override
  Future<void> setPosition(EnginePosition position) async {}

  @override
  Future<void> start([GameEngineConfig? config]) async {
    startedWith = config;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateGeneralOptions() async {}

  @override
  Future<void> updateRuleOptions() async {}
}
