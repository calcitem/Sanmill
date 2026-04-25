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

    final NativeEngineResponse response = await router.execute(
      const NativeEngineRequest(
        requestId: 'request-1',
        gameId: id,
        command: NativeEngineCommandType.state,
      ),
    );
    expect(response.status, NativeEngineResponseStatus.unsupported);
    expect(response.requestId, 'request-1');
  });

  test('NativeEngineResponse carries game-neutral envelope fields', () {
    const GameId id = GameId('native_envelope_test');
    const NativeEngineRequest request = NativeEngineRequest(
      requestId: 'native-1',
      gameId: id,
      command: NativeEngineCommandType.legalActions,
    );

    final NativeEngineResponse response = NativeEngineResponse.unsupported(
      request,
      reason: 'not wired yet',
    );

    expect(response.gameId, id);
    expect(response.requestId, 'native-1');
    expect(response.isOk, isFalse);
    expect(response.diagnostics, contains('not wired yet'));
  });

  test('BoardGeometry can describe non-graph zones for future games', () {
    const BoardGeometry geometry = BoardGeometry(
      kind: BoardLayoutKind.region,
      points: <BoardPoint>[
        BoardPoint(id: 0, x: 0, y: 0),
        BoardPoint(id: 1, x: 1, y: 1),
      ],
      edges: <BoardEdge>[],
      zones: <BoardZone>[
        BoardZone(id: 'home', pointIds: <int>[0]),
        BoardZone(id: 'target', pointIds: <int>[1]),
      ],
    );

    expect(geometry.kind, BoardLayoutKind.region);
    expect(geometry.zones.map((BoardZone zone) => zone.id), <String>[
      'home',
      'target',
    ]);
  });

  test('BoardDisplaySnapshot projects engine state for UI only', () {
    const GameStateSnapshot state = GameStateSnapshot(
      gameId: GameId('display_test'),
      activeSeat: PlayerSeat.first,
      outcome: GameOutcome.ongoing(),
    );
    const BoardDisplaySnapshot display = BoardDisplaySnapshot(
      gameState: state,
      pieces: <BoardPieceView>[
        BoardPieceView(coordinate: BoardCoordinate(0), owner: PlayerSeat.first),
      ],
      highlights: <BoardHighlight>[
        BoardHighlight(
          coordinate: BoardCoordinate(1),
          kind: BoardHighlightKind.legalTarget,
        ),
      ],
    );

    expect(display.gameState, state);
    expect(display.pieces.single.owner, PlayerSeat.first);
    expect(display.highlights.single.kind, BoardHighlightKind.legalTarget);
  });

  test('GamePersistenceScope owns only its assigned Hive range', () {
    const GamePersistenceScope scope = GamePersistenceScope(
      gameId: GameId('persistence_test'),
      hiveTypeIdMin: 700,
      hiveTypeIdMax: 710,
    );

    expect(scope.ownsHiveTypeId(700), isTrue);
    expect(scope.ownsHiveTypeId(705), isTrue);
    expect(scope.ownsHiveTypeId(711), isFalse);
  });

  test('GameRegistry rejects persistence scope mismatches in debug mode', () {
    final GameRegistry registry = GameRegistry.instance;

    expect(
      () => registry.register(
        _MismatchedPersistenceModule(
          const GameId('module_id'),
          const GameId('scope_id'),
        ),
      ),
      throwsA(isA<AssertionError>()),
    );
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

class _MismatchedPersistenceModule extends _FakeModule {
  _MismatchedPersistenceModule(GameId id, this._scopeId) : super(id, 800, 810);

  final GameId _scopeId;

  @override
  GamePersistenceScope get persistenceScope => GamePersistenceScope(
    gameId: _scopeId,
    hiveTypeIdMin: 800,
    hiveTypeIdMax: 810,
  );
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
  Future<NativeEngineResponse> executeNativeRequest(
    NativeEngineRequest request,
  ) async {
    return NativeEngineResponse.unsupported(request);
  }

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
