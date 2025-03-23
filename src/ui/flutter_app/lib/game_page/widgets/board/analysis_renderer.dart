// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// analysis_renderer.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/services/logger.dart';
import '../../services/analysis_mode.dart';
import '../../services/mill.dart';
import '../../services/painters/painters.dart'; // Add this import for access to board coordinate helpers

/// Type of analysis result visualization
enum AnalysisResultType {
  place, // Place a piece on a point
  move, // Move a piece from one point to another
  remove // Remove a piece from a point
}

/// Renderer for analysis marks on the board
class AnalysisRenderer {
  static void render(Canvas canvas, Size size, double squareSize) {
    if (!AnalysisMode.isEnabled || AnalysisMode.analysisResults.isEmpty) {
      return;
    }

    for (final MoveAnalysisResult result in AnalysisMode.analysisResults) {
      // Parse the move format to determine the visualization type
      final AnalysisResultType resultType = _determineResultType(result.move);

      switch (resultType) {
        case AnalysisResultType.place:
          // Get position on board for the move
          final Offset position =
              _getPositionFromCoordinates(result.move, size);

          // Draw mark based on the outcome (win/draw/loss)
          _drawOutcomeMark(canvas, position, result.outcome, squareSize * 0.4);
          break;

        case AnalysisResultType.move:
          // Draw an arrow for movement
          _drawMoveArrow(canvas, result.move, result.outcome, size);
          break;

        case AnalysisResultType.remove:
          // Draw a circle for removal candidate (changed from cross to circle)
          _drawRemoveCircle(
              canvas, result.move, result.outcome, size, squareSize * 0.5);
          break;
      }
    }
  }

  /// Determine the type of analysis result based on the move format
  static AnalysisResultType _determineResultType(String move) {
    if (move.contains('->')) {
      return AnalysisResultType.move;
    } else if (move.startsWith('-')) {
      return AnalysisResultType.remove;
    } else {
      return AnalysisResultType.place;
    }
  }

  /// Draw a circle indicating the outcome of a move
  static void _drawOutcomeMark(
    Canvas canvas,
    Offset position,
    GameOutcome outcome,
    double radius,
  ) {
    final Paint paint = Paint()
      ..color = AnalysisMode.getColorForOutcome(outcome).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Draw circle for the outcome
    canvas.drawCircle(position, radius, paint);

    // Draw symbol inside the circle based on outcome
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: _getSymbolForOutcome(outcome),
        style: TextStyle(
          color: AnalysisMode.getColorForOutcome(outcome),
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Center the text in the circle
    final Offset textOffset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, textOffset);
  }

  /// Draw an arrow indicating a move with outcome
  static void _drawMoveArrow(
    Canvas canvas,
    String moveStr,
    GameOutcome outcome,
    Size size,
  ) {
    // Parse from and to coordinates from format "(3,8)->(3,7)"
    final RegExp movePattern =
        RegExp(r'\(([\d]+),([\d]+)\)->\(([\d]+),([\d]+)\)');
    final Match? match = movePattern.firstMatch(moveStr);

    if (match == null || match.groupCount < 4) {
      return;
    }

    // Extract coordinates
    final int fromX = int.parse(match.group(1)!);
    final int fromY = int.parse(match.group(2)!);
    final int toX = int.parse(match.group(3)!);
    final int toY = int.parse(match.group(4)!);

    // Get positions on board
    final Offset startPos =
        _getPositionFromCoordinates("($fromX,$fromY)", size);
    final Offset endPos = _getPositionFromCoordinates("($toX,$toY)", size);

    // Get color based on outcome
    final Color arrowColor = AnalysisMode.getColorForOutcome(outcome);

    // Set opacity based on outcome
    final double opacity = AnalysisMode.getOpacityForOutcome(outcome);

    // Draw arrow
    _drawArrow(canvas, startPos, endPos, arrowColor.withValues(alpha: opacity));
  }

  /// Draw a circle around a piece that is a removal candidate
  /// Changed from drawing a cross to drawing a circle with the outcome color
  static void _drawRemoveCircle(
    Canvas canvas,
    String moveStr,
    GameOutcome outcome,
    Size size,
    double radius,
  ) {
    // Parse coordinates from format "-(3,8)"
    final RegExp removePattern = RegExp(r'-\((\d+),(\d+)\)');
    final Match? match = removePattern.firstMatch(moveStr);

    if (match == null || match.groupCount < 2) {
      // Log for debugging
      logger.w("Failed to match remove pattern in: $moveStr");
      return;
    }

    // Extract coordinates
    final int x = int.parse(match.group(1)!);
    final int y = int.parse(match.group(2)!);

    // Get position on board
    final Offset position = _getPositionFromCoordinates("($x,$y)", size);

    // Get color based on outcome
    final Color circleColor = AnalysisMode.getColorForOutcome(outcome);

    // Set opacity based on outcome
    final double opacity = AnalysisMode.getOpacityForOutcome(outcome);

    // Draw a circle with dashed lines to highlight removal candidate
    _drawDashedCircle(
      canvas,
      position,
      radius,
      circleColor.withValues(alpha: opacity),
      strokeWidth: 3.0,
      dashLength: 6.0,
    );

    // Draw a smaller circle with the outcome symbol inside
    final Paint smallCirclePaint = Paint()
      ..color = circleColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(position, radius * 0.5, smallCirclePaint);

    // Draw symbol for outcome (+ for win, = for draw, - for loss)
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: _getSymbolForOutcome(outcome),
        style: TextStyle(
          color: circleColor,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Center the text in the circle
    final Offset textOffset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, textOffset);
  }

