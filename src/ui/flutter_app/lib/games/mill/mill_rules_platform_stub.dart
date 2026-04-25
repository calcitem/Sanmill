// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/rules_port.dart';
import 'mill_constants.dart';

/// Platform-compatibility stub that satisfies [RulesPort] for Mill.
///
/// ## Why this exists
///
/// [GameModule.rulesPort] requires a non-null [RulesPort] to allow the
/// generic shell to query legality and enumerate possible actions. Mill's
/// actual move-legality logic lives inside the legacy [GameController] / C++
/// engine, which is not trivially wrapped as a pure Dart [RulesPort].
///
/// ## What it does NOT do
///
/// - [legalActions] always returns an empty list. Do **not** rely on this stub
///   for move enumeration; use [MillGameSession.legalActions] instead, which
///   delegates to the live [GameController].
/// - [isLegal] only verifies that [GameAction.type] is non-empty. It does not
///   consult the engine or validate board coordinates.
///
/// ## When to replace it
///
/// Replace this stub with a real proxy once a Dart-accessible API is available
/// that can enumerate legal moves without requiring a full UI controller.
class MillRulesPlatformStub implements RulesPort {
  MillRulesPlatformStub({GameStateSnapshot? initialSnapshot})
    : _snapshot =
          initialSnapshot ??
          const GameStateSnapshot(
            gameId: GameId.mill,
            activeSeat: PlayerSeat.first,
            outcome: GameOutcome.ongoing(),
            phase: MillPhases.legacy,
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
