// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_platform/game_route_id.dart';

/// Debug-only route ids used by the shared shell.
abstract final class DebugRouteIds {
  static const GameRouteId platformProbe = GameRouteId('debug.platformProbe');
}
