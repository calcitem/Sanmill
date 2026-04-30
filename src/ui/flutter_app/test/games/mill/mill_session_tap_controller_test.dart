// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_session_tap_controller.dart';

void main() {
  group('MillSessionTapController', () {
    test('applies a single-tap place action', () async {
      const GameAction placeA7 = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'a7'},
      );
      final _FakeSession session = _FakeSession(<GameAction>[placeA7]);
      final MillSessionTapController controller = MillSessionTapController();

      final MillSessionTapResult result = await controller.tap(
        session: session,
        tappedLabel: 'a7',
      );

      expect(result.status, MillSessionTapStatus.applied);
      expect(result.action, same(placeA7));
      expect(session.appliedActions, <GameAction>[placeA7]);
      expect(controller.selectedFrom, isNull);
    });

    test('selects source then applies a two-tap move', () async {
      const GameAction move = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{'move': 'd7-g7'},
      );
      final _FakeSession session = _FakeSession(<GameAction>[move]);
      final MillSessionTapController controller = MillSessionTapController();

      final MillSessionTapResult first = await controller.tap(
        session: session,
        tappedLabel: 'd7',
      );
      expect(first.status, MillSessionTapStatus.selectedSource);
      expect(controller.selectedFrom, 'd7');
      expect(session.appliedActions, isEmpty);

      final MillSessionTapResult second = await controller.tap(
        session: session,
        tappedLabel: 'g7',
      );
      expect(second.status, MillSessionTapStatus.applied);
      expect(second.action, same(move));
      expect(session.appliedActions, <GameAction>[move]);
      expect(controller.selectedFrom, isNull);
    });

    test('clears selection after an invalid second tap', () async {
      const GameAction move = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{'move': 'd7-g7'},
      );
      final _FakeSession session = _FakeSession(<GameAction>[move]);
      final MillSessionTapController controller = MillSessionTapController();

      await controller.tap(session: session, tappedLabel: 'd7');
      final MillSessionTapResult result = await controller.tap(
        session: session,
        tappedLabel: 'a1',
      );

      expect(result.status, MillSessionTapStatus.ignored);
      expect(controller.selectedFrom, isNull);
      expect(session.appliedActions, isEmpty);
    });

    test('ignores taps when the session outcome is terminal', () async {
      const GameAction placeA7 = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'a7'},
      );
      final _FakeSession session = _FakeSession(<GameAction>[
        placeA7,
      ], outcome: const GameOutcome.draw());
      final MillSessionTapController controller = MillSessionTapController();

      final MillSessionTapResult result = await controller.tap(
        session: session,
        tappedLabel: 'a7',
      );

      expect(result.status, MillSessionTapStatus.ignored);
      expect(session.appliedActions, isEmpty);
    });
  });
}

class _FakeSession implements GameSession {
  _FakeSession(
    this._legalActions, {
    GameOutcome outcome = const GameOutcome.ongoing(),
  }) : _outcome = outcome,
       _state = ValueNotifier<GameStateSnapshot>(
         GameStateSnapshot(
           gameId: GameId.mill,
           activeSeat: PlayerSeat.first,
           outcome: outcome,
         ),
       );

  final List<GameAction> _legalActions;
  final GameOutcome _outcome;
  final ValueNotifier<GameStateSnapshot> _state;
  final List<GameAction> appliedActions = <GameAction>[];

  @override
  Stream<GameSessionEvent> get events => const Stream<GameSessionEvent>.empty();

  @override
  List<GameAction> get legalActions => _legalActions;

  @override
  GameOutcome get outcome => _outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    appliedActions.add(action);
    _state.value = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: _outcome,
      lastAction: action,
    );
  }

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}

  @override
  void dispose() => _state.dispose();
}
