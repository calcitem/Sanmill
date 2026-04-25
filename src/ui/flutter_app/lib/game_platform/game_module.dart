// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'board_geometry.dart';
import 'engine/engine_port.dart';
import 'game_feature_flags.dart';
import 'game_menu.dart';
import 'game_module_metadata.dart';
import 'game_persistence_scope.dart';
import 'game_session.dart';
import 'game_session_handle.dart';
import 'notation_port.dart';
import 'rules_port.dart';
import 'shell_route_navigation_source.dart';

/// One installable game (Mill, probe, …). The app shell loads modules from a
/// [GameRegistry] and does not import game-specific code except through this API.
abstract class GameModule {
  GameModuleMetadata get metadata;
  GameFeatureFlags get features;
  BoardGeometry get boardGeometry;
  GamePersistenceScope get persistenceScope;

  /// Create a new interactive session. For Mill, this is still backed by
  /// [GameController] singleton; later it becomes a dedicated session type.
  GameSessionHandle startSession();

  /// Optional module initialization that depends on shell context.
  Future<void> bootstrap(BuildContext context) async {}

  /// Primary play modes contributed to the shared shell.
  List<GameModeEntry> playModes(BuildContext context) => <GameModeEntry>[
    GameModeEntry(
      id: metadata.id.value,
      label: metadata.shortLabel,
      builder: (BuildContext context, {Key? key, GameSession? session}) =>
          buildGameSurface(context, key: key, session: session),
    ),
  ];

  /// Non-play screens such as puzzles, statistics, or game-specific settings.
  List<GameMenuContribution> drawerContributions(BuildContext context) =>
      const <GameMenuContribution>[];

  /// Optional rules engine port (for import/export, tests, future UI).
  RulesPort? get rulesPort => null;

  /// Optional notation port (PGN-like or custom text formats per game).
  NotationPort? get notationPort => null;

  /// Optional engine port (AI / analysis / search).
  EnginePort? get enginePort => null;

  /// Optional module-owned rule settings screen. When null, the shared shell
  /// should hide the rule settings entry for this game.
  Widget? buildRuleSettingsScreen(BuildContext context) => null;

  /// First shell route when this game becomes active (startup or game switch).
  String defaultShellRoute(BuildContext context) {
    final List<GameModeEntry> modes = playModes(context);
    if (modes.isEmpty) {
      return metadata.id.value;
    }
    return modes.first.id;
  }

  /// Called when this module is no longer the active game (e.g. user picked
  /// another [GameId]). [lastShellRouteId] is the route that was showing.
  void onShellInactive(
    BuildContext context, {
    required String lastShellRouteId,
  }) {}

  /// Optional board / padding adjustments for the shared shell (Mill only today).
  void applyShellLayoutHints(BuildContext context) {}

  /// Return false to cancel navigation. [source] is [drawer] for drawer picks
  /// and [backStack] for internal stack pops (skips Mill LAN entry confirm).
  Future<bool> willNavigateToShellRoute(
    BuildContext context, {
    required String? previousRouteId,
    required String nextRouteId,
    ShellRouteNavigationSource source = ShellRouteNavigationSource.drawer,
  }) async => true;

  /// Invoked after [willNavigateToShellRoute] succeeds and before the new
  /// route widget is built.
  void didNavigateShellRoute(
    BuildContext context, {
    required String? previousRouteId,
    required String nextRouteId,
  }) {}

  /// True if [routeId] is a [playModes] entry for this module (a primary
  /// play surface), as opposed to a [drawerContributions] screen or an app
  /// shell route. Used by the shared shell for back-stack and gesture policy.
  bool isPlayModeRoute(String routeId, BuildContext context) {
    for (final GameModeEntry mode in playModes(context)) {
      if (mode.id == routeId) {
        return true;
      }
    }
    return false;
  }

  /// Primary in-app play surface. For Mill, [GamePage] with the given
  /// [GameMode] is returned by the adapter. For the probe, a self-contained
  /// toy board.
  ///
  /// [session] is the active [GameSession] when the shell created it; modules
  /// that do not use it may ignore it.
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  });
}
