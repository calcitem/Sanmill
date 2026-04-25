// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Stable route ids for the shared [Home] / drawer shell.
///
/// `mill.*` entries must stay aligned with [MillGameModule] `playModes` and
/// `drawerContributions` ids. `app.*` is cross-game UI (settings, help, exit).
abstract final class ShellRouteIds {
  // Mill play surfaces
  static const String millHumanVsAi = 'mill.play.humanVsAi';
  static const String millHumanVsHuman = 'mill.play.humanVsHuman';
  static const String millAiVsAi = 'mill.play.aiVsAi';
  static const String millHumanVsLan = 'mill.play.humanVsLan';
  static const String millSetupPosition = 'mill.play.setupPosition';

  // Mill non-play screens (still under Mill module contributions)
  static const String millPuzzles = 'mill.game.puzzles';
  static const String millStatistics = 'mill.game.statistics';

  // App-level shell (not tied to a single [GameId])
  /// Switches [GameRegistry] back to [GameId.mill] from another module.
  static const String appBackToMainGame = 'app.switch.mainGame';

  static const String appSettingsGroup = 'app.group.settings';
  static const String appHelpGroup = 'app.group.help';
  static const String appGeneralSettings = 'app.settings.general';
  static const String appRuleSettings = 'app.settings.rules';
  static const String appAppearance = 'app.settings.appearance';
  static const String appHowToPlay = 'app.help.howToPlay';
  static const String appFeedback = 'app.help.feedback';
  static const String appAbout = 'app.help.about';
  static const String appExit = 'app.exit';

  // Debug: switch [GameRegistry] to another [GameId]
  static const String debugPlatformProbe = 'debug.platformProbe';
}
