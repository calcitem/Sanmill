// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_rules_platform_stub.dart';

void main() {
  group('MillRulesPlatformStub — stub contract', () {
    late MillRulesPlatformStub stub;

    setUp(() {
      stub = MillRulesPlatformStub();
    });

    test('legalActions is always empty', () {
      expect(stub.legalActions, isEmpty);
    });

    test('initial snapshot uses legacy phase and Mill game id', () {
      expect(stub.snapshot.gameId, GameId.mill);
      expect(stub.snapshot.phase, MillPhases.legacy);
      expect(stub.snapshot.outcome.isTerminal, isFalse);
    });

    test('accepts any action with a non-empty type string', () {
      const GameAction validAction = GameAction(type: 'mill.place');
      expect(stub.isLegal(validAction), isTrue);
    });

    test('rejects actions with an empty type string', () {
      const GameAction emptyType = GameAction(type: '');
      expect(stub.isLegal(emptyType), isFalse);
    });

    test('apply updates lastAction in the returned snapshot', () {
      const GameAction action = GameAction(
        type: 'mill.place',
        payload: <String, Object?>{'move': 'd6'},
      );
      final GameStateSnapshot updated = stub.apply(action);
      expect(updated.lastAction, action);
      expect(updated.phase, stub.snapshot.phase);
    });

    test('apply keeps activeSeat and outcome unchanged', () {
      const GameAction action = GameAction(type: 'mill.move');
      final PlayerSeat originalSeat = stub.snapshot.activeSeat;
      final GameOutcomeKind originalKind = stub.snapshot.outcome.kind;
      final GameStateSnapshot updated = stub.apply(action);
      expect(updated.activeSeat, originalSeat);
      expect(updated.outcome.kind, originalKind);
    });

    test('snapshot field updates after successive applies', () {
      const GameAction a1 = GameAction(type: 'mill.place');
      const GameAction a2 = GameAction(type: 'mill.move');
      stub.apply(a1);
      final GameStateSnapshot afterA2 = stub.apply(a2);
      expect(afterA2.lastAction, a2);
    });

    test('custom initialSnapshot is used as starting state', () {
      const GameStateSnapshot custom = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: PlayerSeat.second,
        outcome: GameOutcome.ongoing(),
        phase: 'moving',
      );
      final MillRulesPlatformStub customStub = MillRulesPlatformStub(
        initialSnapshot: custom,
      );
      expect(customStub.snapshot.activeSeat, PlayerSeat.second);
      expect(customStub.snapshot.phase, 'moving');
    });
  });
}
