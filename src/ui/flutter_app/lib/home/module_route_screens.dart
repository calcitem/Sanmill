// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_session.dart';
import 'shell_app_routes.dart';

/// Resolves a [GameModule] surface for [routeId], or `null` if the route is
/// not a play mode or menu contribution of [gameId].
Widget? buildModuleScreenForGame(
  BuildContext context,
  GameId gameId,
  String routeId, {
  GameSession? session,
}) {
  final GameModule? module = GameRegistry.instance.getModule(gameId);
  if (module == null) {
    return null;
  }

  for (final GameModeEntry mode in module.playModes(context)) {
    if (mode.id.value == routeId) {
      if (!mode.availableIn(context)) {
        return null;
      }
      return mode.builder(context, key: mode.contentKey, session: session);
    }
  }
  for (final GameMenuContribution c in module.menuContributions(context)) {
    if (c.id.value == routeId) {
      if (!c.availableIn(context)) {
        return null;
      }
      return c.builder(context, key: c.contentKey, session: session);
    }
  }
  return null;
}

/// Resolves a surface for [routeId] using the currently selected game module
/// in [GameRegistry]. Falls back to `null` when the route is not owned by the
/// active module.
Widget? buildModuleScreen(
  BuildContext context,
  String routeId, {
  GameSession? session,
}) {
  return buildModuleScreenForGame(
    context,
    GameRegistry.instance.currentId,
    routeId,
    session: session,
  );
}

/// App-wide screens (settings, help, exit) that are not owned by a [GameModule].
Widget? buildAppShellScreen(BuildContext context, String routeId) {
  return buildAppRouteScreen(context, routeId);
}
