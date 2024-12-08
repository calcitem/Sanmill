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

/// A custom painter to draw the advantage trend line, but only for the most recent 20 moves.
/// Positive values indicate white advantage, negative indicate black advantage.
/// If there are more than 20 moves, only the last 20 are shown.
/// As new moves come in, older moves are discarded from the left side.
class AdvantageGraphPainter extends CustomPainter {
  AdvantageGraphPainter(this.data);

  final List<int> data;

  @override
  void paint(Canvas canvas, Size size) {
    // Determine how many data points to show (up to 20).
    final int showCount = math.min(20, data.length);

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

    // Paint for the zero advantage line.
    final Paint zeroLinePaint = Paint()
      ..color = DB().colorSettings.boardBackgroundColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const double margin = 10.0;
    final double chartWidth = size.width - margin * 2;
    final double chartHeight = size.height - margin * 2;

    // Zero line (value=0) in the vertical center.
    final double zeroY = margin + chartHeight / 2;

    // Function to map advantage values [-100, 100] to canvas Y coordinates.
    double valueToPixel(int val) {
      // val=100 => top (margin)
      // val=-100 => bottom (margin+chartHeight)
      // val=0 => zeroY
      return zeroY - (val * (chartHeight / 200.0));
    }

    // Horizontal step between points for the shownData subset.
    final int count = shownData.length;
    final double dxStep = chartWidth / (count - 1);

    final Path path = Path();
    for (int i = 0; i < count; i++) {
      final double x = margin + i * dxStep;
      final double y = valueToPixel(shownData[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw the zero advantage line.
    canvas.drawLine(
      Offset(margin, zeroY),
      Offset(size.width - margin, zeroY),
      zeroLinePaint,
    );

    // Draw the line path.
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(AdvantageGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
