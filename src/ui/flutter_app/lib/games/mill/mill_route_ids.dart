// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_route_id.dart';

/// Stable route ids for the Mill game module.
///
/// Keep these ids stable to avoid breaking integration tests and persisted
/// navigation state.
abstract final class MillRouteIds {
  // Play surfaces
  static const GameRouteId humanVsAi = GameRouteId('mill.play.humanVsAi');
  static const GameRouteId humanVsHuman = GameRouteId('mill.play.humanVsHuman');
  static const GameRouteId aiVsAi = GameRouteId('mill.play.aiVsAi');
  static const GameRouteId humanVsLan = GameRouteId('mill.play.humanVsLan');
  static const GameRouteId setupPosition = GameRouteId(
    'mill.play.setupPosition',
  );

  // Non-play module screens
  static const GameRouteId puzzles = GameRouteId('mill.game.puzzles');
  static const GameRouteId statistics = GameRouteId('mill.game.statistics');
}
