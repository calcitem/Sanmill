// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../game_platform/game_id.dart';
import '../game_platform/game_menu.dart';
import '../game_platform/game_module.dart';
import '../game_platform/game_registry.dart';
import '../game_platform/game_session.dart';
import '../game_shell/shell_route_ids.dart';
import '../games/mill/mill_game_module.dart'
    show applyMillGameControllerFlagsForPlayRoute;
import 'shell_app_routes.dart';

/// Resolves a Mill module surface for [routeId], or `null` if [routeId] is not
/// a Mill play mode or Mill drawer contribution.
Widget? buildMillModuleScreen(
  BuildContext context,
  String routeId, {
  GameSession? session,
}) {
  if (!routeId.startsWith('mill.')) {
    return null;
  }
  final GameModule? module = GameRegistry.instance.getModule(GameId.mill);
  if (module == null) {
    return null;
  }

  for (final GameModeEntry mode in module.playModes(context)) {
    if (mode.id == routeId) {
      if (!mode.availableIn(context)) {
        return null;
      }
      if (isMillPlayRoute(routeId)) {
        applyMillGameControllerFlagsForPlayRoute(routeId);
      }
      return mode.builder(context, key: mode.contentKey, session: session);
    }
  }
  for (final GameMenuContribution c in module.drawerContributions(context)) {
    if (c.id == routeId) {
      if (!c.availableIn(context)) {
        return null;
      }
      return c.builder(context, key: c.contentKey, session: session);
    }
  }
  return null;
}

/// App-wide screens (settings, help, exit) that are not owned by a [GameModule].
Widget? buildAppShellScreen(BuildContext context, String routeId) {
  return buildAppRouteScreen(context, routeId);
}
