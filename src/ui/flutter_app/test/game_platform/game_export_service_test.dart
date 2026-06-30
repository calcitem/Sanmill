// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_export.dart';
import 'package:sanmill/game_platform/game_export_service.dart';
import 'package:sanmill/game_platform/game_feature_flags.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_module.dart';
import 'package:sanmill/game_platform/game_module_metadata.dart';
import 'package:sanmill/game_platform/game_persistence_scope.dart';
import 'package:sanmill/game_platform/game_registry.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/game_platform/game_session_handle.dart';
import 'package:sanmill/game_platform/notation_port.dart';

class _TestSession implements GameSessionHandle {
  _TestSession(this._state);

  final ValueNotifier<GameStateSnapshot> _state;

  @override
  Stream<GameSessionEvent> get events => const Stream<GameSessionEvent>.empty();

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {}

  @override
  void dispose() {
    _state.dispose();
  }

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}
}

class _TestNotationPort implements NotationPort {
  const _TestNotationPort();

  @override
  String encodeMoveList(Iterable<GameAction> actions) =>
      actions.map((GameAction a) => a.type).join(',');

  @override
  List<GameAction> decodeMoveList(String notation) => const <GameAction>[];

  @override
  String describeMove(GameAction action) => action.type;

  @override
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions) {
    return '${snapshot.gameId.value}:${encodeMoveList(actions)}';
  }
}

class _TestModule extends GameModule {
  _TestModule({required this.withPort, required this.withData});

  final bool withPort;
  final bool withData;

  @override
  GameModuleMetadata get metadata =>
      const GameModuleMetadata(id: GameId('test'), shortLabel: 'Test');

  @override
  GameFeatureFlags get features => const GameFeatureFlags();

  @override
  Never get boardGeometry => throw UnimplementedError();

  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId('test'),
    hiveTypeIdMin: 999,
    hiveTypeIdMax: 999,
  );

  @override
  GameSessionHandle startSession() => _TestSession(
    ValueNotifier<GameStateSnapshot>(
      const GameStateSnapshot(
        gameId: GameId('test'),
        activeSeat: PlayerSeat.none,
        outcome: GameOutcome.ongoing(),
      ),
    ),
  );

  @override
  NotationPort? get notationPort => withPort ? const _TestNotationPort() : null;

  @override
  GameExportData? buildExportData(
    BuildContext context, {
    required GameSession session,
  }) {
    if (!withData) {
      return null;
    }
    return GameExportData(
      snapshot: session.state.value,
      actions: const <GameAction>[
        GameAction(type: 'a'),
        GameAction(type: 'b'),
      ],
    );
  }

  @override
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  }) => const SizedBox.shrink();
}

void main() {
  testWidgets('buildCurrentExportText returns null without notationPort', (
    WidgetTester tester,
  ) async {
    final GameRegistry registry = GameRegistry.instance;
    registry.resetForTesting();
    registry.register(_TestModule(withPort: false, withData: true));
    registry.select(const GameId('test'));

    final _TestSession session = _TestSession(
      ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId('test'),
          activeSeat: PlayerSeat.none,
          outcome: GameOutcome.ongoing(),
        ),
      ),
    );

    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          expect(
            GameExportService.buildCurrentExportText(context, session: session),
            isNull,
          );
          return const SizedBox.shrink();
        },
      ),
    );
    session.dispose();
  });

  testWidgets('buildCurrentExportText returns null without export data', (
    WidgetTester tester,
  ) async {
    final GameRegistry registry = GameRegistry.instance;
    registry.resetForTesting();
    registry.register(_TestModule(withPort: true, withData: false));
    registry.select(const GameId('test'));

    final _TestSession session = _TestSession(
      ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId('test'),
          activeSeat: PlayerSeat.none,
          outcome: GameOutcome.ongoing(),
        ),
      ),
    );

    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          expect(
            GameExportService.buildCurrentExportText(context, session: session),
            isNull,
          );
          return const SizedBox.shrink();
        },
      ),
    );
    session.dispose();
  });

  testWidgets('buildCurrentExportText exports when port + data present', (
    WidgetTester tester,
  ) async {
    final GameRegistry registry = GameRegistry.instance;
    registry.resetForTesting();
    registry.register(_TestModule(withPort: true, withData: true));
    registry.select(const GameId('test'));

    final _TestSession session = _TestSession(
      ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId('test'),
          activeSeat: PlayerSeat.none,
          outcome: GameOutcome.ongoing(),
        ),
      ),
    );

    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          expect(
            GameExportService.buildCurrentExportText(context, session: session),
            'test:a,b',
          );
          return const SizedBox.shrink();
        },
      ),
    );
    session.dispose();
  });
}
