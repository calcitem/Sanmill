// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_platform.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/settings_side_effect_coordinator.dart';

void main() {
  tearDown(() {
    GameRegistry.instance.resetForTesting();
  });

  test(
    'settings engine updates are routed through the active module',
    () async {
      final GameRegistry registry = GameRegistry.instance;
      final _CountingEnginePort firstEngine = _CountingEnginePort();
      final _CountingEnginePort secondEngine = _CountingEnginePort();
      const GameId firstId = GameId('settings_first');
      const GameId secondId = GameId('settings_second');
      registry
        ..register(
          _EngineModule(
            firstId,
            firstEngine,
            hiveTypeIdMin: 500,
            hiveTypeIdMax: 510,
          ),
        )
        ..register(
          _EngineModule(
            secondId,
            secondEngine,
            hiveTypeIdMin: 511,
            hiveTypeIdMax: 520,
          ),
        )
        ..select(firstId);

      final SettingsSideEffectCoordinator coordinator =
          SettingsSideEffectCoordinator(
            engineOptionsDebounceDuration: const Duration(milliseconds: 1),
            updateGeneralEngineOptions: () =>
                registry.current.enginePort?.updateGeneralOptions(),
            updateRuleEngineOptions: () =>
                registry.current.enginePort?.updateRuleOptions(),
            recordEvent: (_, _) {},
          );
      addTearDown(coordinator.dispose);

      coordinator.onGeneralSettingsSaved(const GeneralSettings());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(firstEngine.generalUpdates, 1);
      expect(secondEngine.generalUpdates, 0);

      registry.select(secondId);
      coordinator.onRuleSettingsPersisted();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(firstEngine.ruleUpdates, 0);
      expect(secondEngine.ruleUpdates, 1);
    },
  );
}

class _EngineModule extends GameModule {
  _EngineModule(
    this._id,
    this._engine, {
    required int hiveTypeIdMin,
    required int hiveTypeIdMax,
  }) : _hiveTypeIdMin = hiveTypeIdMin,
       _hiveTypeIdMax = hiveTypeIdMax;

  final GameId _id;
  final _CountingEnginePort _engine;
  final int _hiveTypeIdMin;
  final int _hiveTypeIdMax;

  @override
  BoardGeometry get boardGeometry =>
      const BoardGeometry(points: <BoardPoint>[], edges: <BoardEdge>[]);

  @override
  EnginePort? get enginePort => _engine;

  @override
  GameFeatureFlags get features => const GameFeatureFlags(supportsAi: true);

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
  GameSessionHandle startSession() => _EngineSession(_id);
}

class _EngineSession extends StaticGameSession implements GameSessionHandle {
  _EngineSession(GameId id)
    : super(
        GameStateSnapshot(
          gameId: id,
          activeSeat: PlayerSeat.first,
          outcome: const GameOutcome.ongoing(),
        ),
      );
}

class _CountingEnginePort implements EnginePort {
  int generalUpdates = 0;
  int ruleUpdates = 0;

  @override
  Future<void> analyze(EngineSearchRequest request) async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<EngineEvent> get events => const Stream<EngineEvent>.empty();

  @override
  Stream<String> get eventLines => const Stream<String>.empty();

  @override
  Future<NativeEngineResponse> executeNativeRequest(
    NativeEngineRequest request,
  ) async {
    return NativeEngineResponse.unsupported(request);
  }

  @override
  Future<void> search(EngineSearchRequest request) async {}

  @override
  void sendRawCommand(String command) {}

  @override
  Future<void> setPosition(EnginePosition position) async {}

  @override
  Future<void> start([GameEngineConfig? config]) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateGeneralOptions() async {
    generalUpdates++;
  }

  @override
  Future<void> updateRuleOptions() async {
    ruleUpdates++;
  }
}
