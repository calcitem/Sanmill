// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece_overlay_painter.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/themes/app_theme.dart';
import '../services/board_image_recognition.dart';
import '../services/mill.dart';

/// Drawing overlay for visualizing board recognition results
class PieceOverlayPainter extends CustomPainter {
  PieceOverlayPainter({
    required this.boardPoints,
    required this.resultMap,
    required this.imageSize,
    this.boardRect,
  });

  final List<BoardPoint> boardPoints;
  final Map<int, PieceColor> resultMap;
  final Size imageSize; // Actual size of the processed image
  final math.Rectangle<int>? boardRect;

  @override
  void paint(Canvas canvas, Size size) {
    // If no points detected, don't try to render anything
    if (boardPoints.isEmpty) {
      return;
    }

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Draw the board area rectangle (if available)
    if (boardRect != null) {
      final Paint rectPaint = Paint()
        ..color = Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      // Draw the rectangle with a dashed effect
      final Path dashedPath = Path();

      // Define the rectangle to be drawn
      final Rect rect = Rect.fromLTWH(
        boardRect!.left * scaleX,
        boardRect!.top * scaleY,
        boardRect!.width * scaleX,
        boardRect!.height * scaleY,
      );

      // Draw the rectangle with a dashed line effect
      const double dashWidth = 10.0;
      const double dashSpace = 5.0;

      // Draw the top dashed line
      double startX = rect.left;
      while (startX < rect.right) {
        final double endX =
            startX + dashWidth < rect.right ? startX + dashWidth : rect.right;
        dashedPath.moveTo(startX, rect.top);
        dashedPath.lineTo(endX, rect.top);
        startX = endX + dashSpace;
      }

      // Draw the right dashed line
      double startY = rect.top;
      while (startY < rect.bottom) {
        final double endY =
            startY + dashWidth < rect.bottom ? startY + dashWidth : rect.bottom;
        dashedPath.moveTo(rect.right, startY);
        dashedPath.lineTo(rect.right, endY);
        startY = endY + dashSpace;
      }

      // Draw the bottom dashed line
      startX = rect.right;
      while (startX > rect.left) {
        final double endX =
            startX - dashWidth > rect.left ? startX - dashWidth : rect.left;
        dashedPath.moveTo(startX, rect.bottom);
        dashedPath.lineTo(endX, rect.bottom);
        startX = endX - dashSpace;
      }

      // Draw the left dashed line
      startY = rect.bottom;
      while (startY > rect.top) {
        final double endY =
            startY - dashWidth > rect.top ? startY - dashWidth : rect.top;
        dashedPath.moveTo(rect.left, startY);
        dashedPath.lineTo(rect.left, endY);
        startY = endY - dashSpace;
      }

      // Draw the dashed path
      canvas.drawPath(dashedPath, rectPaint);

      // Add a text label
      final TextPainter textPainter = TextPainter(
        text: const TextSpan(
          text: 'Detected Board Area', // Changed text to English
          style: TextStyle(
            color: Colors.yellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rect.left + 10, rect.top + 10),
      );
    }

    // If no points detected, don't try to render anything (Redundant check, but harmless)
    // if (boardPoints.isEmpty) {
    //   return;
    // }

    // --- 1. Get the actual board points from detection ---
    // Extract points for each ring (assuming standard ordering from detection)
    final List<BoardPoint> outerRingPoints = boardPoints.take(8).toList();
    final List<BoardPoint> middleRingPoints =
        boardPoints.skip(8).take(8).toList();
    final List<BoardPoint> innerRingPoints =
        boardPoints.skip(16).take(8).toList();

    // --- 2. Calculate the board size and position based on actual detected points ---
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    // Find bounding box of outer ring (not all points)
    for (final BoardPoint point in outerRingPoints) {
      if (point.x < minX) {
        minX = point.x.toDouble();
      }
      if (point.y < minY) {
        minY = point.y.toDouble();
      }
      if (point.x > maxX) {
        maxX = point.x.toDouble();
      }
      if (point.y > maxY) {
        maxY = point.y.toDouble();
      }
    }

    // Get detected board dimensions
    final double detectedWidth = maxX - minX;
    final double detectedHeight = maxY - minY;
    final double detectedSize = math.max(detectedWidth, detectedHeight);

    // Get board dimensions in view
    final double viewPadding = AppTheme.boardPadding;
    final double availableSize =
        math.min(size.width, size.height) - (viewPadding * 2);

    // Calculate scale factor to map from detected to view
    final double scaleFactor = availableSize / detectedSize;

    // Calculate offset to center the board
    final double xOffset = (size.width - detectedWidth * scaleFactor) / 2;
    final double yOffset = (size.height - detectedHeight * scaleFactor) / 2;

    // --- 3. Helper function to map detected point to view coordinates ---
    Offset mapPointToView(BoardPoint point) {
      return Offset(xOffset + (point.x - minX) * scaleFactor,
          yOffset + (point.y - minY) * scaleFactor);
    }

    // --- 4. Prepare paint objects for visualization ---
    // Paint for board lines
    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.yellow.withValues(alpha: 0.7); // Use withOpacity

    // --- 5. Draw board grid using actual detected points ---
    // Draw board grid according to Nine Men's Morris rules
    final List<Offset> outerOffsets =
        outerRingPoints.map(mapPointToView).toList();
    final List<Offset> middleOffsets =
        middleRingPoints.map(mapPointToView).toList();
    final List<Offset> innerOffsets =
        innerRingPoints.map(mapPointToView).toList();
    // Draw outer ring connections
    for (int i = 0; i < outerOffsets.length; i++) {
      final int next = (i + 1) % outerOffsets.length;
      canvas.drawLine(outerOffsets[i], outerOffsets[next], gridPaint);
    }
    // Draw middle ring connections
    for (int i = 0; i < middleOffsets.length; i++) {
      final int next = (i + 1) % middleOffsets.length;
      canvas.drawLine(middleOffsets[i], middleOffsets[next], gridPaint);
    }
    // Draw inner ring connections
    for (int i = 0; i < innerOffsets.length; i++) {
      final int next = (i + 1) % innerOffsets.length;
      canvas.drawLine(innerOffsets[i], innerOffsets[next], gridPaint);
    }
    // Draw radial connections between rings at midpoint positions (indices 1,3,5,7)
    const List<int> connections = <int>[1, 3, 5, 7];
    for (final int idx in connections) {
      canvas.drawLine(outerOffsets[idx], middleOffsets[idx], gridPaint);
      canvas.drawLine(middleOffsets[idx], innerOffsets[idx], gridPaint);
    }

    // --- 6. Draw detected pieces ---
    // This section seems to draw crosses over the *ideal* grid positions if a piece is detected there.
    for (int i = 0; i < boardPoints.length && i < resultMap.length; i++) {
      final PieceColor pieceColor = resultMap[i]!;
      if (pieceColor == PieceColor.none) {
        continue; // Skip empty positions
      }

      // Get the point from detection (corresponds to the index i)
      final BoardPoint detectedPoint =
          boardPoints[i]; // Use boardPoints[i] directly

      // Map to view position based on the *calculated* grid, not raw point coordinates
      final Offset viewPosition;
      if (i < 8) {
        viewPosition = outerOffsets[i];
      } else if (i < 16) {
        viewPosition = middleOffsets[i - 8];
      } else {
        viewPosition = innerOffsets[i - 16];
      }

      // Calculate appropriate radius based on point's original radius, scaled
      // Use a fixed fraction of the calculated grid spacing or average radius?
      // Let's keep the original logic for now:
      final double viewRadius = detectedPoint.radius * scaleFactor * 0.8;

      // Draw a cross marker instead of a circle
      final Paint crossPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = pieceColor == PieceColor.black ? Colors.black : Colors.white;

      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 // Border is thicker
        ..color = pieceColor == PieceColor.black
            ? Colors.white
            : Colors.black; // Contrast color

      // Cross size is based on the piece radius
      final double crossSize = viewRadius * 0.8;

      // First, draw the border (wider line)
      canvas.drawLine(
        Offset(viewPosition.dx - crossSize, viewPosition.dy),
        Offset(viewPosition.dx + crossSize, viewPosition.dy),
        borderPaint,
      );
      canvas.drawLine(
        Offset(viewPosition.dx, viewPosition.dy - crossSize),
        Offset(viewPosition.dx, viewPosition.dy + crossSize),
        borderPaint,
      );

      // Then, draw the inner cross (thinner line)
      canvas.drawLine(
        Offset(viewPosition.dx - crossSize, viewPosition.dy),
        Offset(viewPosition.dx + crossSize, viewPosition.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(viewPosition.dx, viewPosition.dy - crossSize),
        Offset(viewPosition.dx, viewPosition.dy + crossSize),
        crossPaint,
      );
    }

    // Draw all raw detected points and their results for debugging/visualization
    for (int i = 0; i < boardPoints.length; i++) {
      final BoardPoint point = boardPoints[i];
      final Offset rawViewPosition = Offset(point.x * scaleX, point.y * scaleY);

      // First, draw a point marker (small circle to easily see the raw point location)
      final Paint pointMarkerPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.6) // Use withOpacity
        ..style = PaintingStyle.fill; // Fill for visibility
      // ..strokeWidth = 1.0; // Not needed for fill

      canvas.drawCircle(
        rawViewPosition,
        3.0, // Fixed small size for marker
        pointMarkerPaint,
      );

      // Add index label for the point
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          rawViewPosition.dx - textPainter.width / 2,
          rawViewPosition.dy - textPainter.height / 2,
        ),
      );

      // Draw the piece recognition result circle around the raw point
      final PieceColor? color = resultMap[i];
      if (color != null && color != PieceColor.none) {
        final Paint resultCirclePaint = Paint()
          ..color = color == PieceColor.white ? Colors.green : Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        // Use the point's detected radius value for the circle size, scaled
        final double radius = point.radius *
            scaleX; // Using scaleX for simplicity, adjust if needed

        canvas.drawCircle(
          rawViewPosition,
          radius,
          resultCirclePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PieceOverlayPainter oldDelegate) =>
      oldDelegate.boardPoints != boardPoints ||
      oldDelegate.resultMap != resultMap ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.boardRect != boardRect;
}