  /// Draw a dashed circle around a position
  static void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    double strokeWidth = 2.0,
    double dashLength = 5.0,
    double gapLength = 3.0,
  }) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Calculate the circumference of the circle
    final double circumference = 2 * pi * radius;

    // Calculate the number of dashes that will fit around the circle
    final int dashCount = (circumference / (dashLength + gapLength)).round();

    // Calculate the angle for each dash
    final double dashAngle = 2 * pi / dashCount;

    // Draw each dash
    for (int i = 0; i < dashCount; i++) {
      final double startAngle = i * dashAngle;
      final double endAngle =
          startAngle + (dashLength / circumference) * 2 * pi;

      final Path dashPath = Path()
        ..addArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          endAngle - startAngle,
        );

      canvas.drawPath(dashPath, paint);
    }
  }

  /// Draw an arrow from start to end position
  static void _drawArrow(Canvas canvas, Offset start, Offset end, Color color) {
    // Define arrow parameters
    const double arrowLength = 15.0; // Length from arrow tip to the base center
    const double arrowWidth = 12.0; // Maximum width of the arrow tip
    const double strokeWidth = 3.0;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Calculate the angle of the line's direction
    final double angle = (end - start).direction;

    // Adjust the endpoint so that the arrow head does not extend beyond the target point
    final Offset adjustedEnd = end -
        Offset(
          arrowLength * cos(angle),
          arrowLength * sin(angle),
        );

    // Draw the main line
    canvas.drawLine(start, adjustedEnd, paint);

    // Draw a solid circle at the start point (arrow tail)
    final Paint circlePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, arrowWidth / 4, circlePaint);

    // Calculate a perpendicular vector to the line's direction
    final Offset perpendicular = Offset(-sin(angle), cos(angle));

    // Determine the two base points of the arrow head
    final Offset arrowBaseLeft =
        adjustedEnd + (perpendicular * (arrowWidth / 2));
    final Offset arrowBaseRight =
        adjustedEnd - (perpendicular * (arrowWidth / 2));

    // Construct a filled triangle for the arrow head
    final Path arrowPath = Path()
      ..moveTo(end.dx, end.dy) // Arrow tip
      ..lineTo(arrowBaseLeft.dx, arrowBaseLeft.dy)
      ..lineTo(arrowBaseRight.dx, arrowBaseRight.dy)
      ..close();

    // Use a paint with fill style for the arrow head
    final Paint arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    // Draw the filled arrow head
    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Get a symbol to display based on the outcome
  static String _getSymbolForOutcome(GameOutcome outcome) {
    switch (outcome) {
      case GameOutcome.win:
        return '+';
      case GameOutcome.draw:
        return '=';
      case GameOutcome.loss:
        return '−';
      case GameOutcome.advantage:
        return '↑'; // Up arrow for advantage
      case GameOutcome.disadvantage:
        return '↓'; // Down arrow for disadvantage
      case GameOutcome.unknown:
        return '?';
    }
  }

  /// Convert move coordinates like "(2,1)" to board position
  static Offset _getPositionFromCoordinates(String move, Size size) {
    // Extract coordinates from move string format like "(2,1)"
    final RegExp coordPattern = RegExp(r'\((\d+),(\d+)\)');
    final Match? match = coordPattern.firstMatch(move);

    if (match != null && match.groupCount == 2) {
      final int x = int.parse(match.group(1)!);
      final int y = int.parse(match.group(2)!);

      // Map to point index in the board's coordinate system
      final int pointIndex = _mapCoordinatesToPointIndex(x, y);

      // Use the pointFromIndex function to get the actual position
      return pointFromIndex(pointIndex, size);
    }

    // Fallback to center if parsing fails
    logger.w("Failed to parse coordinates from: $move");
    return size.center(Offset.zero);
  }

  /// Map engine coordinates (x,y) to point index on the board
  static int _mapCoordinatesToPointIndex(int x, int y) {
    // Convert from (file, rank) to square using existing functions
    // First convert from (file, rank) to square number
    final int square = makeSquare(x, y);

    // Then convert from square number to board index
    final int? index = squareToIndex[square];

    // Return the index if found, or -1
    return index ?? -1;
  }
}
