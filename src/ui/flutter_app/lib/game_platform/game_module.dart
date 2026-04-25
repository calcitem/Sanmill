// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'board_geometry.dart';
import 'game_feature_flags.dart';
import 'game_menu.dart';
import 'game_module_metadata.dart';
import 'game_persistence_scope.dart';
import 'game_session_handle.dart';

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
      builder: buildGameSurface,
    ),
  ];

  /// Non-play screens such as puzzles, statistics, or game-specific settings.
  List<GameMenuContribution> drawerContributions(BuildContext context) =>
      const <GameMenuContribution>[];

  /// Primary in-app play surface. For Mill, [GamePage] with the given
  /// [GameMode] is returned by the adapter. For the probe, a self-contained
  /// toy board.
  Widget buildGameSurface(BuildContext context, {Key? key});
}
