// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// A vertex on the board, in unit square coordinates (0,0)–(1,1).
@immutable
class BoardPoint {
  const BoardPoint({required this.id, required this.x, required this.y});

  final int id;
  final double x;
  final double y;
}

/// An undirected edge between two [BoardPoint.id] values.
@immutable
class BoardEdge {
  const BoardEdge(this.a, this.b);

  final int a;
  final int b;
}

enum BoardLayoutKind { graph, grid, region }

/// A named set of board points, such as a starting camp, target area, hand, or
/// scoring zone. Rendering remains module-owned; the platform only carries the
/// stable ids.
@immutable
class BoardZone {
  const BoardZone({required this.id, required this.pointIds, this.label});

  final String id;
  final List<int> pointIds;
  final String? label;
}

/// Board topology for hit-testing, painting, and a11y.
///
/// Every board-game module should expose its own geometry so shared shell code
/// can reason about points without importing the game's position model. Mill
/// uses 24+ vertices; [demoProbe] uses a tiny toy graph.
@immutable
class BoardGeometry {
  const BoardGeometry({
    required this.points,
    required this.edges,
    this.kind = BoardLayoutKind.graph,
    this.zones = const <BoardZone>[],
  });

  final List<BoardPoint> points;
  final List<BoardEdge> edges;
  final BoardLayoutKind kind;
  final List<BoardZone> zones;
}
