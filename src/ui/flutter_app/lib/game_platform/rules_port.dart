// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Pure rules boundary implemented by each board-game module.
///
/// UI widgets should ask this port or the active [GameSession] for legality
/// instead of embedding game rules in gesture handlers. Implementations should
/// assert on malformed actions and return deterministic snapshots for valid
/// actions.
abstract class RulesPort {
  GameStateSnapshot get snapshot;
  List<GameAction> get legalActions;
  bool isLegal(GameAction action);
  GameStateSnapshot apply(GameAction action);
}
