// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_platform.dart';

void main() {
  tearDown(() {
    GameRegistry.instance.resetForTesting();
  });

  test('GameRegistry notifies listeners on selection change', () {
    final GameRegistry registry = GameRegistry.instance;
    const GameId first = GameId('listener_first');
    const GameId second = GameId('listener_second');
    registry
      ..register(_ListenerModule(first, hiveTypeIdMin: 400, hiveTypeIdMax: 410))
      ..register(
        _ListenerModule(second, hiveTypeIdMin: 411, hiveTypeIdMax: 420),
      )
      ..select(first);

    int notifications = 0;
    void onChange() {
      notifications++;
    }

    registry.addListener(onChange);
    addTearDown(() => registry.removeListener(onChange));

    registry.select(second);
    expect(registry.currentId, second);
    expect(notifications, 1);

    registry.select(second);
    expect(notifications, 1, reason: 'Re-selecting must not re-notify');

    registry.select(first);
    expect(registry.currentId, first);
    expect(notifications, 2);
  });

  test('GameRegistry resets sessions across selections', () {
    final GameRegistry registry = GameRegistry.instance;
    const GameId id = GameId('listener_session');
    final _ListenerModule module = _ListenerModule(
      id,
      hiveTypeIdMin: 421,
      hiveTypeIdMax: 430,
    );
    registry
      ..register(module)
      ..select(id);

    final GameSessionHandle a = module.startSession();
    addTearDown(a.dispose);
    final GameSessionHandle b = module.startSession();
    addTearDown(b.dispose);

    expect(identical(a, b), isFalse);
  });
}

class _ListenerModule extends GameModule {
  _ListenerModule(
    this._id, {
    required int hiveTypeIdMin,
    required int hiveTypeIdMax,
  }) : _hiveTypeIdMin = hiveTypeIdMin,
       _hiveTypeIdMax = hiveTypeIdMax;

  final GameId _id;
  final int _hiveTypeIdMin;
  final int _hiveTypeIdMax;

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
    hiveTypeIdMin: _hiveTypeIdMin,
    hiveTypeIdMax: _hiveTypeIdMax,
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
  GameSessionHandle startSession() => _ListenerSession(_id);
}

class _ListenerSession extends StaticGameSession implements GameSessionHandle {
  _ListenerSession(GameId id)
    : super(
        GameStateSnapshot(
          gameId: id,
          activeSeat: PlayerSeat.first,
          outcome: const GameOutcome.ongoing(),
        ),
      );
}
