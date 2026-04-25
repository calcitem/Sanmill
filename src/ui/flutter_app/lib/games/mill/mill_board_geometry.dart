// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/board_geometry.dart';

/// Normalized 0–1 layout approximating the standard Mill board (24 playable
/// points, three concentric squares, eight radials). Used by the platform
/// until the Mill painter is fully driven from [BoardGeometry].
final BoardGeometry millDefaultBoardGeometry = _buildMillGeometry();

BoardGeometry _buildMillGeometry() {
  const List<BoardPoint> points = <BoardPoint>[
    BoardPoint(id: 0, x: 0.1, y: 0.1),
    BoardPoint(id: 1, x: 0.5, y: 0.1),
    BoardPoint(id: 2, x: 0.9, y: 0.1),
    BoardPoint(id: 3, x: 0.9, y: 0.5),
    BoardPoint(id: 4, x: 0.9, y: 0.9),
    BoardPoint(id: 5, x: 0.5, y: 0.9),
    BoardPoint(id: 6, x: 0.1, y: 0.9),
    BoardPoint(id: 7, x: 0.1, y: 0.5),
    BoardPoint(id: 8, x: 0.2, y: 0.2),
    BoardPoint(id: 9, x: 0.5, y: 0.2),
    BoardPoint(id: 10, x: 0.8, y: 0.2),
    BoardPoint(id: 11, x: 0.8, y: 0.5),
    BoardPoint(id: 12, x: 0.8, y: 0.8),
    BoardPoint(id: 13, x: 0.5, y: 0.8),
    BoardPoint(id: 14, x: 0.2, y: 0.8),
    BoardPoint(id: 15, x: 0.2, y: 0.5),
    BoardPoint(id: 16, x: 0.3, y: 0.3),
    BoardPoint(id: 17, x: 0.5, y: 0.3),
    BoardPoint(id: 18, x: 0.7, y: 0.3),
    BoardPoint(id: 19, x: 0.7, y: 0.5),
    BoardPoint(id: 20, x: 0.7, y: 0.7),
    BoardPoint(id: 21, x: 0.5, y: 0.7),
    BoardPoint(id: 22, x: 0.3, y: 0.7),
    BoardPoint(id: 23, x: 0.3, y: 0.5),
  ];

  final List<BoardEdge> edges = <BoardEdge>[];

  void addRing(int start) {
    for (int i = 0; i < 8; i++) {
      edges.add(BoardEdge(start + i, start + (i + 1) % 8));
    }
  }

  addRing(0);
  addRing(8);
  addRing(16);
  for (int i = 0; i < 8; i++) {
    edges.add(BoardEdge(i, 8 + i));
    edges.add(BoardEdge(8 + i, 16 + i));
  }
  return BoardGeometry(points: points, edges: edges);
}
