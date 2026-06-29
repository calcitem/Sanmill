// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'game_route_id.dart';
import 'game_session.dart';

/// Where a game module wants its action to appear in the app shell.
enum GameMenuSection { play, tools, game, settings, help, debug }

typedef GameMenuWidgetBuilder =
    Widget Function(BuildContext context, {Key? key, GameSession? session});
typedef GameMenuAvailability = bool Function(BuildContext context);

/// A mode or route contributed by a [GameModule] to the shared shell.
@immutable
class GameMenuContribution {
  const GameMenuContribution({
    required this.id,
    required this.label,
    required this.builder,
    this.section = GameMenuSection.game,
    this.icon,
    this.isAvailable,
    this.drawerKey,
    this.contentKey,
  });

  final GameRouteId id;
  final String label;
  final IconData? icon;
  final GameMenuSection section;
  final GameMenuWidgetBuilder builder;

  /// Stable key for the drawer item. Modules should provide this when tests or
  /// persisted UI automation depend on a specific drawer entry.
  final Key? drawerKey;

  /// Key passed to the content widget built for this route.
  final Key? contentKey;
  final GameMenuAvailability? isAvailable;

  bool availableIn(BuildContext context) => isAvailable?.call(context) ?? true;
}

/// A primary play mode such as human-vs-AI or setup-position.
@immutable
class GameModeEntry {
  const GameModeEntry({
    required this.id,
    required this.label,
    required this.builder,
    this.section = GameMenuSection.play,
    this.icon,
    this.isAvailable,
    this.drawerKey,
    this.contentKey,
  });

  final GameRouteId id;
  final String label;
  final IconData? icon;
  final GameMenuSection section;
  final GameMenuWidgetBuilder builder;

  /// Stable key for the drawer item. Keep old values stable across refactors.
  final Key? drawerKey;

  /// Key passed to the game surface built for this play mode.
  final Key? contentKey;
  final GameMenuAvailability? isAvailable;

  bool availableIn(BuildContext context) => isAvailable?.call(context) ?? true;
}
