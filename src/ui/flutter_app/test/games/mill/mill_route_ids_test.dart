// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_route_ids.dart';

void main() {
  group('MillRouteIds', () {
    test('Mill route ids share the "mill." prefix', () {
      const List<String> millRoutes = <String>[
        MillRouteIds.humanVsAi,
        MillRouteIds.humanVsHuman,
        MillRouteIds.aiVsAi,
        MillRouteIds.humanVsLan,
        MillRouteIds.setupPosition,
        MillRouteIds.puzzles,
        MillRouteIds.statistics,
      ];
      for (final String routeId in millRoutes) {
        expect(routeId, startsWith('mill.'));
      }
    });
  });
}
