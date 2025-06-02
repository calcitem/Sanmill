// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// analysis_renderer.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/database/database.dart';
import '../../../shared/services/environment_config.dart';
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
  // The tolerance for considering values as "equal" (for floating point comparisons)
  static const double valueTolerance = 0.001;

  static void render(Canvas canvas, Size size, double squareSize) {
    if (!AnalysisMode.isEnabled || AnalysisMode.analysisResults.isEmpty) {
      return;
    }

    // Debug: Log analysis results in dev mode
    if (EnvironmentConfig.devMode) {
      logger
          .i("Analysis results count: ${AnalysisMode.analysisResults.length}");
      for (final MoveAnalysisResult result in AnalysisMode.analysisResults) {
        logger.i("Move: ${result.move}, Outcome: ${result.outcome.name}, "
            "Value: ${result.outcome.valueStr}, Steps: ${result.outcome.stepCount}");
      }
    }

    // Sort analysis results based on value for advantage/disadvantage outcomes
    final List<MoveAnalysisResult> sortedResults =
        _getSortedResults(AnalysisMode.analysisResults);

    // Determine the best value to find tied first place results
    final double? bestValue = _getBestValue(sortedResults);

    // Check if we're in "flying" mode and should only show best moves
    final bool isFlyingMode = _shouldFilterToOnlyBestMoves();

    // If in flying mode, only keep moves with the best value
    List<MoveAnalysisResult> resultsToRender = sortedResults;
    if (isFlyingMode && bestValue != null) {
      resultsToRender = sortedResults.where((MoveAnalysisResult result) {
        // Keep only results that are tied for first place
        if (result.outcome.valueStr == null ||
            result.outcome.valueStr!.isEmpty) {
          return false;
        }

        try {
          final double resultValue = double.parse(result.outcome.valueStr!);
          // Check if this value is equal to the best value (within tolerance)
          return (resultValue - bestValue).abs() < valueTolerance;
        } catch (e) {
          logger.w("Error parsing result value for flying mode filtering: $e");
          return false;
        }
      }).toList();

      // If filtering resulted in empty list, fallback to the best result
      if (resultsToRender.isEmpty && sortedResults.isNotEmpty) {
        resultsToRender = <MoveAnalysisResult>[sortedResults.first];
      }
    }

    for (int i = 0; i < resultsToRender.length; i++) {
      final MoveAnalysisResult result = resultsToRender[i];

      // Determine if this is a top result (tied for first place)
      final bool isTopResult = _isTopResult(result, bestValue);

      // Parse the move format to determine the visualization type
      final AnalysisResultType resultType = _determineResultType(result.move);

      switch (resultType) {
        case AnalysisResultType.place:
          // Draw mark for place move in standard notation
          if (result.move.length == 2 &&
              RegExp(r'^[a-g][1-7]$').hasMatch(result.move)) {
            // Get position on board using standard notation
            final Offset position =
                _getPositionFromStandardNotation(result.move, size);

            // Draw mark based on the outcome (win/draw/loss)
            _drawOutcomeMark(canvas, position, result.outcome, squareSize * 0.4,
                isTopResult);
          } else {
            logger.w("Failed to parse place move: ${result.move}");
          }
          break;

        case AnalysisResultType.move:
          // Draw an arrow for movement
          _drawMoveArrow(
              canvas, result.move, result.outcome, size, isTopResult);
          break;

        case AnalysisResultType.remove:
          // Draw a circle for removal candidate (changed from cross to circle)
          _drawRemoveCircle(canvas, result.move, result.outcome, size,
              squareSize * 0.5, isTopResult);
          break;
      }
    }
  }

  /// Get the best evaluation value from sorted results
  static double? _getBestValue(List<MoveAnalysisResult> sortedResults) {
    // If there are no results, return null
    if (sortedResults.isEmpty) {
      return null;
    }

    // Try to get the value from the first sorted result
    final MoveAnalysisResult firstResult = sortedResults.first;
    if (firstResult.outcome.valueStr == null ||
        firstResult.outcome.valueStr!.isEmpty) {
      return null;
    }

    try {
      return double.parse(firstResult.outcome.valueStr!);
    } catch (e) {
      logger.w("Error parsing first result value: $e");
      return null;
    }
  }

  /// Check if a result is tied for first place
  static bool _isTopResult(MoveAnalysisResult result, double? bestValue) {
    // If we couldn't determine a best value, all results use normal width
    if (bestValue == null) {
      return true;
    }

    // If result has no value, it's not a top result
    if (result.outcome.valueStr == null || result.outcome.valueStr!.isEmpty) {
      return false;
    }

    try {
      final double resultValue = double.parse(result.outcome.valueStr!);
      // Check if this value is equal to the best value (within tolerance)
      return (resultValue - bestValue).abs() < valueTolerance;
    } catch (e) {
      logger.w("Error parsing result value: $e");
      return false;
    }
  }

  /// Sort analysis results based on their values for advantage/disadvantage outcomes
  static List<MoveAnalysisResult> _getSortedResults(
      List<MoveAnalysisResult> results) {
    // Clone the list to avoid modifying the original
    final List<MoveAnalysisResult> sortedResults =
        List<MoveAnalysisResult>.from(results);

    // Sort the results based on their numerical evaluation values
    sortedResults.sort((MoveAnalysisResult a, MoveAnalysisResult b) {
      // Handle cases where valueStr is null or empty
      if (a.outcome.valueStr == null || a.outcome.valueStr!.isEmpty) {
        return 1;
      }
      if (b.outcome.valueStr == null || b.outcome.valueStr!.isEmpty) {
        return -1;
      }

      // Parse values as doubles for proper sorting
      try {
        final double aValue = double.parse(a.outcome.valueStr!);
        final double bValue = double.parse(b.outcome.valueStr!);

        // Sort in descending order (highest value first)
        return bValue.compareTo(aValue);
      } catch (e) {
        // If parsing fails, keep original order
        logger.w("Error parsing analysis values: $e");
        return 0;
      }
    });

    return sortedResults;
  }

  /// Determine if dash pattern should be used based on outcome
  static bool _shouldUseDashPattern(GameOutcome outcome) {
    return outcome == GameOutcome.advantage ||
        outcome == GameOutcome.disadvantage;
  }

  /// Get stroke width based on outcome and whether it's a top result
  static double _getStrokeWidth(GameOutcome outcome, bool isTopResult) {
    // Base stroke width
    const double normalWidth = 2.5;
    const double reducedWidth = 1.5;

    // For advantage/disadvantage, use normal width only for top results
    if (outcome == GameOutcome.advantage ||
        outcome == GameOutcome.disadvantage) {
      return isTopResult ? normalWidth : reducedWidth;
    }

    // For win/draw/loss, always use normal width
    return normalWidth;
  }

  /// Draw a circle indicating the outcome of a move
  static void _drawOutcomeMark(
    Canvas canvas,
    Offset position,
    GameOutcome outcome,
    double radius,
    bool isTopResult,
  ) {
    final bool useDashPattern = _shouldUseDashPattern(outcome);
    final double strokeWidth = _getStrokeWidth(outcome, isTopResult);

    final Paint paint = Paint()
      ..color = AnalysisMode.getColorForOutcome(outcome).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Draw circle for the outcome - with dash pattern if needed
    if (useDashPattern) {
      _drawDashedCircle(
        canvas,
        position,
        radius,
        paint.color,
        strokeWidth: strokeWidth,
      );
    } else {
      canvas.drawCircle(position, radius, paint);
    }

    // Draw symbol inside the circle based on outcome
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: _getDisplaySymbolForOutcome(outcome),
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
    bool isTopResult,
  ) {
    //logger.i(
    //    "Move: $moveStr, Outcome: ${outcome.runtimeType}, Value: ${outcome.valueStr}");

    // Parse standard notation move format like "a1-a4", "d5-e5"
    if (!moveStr.contains('-') || moveStr.length != 5) {
      return;
    }

    final List<String> squares = moveStr.split('-');
    if (squares.length != 2) {
      return;
    }

    final String fromSquare = squares[0];
    final String toSquare = squares[1];

    // Convert square notation to positions using standard notation
    final Offset startPos = _getPositionFromStandardNotation(fromSquare, size);
    final Offset endPos = _getPositionFromStandardNotation(toSquare, size);

    // Get color based on outcome
    final Color arrowColor = AnalysisMode.getColorForOutcome(outcome);

    // Set opacity based on outcome
    final double opacity = AnalysisMode.getOpacityForOutcome(outcome);

    // Determine if dashed pattern should be used
    final bool useDashPattern = _shouldUseDashPattern(outcome);

    // Get stroke width based on importance
    final double strokeWidth = _getStrokeWidth(outcome, isTopResult);

    // Draw arrow
    _drawArrow(
      canvas,
      startPos,
      endPos,
      arrowColor.withValues(alpha: opacity),
      useDashPattern: useDashPattern,
      strokeWidth: strokeWidth,
    );

    // Draw step count next to the arrow if available
    final int? stepCount = outcome.stepCount;
    if (stepCount != null && stepCount > 0) {
      final TextPainter stepTextPainter = TextPainter(
        text: TextSpan(
          text: stepCount.toString(),
          style: TextStyle(
            color: arrowColor, // Use arrowColor for consistency
            fontSize: 12, // Adjust font size as needed
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      stepTextPainter.layout();

      // Calculate the midpoint of the arrow
      final Offset midPoint = Offset(
        (startPos.dx + endPos.dx) / 2,
        (startPos.dy + endPos.dy) / 2,
      );

      // Calculate a perpendicular offset to move the text away from the arrow
      // The direction of the offset depends on the arrow's angle to avoid overlap
      // A simple approach is to offset it consistently, e.g., upwards or to the side
      // For a more robust solution, one might consider the arrow's angle
// Horizontal offset from midpoint
// Center vertically by default, adjust as needed

      // Adjust offset based on arrow direction to prevent text from being drawn over the arrow line
      // This is a simplified logic, might need refinement for all arrow angles
      final double angle = (endPos - startPos).direction;
      double textX = midPoint.dx;
      double textY = midPoint.dy;

      // If arrow is more horizontal, place text above/below
      // If arrow is more vertical, place text to the left/right
      if (cos(angle).abs() > sin(angle).abs()) {
        // More horizontal
        textY = midPoint.dy -
            stepTextPainter.height -
            5; // Place above, 5 is padding
        textX = midPoint.dx - stepTextPainter.width / 2;
      } else {
        // More vertical
        textX = midPoint.dx + 10; // Place to the right, 10 is padding
        textY = midPoint.dy - stepTextPainter.height / 2;
        // Potentially check if 'endPos' is above or below 'startPos' to decide left/right better
        if (endPos.dx < startPos.dx) {
          // If arrow points left, place text to its left
          textX = midPoint.dx - stepTextPainter.width - 10;
        }
      }

      final Offset stepTextOffset = Offset(textX, textY);

      stepTextPainter.paint(canvas, stepTextOffset);
    }
  }

  /// Draw a circle around a piece that is a removal candidate
  static void _drawRemoveCircle(
    Canvas canvas,
    String moveStr,
    GameOutcome outcome,
    Size size,
    double radius,
    bool isTopResult,
  ) {
    // Parse standard notation remove moves like "xa1", "xd5"
    if (!moveStr.startsWith('x') || moveStr.length != 3) {
      logger.w("Failed to parse remove move: $moveStr");
      return;
    }

    // Extract square notation (e.g., "a1", "d5" from "xa1", "xd5")
    final String squareNotation = moveStr.substring(1);

    // Get position on board using standard notation
    final Offset position =
        _getPositionFromStandardNotation(squareNotation, size);

    // Get color based on outcome
    final Color circleColor = AnalysisMode.getColorForOutcome(outcome);

    // Set opacity based on outcome
    final double opacity = AnalysisMode.getOpacityForOutcome(outcome);

    // Determine if dashed pattern should be used and get stroke width
    final bool useDashPattern = _shouldUseDashPattern(outcome);
    final double strokeWidth = _getStrokeWidth(outcome, isTopResult);

    // Draw a circle with appropriate line style to highlight removal candidate
    if (useDashPattern) {
      _drawDashedCircle(
        canvas,
        position,
        radius,
        circleColor.withValues(alpha: opacity),
        strokeWidth: strokeWidth,
        dashLength: 6.0,
      );
    } else {
      final Paint circlePaint = Paint()
        ..color = circleColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawCircle(position, radius, circlePaint);
    }

    // Draw step count above the circle if available
    final int? stepCount = outcome.stepCount;
    if (stepCount != null && stepCount > 0) {
      final TextPainter stepTextPainter = TextPainter(
        text: TextSpan(
          text: stepCount.toString(),
          style: TextStyle(
            color: circleColor,
            fontSize: radius * 0.7, // Adjust font size as needed
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      stepTextPainter.layout();

      // Position the text above the circle
      final Offset stepTextOffset = Offset(
        position.dx - stepTextPainter.width / 2,
        position.dy -
            radius -
            stepTextPainter.height -
            2, // 2 is a small padding
      );

      stepTextPainter.paint(canvas, stepTextOffset);
    }
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
  static void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    bool useDashPattern = false,
    double strokeWidth = 3.0,
  }) {
    // Define arrow parameters
    const double arrowLength = 15.0; // Length from arrow tip to the base center
    const double arrowWidth = 12.0; // Maximum width of the arrow tip

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

    // Draw the main line - dashed if needed
    if (useDashPattern) {
      _drawDashedLine(canvas, start, adjustedEnd, paint);
    } else {
      canvas.drawLine(start, adjustedEnd, paint);
    }

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

  /// Draw a dashed line between two points
  static void _drawDashedLine(
      Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dashLength = 8.0;
    const double gapLength = 4.0;

    // Calculate the line length and direction
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double distance = sqrt(dx * dx + dy * dy);

    // Calculate unit vector along the line direction
    final double unitX = dx / distance;
    final double unitY = dy / distance;

    // Calculate total number of segments (dash + gap)
    final int segmentCount = (distance / (dashLength + gapLength)).floor();

    // Draw each dash
    double currentX = start.dx;
    double currentY = start.dy;

    for (int i = 0; i < segmentCount; i++) {
      // Calculate dash end point
      final double dashEndX = currentX + unitX * dashLength;
      final double dashEndY = currentY + unitY * dashLength;

      // Draw the dash
      canvas.drawLine(
        Offset(currentX, currentY),
        Offset(dashEndX, dashEndY),
        paint,
      );

      // Move to the start of the next dash
      currentX = dashEndX + unitX * gapLength;
      currentY = dashEndY + unitY * gapLength;
    }

    // Draw remaining portion if any
    final double remainingDistance =
        distance - segmentCount * (dashLength + gapLength);
    if (remainingDistance > 0) {
      final double dashPortion = min(remainingDistance, dashLength);
      canvas.drawLine(
        Offset(currentX, currentY),
        Offset(currentX + unitX * dashPortion, currentY + unitY * dashPortion),
        paint,
      );
    }
  }

  /// Determine the type of analysis result based on the move format
  static AnalysisResultType _determineResultType(String move) {
    if (move.startsWith('x')) {
      // Standard notation: remove moves start with 'x' (e.g., "xa1", "xd5")
      return AnalysisResultType.remove;
    } else if (move.contains('-') &&
        move.length == 5 &&
        RegExp(r'^[a-g][1-7]-[a-g][1-7]$').hasMatch(move)) {
      // Standard notation: move format like "a1-a4", "d5-e5"
      return AnalysisResultType.move;
    } else if (move.length == 2 && RegExp(r'^[a-g][1-7]$').hasMatch(move)) {
      // Standard notation: place format like "d5", "a1"
      return AnalysisResultType.place;
    } else {
      // Fallback to place for unknown formats
      return AnalysisResultType.place;
    }
  }

  /// Get a symbol to display based on the outcome
  static String _getSymbolForOutcome(GameOutcome outcome) {
    // For the standard game outcomes, return fixed symbols
    switch (outcome) {
      case GameOutcome.win:
        return ''; // Win symbol
      case GameOutcome.draw:
        return ''; // Draw symbol
      case GameOutcome.loss:
        return ''; // Loss symbol
      case GameOutcome.advantage:
        // For advantage, check if we have a value string from engine
        if (EnvironmentConfig.devMode &&
            outcome.valueStr != null &&
            outcome.valueStr!.isNotEmpty) {
          return outcome
              .valueStr!; // Return the numerical evaluation only in dev mode
        }
        return ''; // Default symbol for advantage
      case GameOutcome.disadvantage:
        // For disadvantage, check if we have a value string from engine
        if (EnvironmentConfig.devMode &&
            outcome.valueStr != null &&
            outcome.valueStr!.isNotEmpty) {
          return outcome
              .valueStr!; // Return the numerical evaluation only in dev mode
        }
        return ''; // Default symbol for disadvantage
      case GameOutcome.unknown:
      default:
        // For unknown outcomes, check if we have a value string from engine
        if (EnvironmentConfig.devMode &&
            outcome.valueStr != null &&
            outcome.valueStr!.isNotEmpty) {
          return outcome
              .valueStr!; // Return the numerical evaluation only in dev mode
        }
        return '?'; // Default symbol for unknown
    }
  }

  /// Get a display symbol that includes step count information
  static String _getDisplaySymbolForOutcome(GameOutcome outcome) {
    // Debug logging in dev mode
    if (EnvironmentConfig.devMode) {
      logger.i("Getting display symbol for outcome: ${outcome.name}, "
          "valueStr: ${outcome.valueStr}, stepCount: ${outcome.stepCount}");
    }

    // Check if we have step count information from perfect database
    if (outcome.stepCount != null && outcome.stepCount! > 0) {
      // Debug log in dev mode
      if (EnvironmentConfig.devMode) {
        logger.i(
            "Displaying step count ${outcome.stepCount} for outcome ${outcome.name}");
      }
      // Return step count for perfect database results
      return outcome.stepCount!.toString();
    }

    // Check if we have a valid value string to display
    if (outcome.valueStr != null && outcome.valueStr!.isNotEmpty) {
      // Debug log in dev mode
      if (EnvironmentConfig.devMode) {
        logger.i(
            "Displaying value string '${outcome.valueStr}' for outcome ${outcome.name}");
      }

      // For advantage/disadvantage with numerical values, show the value in dev mode
      if (EnvironmentConfig.devMode &&
          (outcome == GameOutcome.advantage ||
              outcome == GameOutcome.disadvantage)) {
        return outcome.valueStr!;
      }
    }

    // Debug log in dev mode when using fallback
    if (EnvironmentConfig.devMode) {
      logger.i(
          "Using fallback symbol for outcome ${outcome.name}, stepCount: ${outcome.stepCount}");
    }

    // Fall back to regular symbol logic
    final String fallbackSymbol = _getSymbolForOutcome(outcome);

    // If fallback is empty, provide a meaningful default
    if (fallbackSymbol.isEmpty) {
      switch (outcome) {
        case GameOutcome.win:
          return '✓';
        case GameOutcome.draw:
          return '=';
        case GameOutcome.loss:
          return '✗';
        case GameOutcome.advantage:
          return '+';
        case GameOutcome.disadvantage:
          return '-';
        case GameOutcome.unknown:
        default:
          return '?';
      }
    }

    return fallbackSymbol;
  }

  /// Convert standard notation square (like "a1", "d5") to board position
  static Offset _getPositionFromStandardNotation(
      String squareNotation, Size size) {
    // Validate standard notation format
    if (squareNotation.length != 2 ||
        !RegExp(r'^[a-g][1-7]$').hasMatch(squareNotation)) {
      logger.w("Invalid standard notation: $squareNotation");
      return size.center(Offset.zero);
    }
    // Convert to square using existing functions
    final int square = notationToSquare(squareNotation);

    // Use pointFromSquare to get the actual position
    return pointFromSquare(square, size);
  }

  /// Check if we should filter to only show the best moves
  /// This happens when the player is in "flying" mode
  static bool _shouldFilterToOnlyBestMoves() {
    // Check if flying is enabled in rules and the current player has few enough pieces
    return DB().ruleSettings.mayFly &&
        GameController().position.phase == Phase.moving &&
        GameController()
                .position
                .pieceOnBoardCount[GameController().position.sideToMove]! <=
            DB().ruleSettings.flyPieceCount;
  }

  /// Get display text for analysis result including step count information
  static String getAnalysisDisplayText(MoveAnalysisResult result) {
    if (result.outcome.stepCount != null) {
      // Use the new displayString that includes step information
      return "${result.move}: ${result.outcome.displayString}";
    } else {
      // Fallback to traditional display
      return "${result.move}: ${result.outcome.name}${result.outcome.valueStr != null ? " (${result.outcome.valueStr})" : ""}";
    }
  }

  /// Check if analysis result has perfect database step information
  static bool hasPerfectDatabaseInfo(MoveAnalysisResult result) {
    return result.outcome.stepCount != null && result.outcome.stepCount! > 0;
  }
}
