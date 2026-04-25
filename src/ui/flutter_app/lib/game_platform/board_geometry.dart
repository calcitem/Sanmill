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

/// Board topology for hit-testing, painting, and a11y. Mill uses 24+ vertices;
/// [demoProbe] can use a tiny toy graph.
@immutable
class BoardGeometry {
  const BoardGeometry({required this.points, required this.edges});

  final List<BoardPoint> points;
  final List<BoardEdge> edges;
}
