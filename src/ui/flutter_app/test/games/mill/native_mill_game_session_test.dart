// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

void main() {
  group('NativeMillGameSession', () {
    test('applies legal actions and emits state + move events', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      final GameAction action = rulesPort.placeA7;
      await session.apply(action);
      await Future<void>.delayed(Duration.zero);

      expect(rulesPort.applyCount, 1);
      expect(session.state.value.lastAction, same(action));
      expect(session.state.value.activeSeat, PlayerSeat.second);
      expect(
        events.map((GameSessionEvent e) => e.type),
        containsAllInOrder(<String>[
          MillEventTypes.stateChanged,
          MillEventTypes.moveApplied,
        ]),
      );
      expect(events.last.payload['mover'], PlayerSeat.first.name);
      expect(events.last.payload['move'], 'a7');
    });

    test('rejects illegal actions without mutating state', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      final GameStateSnapshot before = session.state.value;
      await session.apply(
        const GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'z9'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(rulesPort.applyCount, 0);
      expect(session.state.value, same(before));
      expect(events.single.type, MillEventTypes.moveRejected);
    });

    test('undo and redo forward to the rules port', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);
      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      await session.apply(rulesPort.placeA7);
      await session.undo();
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.undoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.first);
      expect(
        events.map((GameSessionEvent e) => e.type),
        contains(MillEventTypes.undoApplied),
      );

      await session.redo();
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.redoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.second);
      expect(
        events.map((GameSessionEvent e) => e.type),
        contains(MillEventTypes.redoApplied),
      );
    });

    test('terminal outcomes expose no legal actions', () {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        initial: const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.none,
          outcome: GameOutcome.draw(),
          phase: 'gameOver',
        ),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      expect(session.outcome.isTerminal, isTrue);
      expect(session.legalActions, isEmpty);
    });

    test(
      'searchBestAction returns null when no search bestMove is emitted',
      () async {
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);

        expect(await session.searchBestAction(), isNull);
        expect(await session.searchAndApplyBestAction(), isNull);
        expect(rulesPort.applyCount, 0);
      },
    );

    test('stores LAN metadata for native LAN turn checks', () {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      const LanSessionMeta meta = LanSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: false,
      );
      session.lanMeta = meta;

      expect(session.lanMeta, meta);
    });
  });
}

class _FakeNativeMillRulesPort implements NativeMillRulesPort {
  _FakeNativeMillRulesPort({GameStateSnapshot? initial})
    : _snapshot = initial ?? _initialSnapshot;

  static const GameStateSnapshot _initialSnapshot = GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: GameOutcome.ongoing(),
    phase: 'placing',
  );

  final GameAction placeA7 = const GameAction(
    type: MillActionTypes.place,
    payload: <String, Object?>{'move': 'a7'},
  );

  GameStateSnapshot _snapshot;
  int applyCount = 0;
  int undoCount = 0;
  int redoCount = 0;
  bool disposed = false;

  @override
  int get undoDepth => applyCount - undoCount + redoCount;

  @override
  int get redoDepth => undoCount - redoCount;

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  List<GameAction> get legalActions => _snapshot.outcome.isTerminal
      ? const <GameAction>[]
      : <GameAction>[placeA7];

  @override
  bool isLegal(GameAction action) =>
      action.type == placeA7.type &&
      action.payload['move'] == placeA7.payload['move'];

  @override
  GameStateSnapshot apply(GameAction action) {
    applyCount++;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      lastAction: action,
    );
    return _snapshot;
  }

  @override
  GameStateSnapshot undo() {
    undoCount++;
    _snapshot = _initialSnapshot;
    return _snapshot;
  }

  @override
  GameStateSnapshot redo() {
    redoCount++;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      lastAction: placeA7,
    );
    return _snapshot;
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  Stream<tgf.EngineEvent> millSearchEvents({required int depth}) {
    return const Stream<tgf.EngineEvent>.empty();
  }

  @override
  GameStateSnapshot setupClear() => _snapshot;

  @override
  GameStateSnapshot setupSetPiece(int node, int owner) => _snapshot;

  @override
  GameStateSnapshot setupSetSide(int side) => _snapshot;

  @override
  GameStateSnapshot setupFinish() => _snapshot;
}
