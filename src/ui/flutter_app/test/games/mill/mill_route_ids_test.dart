// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_route_id.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';

void main() {
  group('MillRouteIds', () {
    test('Mill route ids share the "mill." prefix', () {
      const List<GameRouteId> millRoutes = <GameRouteId>[
        MillRouteIds.humanVsAi,
        MillRouteIds.humanVsHuman,
        MillRouteIds.aiVsAi,
        MillRouteIds.humanVsLan,
        MillRouteIds.setupPosition,
        MillRouteIds.puzzles,
        MillRouteIds.statistics,
      ];
      for (final GameRouteId routeId in millRoutes) {
        expect(routeId.value, startsWith('mill.'));
      }
    });

    test('each route id has a unique value', () {
      const List<GameRouteId> all = <GameRouteId>[
        MillRouteIds.humanVsAi,
        MillRouteIds.humanVsHuman,
        MillRouteIds.aiVsAi,
        MillRouteIds.humanVsLan,
        MillRouteIds.setupPosition,
        MillRouteIds.puzzles,
        MillRouteIds.statistics,
      ];
      final Set<String> values = all.map((GameRouteId r) => r.value).toSet();
      expect(values.length, all.length);
    });
  });
}
