// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';

void main() {
  group('NativeMillGameSession', () {
    test('applies legal actions and emits state + move events', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final sub = session.events.listen(events.add);
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
    });

    test('rejects illegal actions without mutating state', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final sub = session.events.listen(events.add);
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

      await session.apply(rulesPort.placeA7);
      await session.undo();
      expect(rulesPort.undoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.first);

      await session.redo();
      expect(rulesPort.redoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.second);
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
}
