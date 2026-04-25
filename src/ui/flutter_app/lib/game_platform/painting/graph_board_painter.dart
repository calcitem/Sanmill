// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../board_geometry.dart';

/// Paints vertices and edges from a [BoardGeometry] in a unit square, scaled
/// to the given canvas [size].
class GraphBoardPainter extends CustomPainter {
  GraphBoardPainter({
    required this.geometry,
    required this.lineColor,
    required this.nodeColor,
    required this.nodeRadius,
  });

  final BoardGeometry geometry;
  final Color lineColor;
  final Color nodeColor;
  final double nodeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Paint fillPaint = Paint()..color = nodeColor;
    for (final BoardEdge e in geometry.edges) {
      final BoardPoint a = geometry.points[e.a];
      final BoardPoint b = geometry.points[e.b];
      final Offset p1 = Offset(a.x * size.width, a.y * size.height);
      final Offset p2 = Offset(b.x * size.width, b.y * size.height);
      canvas.drawLine(p1, p2, linePaint);
    }
    for (final BoardPoint p in geometry.points) {
      final Offset c = Offset(p.x * size.width, p.y * size.height);
      canvas.drawCircle(c, nodeRadius, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GraphBoardPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.nodeRadius != nodeRadius;
  }
}
