// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_rect_overlay.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Overlay layer used to display the detected board rectangle area during the board detection phase.
class BoardRectOverlay extends StatelessWidget {
  const BoardRectOverlay({
    super.key,
    required this.boardRect,
    required this.imageSize,
  });

  /// The detected board rectangle area.
  final math.Rectangle<int> boardRect;

  /// The size of the original image.
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _BoardRectPainter(
        boardRect: boardRect,
        imageSize: imageSize,
      ),
    );
  }
}

/// Custom painter for drawing the board detection rectangle area.
class _BoardRectPainter extends CustomPainter {
  _BoardRectPainter({
    required this.boardRect,
    required this.imageSize,
  });

  final math.Rectangle<int> boardRect;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the scaling factors.
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Set up the paint for drawing the rectangle.
    final Paint rectPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Create a dashed path.
    final Path dashedPath = Path();

    // Calculate the position and size of the rectangle in the view.
    final Rect rect = Rect.fromLTWH(
      boardRect.left * scaleX,
      boardRect.top * scaleY,
      boardRect.width * scaleX,
      boardRect.height * scaleY,
    );

    // Draw the rectangle with a dashed effect.
    const double dashWidth = 10.0;
    const double dashSpace = 5.0;

    // Draw the top dashed line.
    double startX = rect.left;
    while (startX < rect.right) {
      final double endX =
          startX + dashWidth < rect.right ? startX + dashWidth : rect.right;
      dashedPath.moveTo(startX, rect.top);
      dashedPath.lineTo(endX, rect.top);
      startX = endX + dashSpace;
    }

    // Draw the right dashed line.
    double startY = rect.top;
    while (startY < rect.bottom) {
      final double endY =
          startY + dashWidth < rect.bottom ? startY + dashWidth : rect.bottom;
      dashedPath.moveTo(rect.right, startY);
      dashedPath.lineTo(rect.right, endY);
      startY = endY + dashSpace;
    }

    // Draw the bottom dashed line.
    startX = rect.right;
    while (startX > rect.left) {
      final double endX =
          startX - dashWidth > rect.left ? startX - dashWidth : rect.left;
      dashedPath.moveTo(startX, rect.bottom);
      dashedPath.lineTo(endX, rect.bottom);
      startX = endX - dashSpace;
    }

    // Draw the left dashed line.
    startY = rect.bottom;
    while (startY > rect.top) {
      final double endY =
          startY - dashWidth > rect.top ? startY - dashWidth : rect.top;
      dashedPath.moveTo(rect.left, startY);
      dashedPath.lineTo(rect.left, endY);
      startY = endY - dashSpace;
    }

    // Draw the dashed path.
    canvas.drawPath(dashedPath, rectPaint);

    // Add a text label.
    const String label = 'Detected Board Area'; // Translated label text
    const TextSpan textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.yellow,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black54,
      ),
    );

    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(rect.left + 10, rect.top + 10),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardRectPainter oldDelegate) =>
      oldDelegate.boardRect != boardRect || oldDelegate.imageSize != imageSize;
}
