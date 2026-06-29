// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_platform/game_route_id.dart';

/// Stable route ids for the shared app shell.
///
/// `app.*` is cross-game UI (settings, help, exit, game switch).
abstract final class ShellRouteIds {
  // App-level shell (not tied to a single [GameId])
  /// Switches [GameRegistry] back to its primary game from another module.
  static const GameRouteId appBackToMainGame = GameRouteId(
    'app.switch.mainGame',
  );

  static const GameRouteId appSettingsGroup = GameRouteId('app.group.settings');
  static const GameRouteId appHelpGroup = GameRouteId('app.group.help');
  static const GameRouteId appGeneralSettings = GameRouteId(
    'app.settings.general',
  );
  static const GameRouteId appRuleSettings = GameRouteId('app.settings.rules');
  static const GameRouteId appAppearance = GameRouteId(
    'app.settings.appearance',
  );
  static const GameRouteId appHowToPlay = GameRouteId('app.help.howToPlay');
  static const GameRouteId appFeedback = GameRouteId('app.help.feedback');
  static const GameRouteId appAbout = GameRouteId('app.help.about');
  static const GameRouteId appExit = GameRouteId('app.exit');
}
