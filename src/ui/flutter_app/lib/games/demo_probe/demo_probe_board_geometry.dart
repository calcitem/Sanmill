// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/board_geometry.dart';

/// 3×3 grid in unit square, indices 0–8 row-major.
final BoardGeometry demoProbeBoardGeometry = _buildTicTacToe();

BoardGeometry _buildTicTacToe() {
  const List<BoardPoint> points = <BoardPoint>[
    BoardPoint(id: 0, x: 0.2, y: 0.2),
    BoardPoint(id: 1, x: 0.5, y: 0.2),
    BoardPoint(id: 2, x: 0.8, y: 0.2),
    BoardPoint(id: 3, x: 0.2, y: 0.5),
    BoardPoint(id: 4, x: 0.5, y: 0.5),
    BoardPoint(id: 5, x: 0.8, y: 0.5),
    BoardPoint(id: 6, x: 0.2, y: 0.8),
    BoardPoint(id: 7, x: 0.5, y: 0.8),
    BoardPoint(id: 8, x: 0.8, y: 0.8),
  ];
  const List<BoardEdge> edges = <BoardEdge>[
    BoardEdge(0, 1),
    BoardEdge(1, 2),
    BoardEdge(3, 4),
    BoardEdge(4, 5),
    BoardEdge(6, 7),
    BoardEdge(7, 8),
    BoardEdge(0, 3),
    BoardEdge(3, 6),
    BoardEdge(1, 4),
    BoardEdge(4, 7),
    BoardEdge(2, 5),
    BoardEdge(5, 8),
  ];
  return const BoardGeometry(points: points, edges: edges);
}
