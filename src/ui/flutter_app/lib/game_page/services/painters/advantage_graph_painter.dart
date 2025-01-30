// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// advantage_graph_painter.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/database/database.dart';
import '../../../shared/utils/helpers/color_helpers/color_helper.dart';

/// A custom painter to draw the advantage trend line for up to 50 moves.
/// The horizontal axis is always conceptually divided into 50 segments.
/// If fewer than 50 moves are present, the moves are drawn starting from the left side,
/// using the same segment spacing, but not scaling to fill the entire width.
/// Once 50 moves are available, they fill the entire width. As more moves come in,
/// older moves are discarded and the line shifts left, always showing the last 50 moves.
///
/// In addition, the entire graph area is enclosed by a rectangle.
/// Above the advantage line is filled with DB().colorSettings.blackPieceColor at 50% opacity.
/// Below the advantage line is filled with DB().colorSettings.whitePieceColor at 50% opacity.
/// The advantage line thus appears as a boundary line within a semi-transparent overlay.
class AdvantageGraphPainter extends CustomPainter {
  AdvantageGraphPainter(this.data);

  final List<int> data;

  @override
  void paint(Canvas canvas, Size size) {
    // Determine how many data points to show (up to 50).
    final int showCount = math.min(50, data.length);

    // Choose between boardBackgroundColor and boardLineColor based on which has
    // a larger difference from darkBackgroundColor.
    final Color bgColor = DB().colorSettings.boardBackgroundColor;
    final Color lineColor = DB().colorSettings.boardLineColor;
    final Color darkBgColor = DB().colorSettings.darkBackgroundColor;

    final Color chosenColor =
        pickColorWithMaxDifference(bgColor, lineColor, darkBgColor)
            .withValues(alpha: 0.5);

    // Use chosenColor for zeroLinePaint.
    final Paint zeroLinePaint = Paint()
      ..color = chosenColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double margin = 10.0;
    final double chartWidth = size.width - margin * 2;
    final double chartHeight = size.height - margin * 2;

    // Zero line (value=0) in the vertical center.
    final double zeroY = margin + chartHeight / 2;

    // Always divide the horizontal axis into 50 segments.
    // For 50 moves, there are 49 intervals.
    final double dxStep = chartWidth / 49.0;

    // Clip the canvas to a rounded rectangle to restrict drawing to the rounded area.
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, margin, chartWidth, chartHeight),
        const Radius.circular(5),
      ),
    );

    // Draw zero advantage line (spanning full width) even if not enough data points.
    canvas.drawLine(
      Offset(margin, zeroY),
      Offset(margin + 49 * dxStep, zeroY),
      zeroLinePaint,
    );

    // Draw a box around the entire advantage graph area with rounded corners.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, margin, chartWidth, chartHeight),
        const Radius.circular(5),
      ),
      zeroLinePaint,
    );

    // If not enough data points, do not draw the advantage line or fill areas.
    // Return here after drawing the frame and zero line.
    // Newly added English comment: Drawing the frame and zero line regardless of data count.
    if (showCount < 2) {
      return;
    }

    // Extract the subset of the data (last showCount moves).
    final List<int> shownData = data.sublist(data.length - showCount);

    // Paint for the advantage line.
    final Paint linePaint = Paint()
      ..color = Color.lerp(
        DB().colorSettings.whitePieceColor,
        DB().colorSettings.blackPieceColor,
        0.5,
      )!
          .withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Maps advantage values [-100, 100] to Y coordinates.
    double valueToPixel(int val) {
      return zeroY - (val * (chartHeight / 200.0));
    }

    final Path path = Path();
    double? lastY;
    int? lastVal;

    // Store all points of the advantage line to construct fill areas.
    final List<Offset> points = <Offset>[];

    for (int i = 0; i < showCount; i++) {
      final double x = margin + i * dxStep;
      final int val = shownData[i];
      double y;

      // Handle VALUE_UNIQUE:
      // If val is ±100, keep Y same as previous (if any), else default to zero if first point.
      if (val == 100 || val == -100) {
        if (lastY == null) {
          y = valueToPixel(0);
        } else {
          y = lastY;
        }
      } else {
        y = valueToPixel(val);
      }

      // Check for sudden jump scenario:
      // If the previous value was out of normal range and current value is 0, consider it a new line start.
      bool newLineStart = false;
      if (lastVal != null) {
        if ((lastVal < -75 || lastVal > 75) && val == 0) {
          newLineStart = true;
        }
      }

      if (i == 0 || newLineStart) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      points.add(Offset(x, y));
      lastY = y;
      lastVal = val;
    }

    // Create fill paints:
    // Above the advantage line: blackPieceColor at 30% opacity.
    final Paint topFillPaint = Paint()
      ..color = DB().colorSettings.blackPieceColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Below the advantage line: whitePieceColor at 30% opacity.
    final Paint bottomFillPaint = Paint()
      ..color = DB().colorSettings.whitePieceColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Construct a path for the area above the advantage line:
    // 1. Move along the advantage line from left to right.
    // 2. From the last point, go straight up to the top boundary.
    // 3. Go back to the first point along the top boundary.
    // 4. Close the path.
    final Path topFillPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      topFillPath.lineTo(points[i].dx, points[i].dy);
    }
    topFillPath.lineTo(points.last.dx, margin);
    topFillPath.lineTo(points.first.dx, margin);
    topFillPath.close();

    // Construct a path for the area below the advantage line:
    // 1. Move along the advantage line from left to right.
    // 2. From the last point, go straight down to the bottom boundary.
    // 3. Go back to the first point along the bottom boundary.
    // 4. Close the path.
    final Path bottomFillPath = Path()
      ..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      bottomFillPath.lineTo(points[i].dx, points[i].dy);
    }
    bottomFillPath.lineTo(points.last.dx, margin + chartHeight);
    bottomFillPath.lineTo(points.first.dx, margin + chartHeight);
    bottomFillPath.close();

    // Draw the top area.
    canvas.drawPath(topFillPath, topFillPaint);
    // Draw the bottom area.
    canvas.drawPath(bottomFillPath, bottomFillPaint);

    // Finally, draw the advantage line on top.
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(AdvantageGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
