// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Stable route ids for the Mill game module.
///
/// Keep these ids stable to avoid breaking integration tests and persisted
/// navigation state.
abstract final class MillRouteIds {
  // Play surfaces
  static const String humanVsAi = 'mill.play.humanVsAi';
  static const String humanVsHuman = 'mill.play.humanVsHuman';
  static const String aiVsAi = 'mill.play.aiVsAi';
  static const String humanVsLan = 'mill.play.humanVsLan';
  static const String setupPosition = 'mill.play.setupPosition';

  // Non-play module screens
  static const String puzzles = 'mill.game.puzzles';
  static const String statistics = 'mill.game.statistics';
}
