// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../shared/database/database.dart';

/// A custom painter to draw the advantage trend line for up to 50 moves.
/// The horizontal axis is always conceptually divided into 50 segments.
/// If fewer than 50 moves are present, the moves are drawn starting from the left side,
/// using the same segment spacing, but not scaling to fill the entire width.
/// Once 50 moves are available, they fill the entire width. As more moves come in,
/// older moves are discarded and the line shifts left, always showing the last 50 moves.
class AdvantageGraphPainter extends CustomPainter {
  AdvantageGraphPainter(this.data);

  final List<int> data;

  @override
  void paint(Canvas canvas, Size size) {
    // Determine how many data points to show (up to 50).
    final int showCount = math.min(50, data.length);

    // If not enough data points, do nothing.
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
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Choose between boardBackgroundColor and boardLineColor based on which has a larger difference from darkBackgroundColor.
    // Use a simple squared distance in RGB space to determine the color difference.
    final Color bgColor = DB().colorSettings.boardBackgroundColor;
    final Color lineColor = DB().colorSettings.boardLineColor;
    final Color darkBgColor = DB().colorSettings.darkBackgroundColor;

    double colorDiff(Color c1, Color c2) {
      final int dr = c1.red - c2.red;
      final int dg = c1.green - c2.green;
      final int db = c1.blue - c2.blue;
      return (dr * dr + dg * dg + db * db).toDouble();
    }

    final Color chosenColor =
        (colorDiff(bgColor, darkBgColor) > colorDiff(lineColor, darkBgColor))
            ? bgColor
            : lineColor;

    // Then use chosenColor for zeroLinePaint.
    final Paint zeroLinePaint = Paint()
      ..color = chosenColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double margin = 10.0;
    final double chartWidth = size.width - margin * 2;
    final double chartHeight = size.height - margin * 2;

    // Zero line (value=0) in the vertical center.
    final double zeroY = margin + chartHeight / 2;

    // Maps advantage values [-100, 100] to Y coordinates.
    double valueToPixel(int val) {
      return zeroY - (val * (chartHeight / 200.0));
    }

    // Always divide the horizontal axis into 50 segments.
    // For 50 moves, there are 49 intervals.
    // If fewer than 50 moves, do not scale them to full width;
    // just place them from the left at fixed spacing.
    final double dxStep = chartWidth / 49.0;

    final Path path = Path();
    double? lastY;
    int? lastVal;

    for (int i = 0; i < showCount; i++) {
      // The X position always starts from the left and uses the same dxStep.
      // If fewer than 50 moves, we just won't reach the far right side.
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
        // Move to this point without drawing a line from the previous.
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      lastY = y;
      lastVal = val;
    }

    // Draw zero advantage line.
    // Zero line should also span the full 50-segment width (49 intervals).
    canvas.drawLine(
      Offset(margin, zeroY),
      Offset(margin + 49 * dxStep, zeroY),
      zeroLinePaint,
    );

    // Draw the advantage line path.
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(AdvantageGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
