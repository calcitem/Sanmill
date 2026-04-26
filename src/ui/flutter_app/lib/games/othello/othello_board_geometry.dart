// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/board_geometry.dart';

final BoardGeometry othelloBoardGeometry = _buildOthelloGeometry();

BoardGeometry _buildOthelloGeometry() {
  final List<BoardPoint> points = <BoardPoint>[
    for (int r = 0; r < 8; r++)
      for (int c = 0; c < 8; c++)
        BoardPoint(id: r * 8 + c, x: c / 7.0, y: r / 7.0),
  ];
  final List<BoardEdge> edges = <BoardEdge>[];
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if (c < 7) {
        edges.add(BoardEdge(r * 8 + c, r * 8 + c + 1));
      }
      if (r < 7) {
        edges.add(BoardEdge(r * 8 + c, (r + 1) * 8 + c));
      }
    }
  }
  return BoardGeometry(
    points: points,
    edges: edges,
    kind: BoardLayoutKind.grid,
  );
}
