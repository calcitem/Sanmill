// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/rules_port.dart';

/// Thin rules adapter around the legacy Mill state machine.
class MillRulesAdapter implements RulesPort {
  MillRulesAdapter({GameStateSnapshot? initialSnapshot})
    : _snapshot =
          initialSnapshot ??
          const GameStateSnapshot(
            gameId: GameId.mill,
            activeSeat: PlayerSeat.first,
            outcome: GameOutcome.ongoing(),
            phase: 'legacy',
          );

  GameStateSnapshot _snapshot;

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  GameStateSnapshot apply(GameAction action) {
    assert(isLegal(action), 'Illegal Mill action: ${action.type}.');
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: snapshot.activeSeat,
      outcome: snapshot.outcome,
      phase: snapshot.phase,
      lastAction: action,
      payload: snapshot.payload,
    );
    return _snapshot;
  }

  @override
  bool isLegal(GameAction action) {
    return action.type.isNotEmpty;
  }
}
