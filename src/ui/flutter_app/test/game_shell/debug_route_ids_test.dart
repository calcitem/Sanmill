// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_route_id.dart';
import 'package:sanmill/game_shell/debug_route_ids.dart';

void main() {
  group('DebugRouteIds', () {
    test('debug route ids share the "debug." prefix', () {
      const List<GameRouteId> debugRoutes = <GameRouteId>[
        DebugRouteIds.platformProbe,
      ];
      for (final GameRouteId routeId in debugRoutes) {
        expect(routeId.value, startsWith('debug.'));
      }
    });
  });
}
