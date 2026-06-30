// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/board_geometry.dart';

void main() {
  group('BoardEdge', () {
    test('default kindTag is 0', () {
      const BoardEdge edge = BoardEdge(0, 1);
      expect(edge.kindTag, 0);
    });

    test('explicit kindTag is preserved', () {
      const BoardEdge edge = BoardEdge(0, 1, kindTag: 7);
      expect(edge.kindTag, 7);
    });
  });

  group('BoardZone', () {
    test('default role is empty', () {
      const BoardZone zone = BoardZone(id: 'hand_w', pointIds: <int>[0, 1, 2]);
      expect(zone.role, isEmpty);
    });

    test('canonical roles are stable string tokens', () {
      expect(BoardZoneRole.hand, 'hand');
      expect(BoardZoneRole.goal, 'goal');
      expect(BoardZoneRole.camp, 'camp');
      expect(BoardZoneRole.headquarters, 'headquarters');
      expect(BoardZoneRole.railroad, 'railroad');
    });
  });

  group('BoardGeometry helpers', () {
    const BoardGeometry geo = BoardGeometry(
      points: <BoardPoint>[
        BoardPoint(id: 0, x: 0.0, y: 0.0),
        BoardPoint(id: 1, x: 0.5, y: 0.0),
        BoardPoint(id: 2, x: 1.0, y: 0.0),
      ],
      edges: <BoardEdge>[BoardEdge(0, 1, kindTag: 1), BoardEdge(1, 2)],
      zones: <BoardZone>[
        BoardZone(id: 'camp_b', pointIds: <int>[1], role: BoardZoneRole.camp),
      ],
    );

    test('kindOfEdge resolves regardless of orientation', () {
      expect(geo.kindOfEdge(0, 1), 1);
      expect(geo.kindOfEdge(1, 0), 1);
      expect(geo.kindOfEdge(1, 2), 0);
      expect(geo.kindOfEdge(0, 2), isNull);
    });

    test('zoneRoleAt returns canonical role for matching node', () {
      expect(geo.zoneRoleAt(1), BoardZoneRole.camp);
      expect(geo.zoneRoleAt(0), BoardZoneRole.none);
      expect(geo.zoneRoleAt(2), BoardZoneRole.none);
    });
  });
}
