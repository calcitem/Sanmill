// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'game_session.dart';

/// Generic rules boundary implemented by each game module.
abstract class RulesPort {
  GameStateSnapshot get snapshot;
  List<GameAction> get legalActions;
  bool isLegal(GameAction action);
  GameStateSnapshot apply(GameAction action);
}
