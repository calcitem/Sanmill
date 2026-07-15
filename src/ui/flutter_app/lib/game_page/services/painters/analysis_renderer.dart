// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_renderer.dart

part of '../../../game_page/services/painters/painters.dart';

/// Type of analysis result visualization.
enum AnalysisResultType {
  /// Place a piece on a point.
  place,

  /// Move a piece from one point to another.
  move,

  /// Remove a piece from a point.
  remove,
}

/// Renderer for the analysis overlay.
///
/// Draws one mark per analysed legal move: a circle for placements, an arrow
/// for moves, and a circle around removal candidates, colored by the
/// win/draw/loss verdict.  Reads its data from [AnalysisMode]; rendering is a
/// no-op when the overlay is disabled or empty.
class AnalysisRenderer {
  /// Tolerance for treating two evaluation values as equal.
  static const double valueTolerance = 0.001;

  static const double _engineBestMoveStrokeWidth = 5.0;
  static const double _engineSecondaryMoveStrokeWidth = 3.25;
  static const Color _engineBestMoveColor = Color(0xFF1E88E5);
  static const Color _engineSecondaryMoveColor = Color(0xFF546E7A);
  static const Color _engineThreatMoveColor = Color(0xFFD32F2F);
  static final RegExp _standardSquarePattern = RegExp(r'^[a-g][1-7]$');
  static final RegExp _standardMovePattern = RegExp(r'^[a-g][1-7]-[a-g][1-7]$');

  static void render(Canvas canvas, Size size, double squareSize) {
    if (!AnalysisMode.isEnabled) {
      return;
    }

    final bool hasAnalysisResults = AnalysisMode.analysisResults.isNotEmpty;
    final bool hasEngineLineResults =
        AnalysisMode.isFullAnalysis &&
        AnalysisMode.hasEngineLinesSource &&
        AnalysisMode.analysisLineResults.isNotEmpty;
    if (!hasAnalysisResults && !hasEngineLineResults) {
      return;
    }

    if (hasAnalysisResults) {
      if (AnalysisMode.isThreatMode) {
        _renderNormalBestMove(canvas, size, squareSize);
      }
      _renderResults(
        canvas,
        size,
        squareSize,
        AnalysisMode.analysisResults,
        useThreatColors: AnalysisMode.isThreatMode,
      );
    }
    _renderEngineLineHighlights(canvas, size, squareSize);
  }

  static void _renderNormalBestMove(
    Canvas canvas,
    Size size,
    double squareSize,
  ) {
    final List<MoveAnalysisResult> normalResults =
        AnalysisMode.normalEngineAnalysisResults;
    if (normalResults.isEmpty) {
      return;
    }
    _renderResults(canvas, size, squareSize, <MoveAnalysisResult>[
      _getSortedResults(normalResults).first,
    ], useThreatColors: false);
  }

  static void _renderResults(
    Canvas canvas,
    Size size,
    double squareSize,
    List<MoveAnalysisResult> results, {
    required bool useThreatColors,
  }) {
    if (results.isEmpty) {
      return;
    }

    final List<MoveAnalysisResult> sortedResults = _getSortedResults(results);

    final double? bestValue = _getBestValue(sortedResults);

    // In flying mode only the best moves are shown, matching the legacy
    // behaviour of focusing the overlay when the player can fly.
    final bool isFlyingMode = _shouldFilterToOnlyBestMoves();
    List<MoveAnalysisResult> resultsToRender = sortedResults;
    if (isFlyingMode && bestValue != null) {
      resultsToRender = sortedResults.where((MoveAnalysisResult result) {
        if (result.outcome.valueStr == null ||
            result.outcome.valueStr!.isEmpty) {
          return false;
        }
        final double? resultValue = double.tryParse(result.outcome.valueStr!);
        if (resultValue == null) {
          return false;
        }
        return (resultValue - bestValue).abs() < valueTolerance;
      }).toList();
      if (resultsToRender.isEmpty && sortedResults.isNotEmpty) {
        resultsToRender = <MoveAnalysisResult>[sortedResults.first];
      }
    }

    for (final MoveAnalysisResult result in resultsToRender) {
      final bool isTopResult = _isTopResult(result, bestValue);
      final AnalysisResultType resultType = _determineResultType(result.move);

      switch (resultType) {
        case AnalysisResultType.place:
          if (result.move.length == 2 &&
              _standardSquarePattern.hasMatch(result.move)) {
            final Offset position = _getPositionFromStandardNotation(
              result.move,
              size,
            );
            _drawOutcomeMark(
              canvas,
              position,
              result.outcome,
              squareSize * 0.4,
              isTopResult,
              result.move,
              useThreatColors: useThreatColors,
            );
          } else {
            logger.w("Failed to parse place move: ${result.move}");
          }
          break;

        case AnalysisResultType.move:
          _drawMoveArrow(
            canvas,
            result.move,
            result.outcome,
            size,
            isTopResult,
            useThreatColors: useThreatColors,
          );
          break;

        case AnalysisResultType.remove:
          _drawRemoveCircle(
            canvas,
            result.move,
            result.outcome,
            size,
            squareSize * 0.5,
            isTopResult,
            useThreatColors: useThreatColors,
          );
          break;
      }
    }
  }

  static void _renderEngineLineHighlights(
    Canvas canvas,
    Size size,
    double squareSize,
  ) {
    if (!AnalysisMode.isFullAnalysis ||
        !AnalysisMode.hasEngineLinesSource ||
        !AnalysisMode.showBestMoveArrow ||
        AnalysisMode.analysisLineResults.isEmpty) {
      return;
    }

    final int visibleLineCount = max(1, AnalysisMode.engineLineCount);
    if (AnalysisMode.isThreatMode) {
      final List<MoveAnalysisResult> normalResults = _engineLineResultsToRender(
        AnalysisMode.normalEngineAnalysisResults,
        1,
      );
      if (normalResults.isNotEmpty) {
        _drawEngineLineHighlight(
          canvas,
          normalResults.first,
          size,
          squareSize,
          color: _engineBestMoveColor,
          isPrimary: true,
        );
      }

      final List<MoveAnalysisResult> threatResults = _engineLineResultsToRender(
        AnalysisMode.analysisLineResults,
        visibleLineCount,
      );
      for (int i = 0; i < threatResults.length; i++) {
        _drawEngineLineHighlight(
          canvas,
          threatResults[i],
          size,
          squareSize,
          color: _engineThreatMoveColor,
          isPrimary: i == 0,
        );
      }
      return;
    }

    final List<MoveAnalysisResult> resultsToRender = _engineLineResultsToRender(
      AnalysisMode.analysisLineResults,
      visibleLineCount,
    );
    for (int i = 0; i < resultsToRender.length; i++) {
      _drawEngineLineHighlight(
        canvas,
        resultsToRender[i],
        size,
        squareSize,
        color: i == 0 ? _engineBestMoveColor : _engineSecondaryMoveColor,
        isPrimary: i == 0,
      );
    }
  }

  static List<MoveAnalysisResult> _engineLineResultsToRender(
    List<MoveAnalysisResult> results,
    int count,
  ) {
    assert(count >= 1, 'Engine line overlay count must be positive.');
    if (results.isEmpty) {
      return const <MoveAnalysisResult>[];
    }
    return results.take(min(results.length, count)).toList(growable: false);
  }

  static void _drawEngineLineHighlight(
    Canvas canvas,
    MoveAnalysisResult result,
    Size size,
    double squareSize, {
    required Color color,
    required bool isPrimary,
  }) {
    final String move = _rootMoveForLine(result);
    final Color highlightColor = color.withValues(
      alpha: isPrimary ? 0.82 : 0.6,
    );
    final double strokeWidth = isPrimary
        ? _engineBestMoveStrokeWidth
        : _engineSecondaryMoveStrokeWidth;

    switch (_determineResultType(move)) {
      case AnalysisResultType.move:
        _drawEngineMoveArrow(
          canvas,
          move,
          highlightColor,
          size,
          strokeWidth: strokeWidth,
        );
        break;
      case AnalysisResultType.place:
        _drawEngineTargetMark(
          canvas,
          move,
          highlightColor,
          size,
          squareSize * 0.48,
          strokeWidth: strokeWidth,
        );
        break;
      case AnalysisResultType.remove:
        _drawEngineTargetMark(
          canvas,
          move.substring(1),
          highlightColor,
          size,
          squareSize * 0.58,
          strokeWidth: strokeWidth,
        );
        break;
    }
  }

  static String _rootMoveForLine(MoveAnalysisResult result) {
    final String move = result.line.isNotEmpty
        ? result.line.first
        : result.move;
    assert(move.trim().isNotEmpty, 'Engine line result must contain a move.');
    return move.trim();
  }

  static void _drawEngineMoveArrow(
    Canvas canvas,
    String moveStr,
    Color color,
    Size size, {
    required double strokeWidth,
  }) {
    assert(
      _standardMovePattern.hasMatch(moveStr),
      'Engine line move must use from-to notation.',
    );
    if (!_standardMovePattern.hasMatch(moveStr)) {
      return;
    }

    final List<String> squares = moveStr.split('-');
    final Offset startPos = _getPositionFromStandardNotation(squares[0], size);
    final Offset endPos = _getPositionFromStandardNotation(squares[1], size);
    _drawArrow(canvas, startPos, endPos, color, strokeWidth: strokeWidth);
  }

  static void _drawEngineTargetMark(
    Canvas canvas,
    String squareNotation,
    Color color,
    Size size,
    double radius, {
    required double strokeWidth,
  }) {
    assert(
      _standardSquarePattern.hasMatch(squareNotation),
      'Engine line target must use standard square notation.',
    );
    if (!_standardSquarePattern.hasMatch(squareNotation)) {
      return;
    }

    final Offset position = _getPositionFromStandardNotation(
      squareNotation,
      size,
    );
    final Paint fillPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(position, radius, fillPaint);
    canvas.drawCircle(position, radius, strokePaint);
  }

  /// Best (highest) evaluation value among the sorted results, if any.
  static double? _getBestValue(List<MoveAnalysisResult> sortedResults) {
    if (sortedResults.isEmpty) {
      return null;
    }
    final MoveAnalysisResult first = sortedResults.first;
    if (first.outcome.valueStr == null || first.outcome.valueStr!.isEmpty) {
      return null;
    }
    return double.tryParse(first.outcome.valueStr!);
  }

  /// Whether [result] ties the best value (rendered with full emphasis).
  static bool _isTopResult(MoveAnalysisResult result, double? bestValue) {
    if (bestValue == null) {
      return true;
    }
    if (result.outcome.valueStr == null || result.outcome.valueStr!.isEmpty) {
      return false;
    }
    final double? value = double.tryParse(result.outcome.valueStr!);
    if (value == null) {
      return false;
    }
    return (value - bestValue).abs() < valueTolerance;
  }

  /// Sort results by descending numeric value (best first).
  static List<MoveAnalysisResult> _getSortedResults(
    List<MoveAnalysisResult> results,
  ) {
    final List<MoveAnalysisResult> sorted = List<MoveAnalysisResult>.from(
      results,
    );
    sorted.sort((MoveAnalysisResult a, MoveAnalysisResult b) {
      if (a.outcome.valueStr == null || a.outcome.valueStr!.isEmpty) {
        return 1;
      }
      if (b.outcome.valueStr == null || b.outcome.valueStr!.isEmpty) {
        return -1;
      }
      final double? aValue = double.tryParse(a.outcome.valueStr!);
      final double? bValue = double.tryParse(b.outcome.valueStr!);
      if (aValue == null || bValue == null) {
        return 0;
      }
      return bValue.compareTo(aValue);
    });
    return sorted;
  }

  /// Whether advantage/disadvantage outcomes should use a dashed pattern.
  static bool _shouldUseDashPattern(AnalysisOutcome outcome) {
    return outcome == AnalysisOutcome.advantage ||
        outcome == AnalysisOutcome.disadvantage;
  }

  static Color _resultColor(
    AnalysisOutcome outcome,
    bool isTopResult, {
    required bool useThreatColors,
  }) {
    if (useThreatColors) {
      return Colors.red.shade600;
    }
    return AnalysisMode.getColorForOutcome(outcome);
  }

  static double _resultOpacity(
    AnalysisOutcome outcome,
    bool isTopResult, {
    required bool useThreatColors,
  }) {
    if (useThreatColors) {
      return isTopResult ? 0.68 : 0.48;
    }
    return AnalysisMode.getOpacityForOutcome(outcome);
  }

  /// Stroke width based on outcome, top-result status, and trap flag.
  static double _getStrokeWidth(
    AnalysisOutcome outcome,
    bool isTopResult, {
    String? move,
  }) {
    const double normalWidth = 2.5;
    const double reducedWidth = 1.5;
    const double trapWidth = 4.0;

    if (move != null && AnalysisMode.isTrapMove(move)) {
      return trapWidth;
    }
    if (outcome == AnalysisOutcome.advantage ||
        outcome == AnalysisOutcome.disadvantage) {
      return isTopResult ? normalWidth : reducedWidth;
    }
    return normalWidth;
  }

  /// Draw a circle and verdict symbol for a placement move.
  static void _drawOutcomeMark(
    Canvas canvas,
    Offset position,
    AnalysisOutcome outcome,
    double radius,
    bool isTopResult,
    String move, {
    required bool useThreatColors,
  }) {
    final bool useDashPattern = _shouldUseDashPattern(outcome);
    final double strokeWidth = _getStrokeWidth(
      outcome,
      isTopResult,
      move: move,
    );

    final Color resultColor = _resultColor(
      outcome,
      isTopResult,
      useThreatColors: useThreatColors,
    );
    final Paint paint = Paint()
      ..color = resultColor.withValues(
        alpha: useThreatColors
            ? _resultOpacity(
                outcome,
                isTopResult,
                useThreatColors: useThreatColors,
              )
            : 0.7,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

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

    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: _getDisplaySymbolForOutcome(outcome),
        style: TextStyle(
          color: resultColor,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final Offset textOffset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  /// Draw an arrow (with optional step-count label) for a move.
  static void _drawMoveArrow(
    Canvas canvas,
    String moveStr,
    AnalysisOutcome outcome,
    Size size,
    bool isTopResult, {
    required bool useThreatColors,
  }) {
    if (!moveStr.contains('-') || moveStr.length != 5) {
      return;
    }
    final List<String> squares = moveStr.split('-');
    if (squares.length != 2) {
      return;
    }

    final Offset startPos = _getPositionFromStandardNotation(squares[0], size);
    final Offset endPos = _getPositionFromStandardNotation(squares[1], size);

    final Color arrowColor = _resultColor(
      outcome,
      isTopResult,
      useThreatColors: useThreatColors,
    );
    final double opacity = _resultOpacity(
      outcome,
      isTopResult,
      useThreatColors: useThreatColors,
    );
    final bool useDashPattern = _shouldUseDashPattern(outcome);
    final double strokeWidth = _getStrokeWidth(
      outcome,
      isTopResult,
      move: moveStr,
    );

    _drawArrow(
      canvas,
      startPos,
      endPos,
      arrowColor.withValues(alpha: opacity),
      useDashPattern: useDashPattern,
      strokeWidth: strokeWidth,
    );

    final int? stepCount = outcome.stepCount;
    if (stepCount != null && stepCount > 0) {
      final TextPainter stepTextPainter = TextPainter(
        text: TextSpan(
          text: stepCount.toString(),
          style: TextStyle(
            color: arrowColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      stepTextPainter.layout();

      final Offset midPoint = Offset(
        (startPos.dx + endPos.dx) / 2,
        (startPos.dy + endPos.dy) / 2,
      );
      final double angle = (endPos - startPos).direction;
      double textX = midPoint.dx;
      double textY = midPoint.dy;
      if (cos(angle).abs() > sin(angle).abs()) {
        textY = midPoint.dy - stepTextPainter.height - 5;
        textX = midPoint.dx - stepTextPainter.width / 2;
      } else {
        textX = midPoint.dx + 10;
        textY = midPoint.dy - stepTextPainter.height / 2;
        if (endPos.dx < startPos.dx) {
          textX = midPoint.dx - stepTextPainter.width - 10;
        }
      }
      stepTextPainter.paint(canvas, Offset(textX, textY));
    }
  }

  /// Draw a circle (with optional step-count label) around a removal target.
  static void _drawRemoveCircle(
    Canvas canvas,
    String moveStr,
    AnalysisOutcome outcome,
    Size size,
    double radius,
    bool isTopResult, {
    required bool useThreatColors,
  }) {
    if (!moveStr.startsWith('x') || moveStr.length != 3) {
      logger.w("Failed to parse remove move: $moveStr");
      return;
    }
    final String squareNotation = moveStr.substring(1);
    final Offset position = _getPositionFromStandardNotation(
      squareNotation,
      size,
    );

    final Color circleColor = _resultColor(
      outcome,
      isTopResult,
      useThreatColors: useThreatColors,
    );
    final double opacity = _resultOpacity(
      outcome,
      isTopResult,
      useThreatColors: useThreatColors,
    );
    final bool useDashPattern = _shouldUseDashPattern(outcome);
    final double strokeWidth = _getStrokeWidth(
      outcome,
      isTopResult,
      move: moveStr,
    );

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

    final int? stepCount = outcome.stepCount;
    if (stepCount != null && stepCount > 0) {
      final TextPainter stepTextPainter = TextPainter(
        text: TextSpan(
          text: stepCount.toString(),
          style: TextStyle(
            color: circleColor,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      stepTextPainter.layout();
      final Offset stepTextOffset = Offset(
        position.dx - stepTextPainter.width / 2,
        position.dy - radius - stepTextPainter.height - 2,
      );
      stepTextPainter.paint(canvas, stepTextOffset);
    }
  }

  /// Draw a dashed circle around [center].
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

    final double circumference = 2 * pi * radius;
    final int dashCount = (circumference / (dashLength + gapLength)).round();
    if (dashCount <= 0) {
      canvas.drawCircle(center, radius, paint);
      return;
    }
    final double dashAngle = 2 * pi / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final double startAngle = i * dashAngle;
      final double sweep = (dashLength / circumference) * 2 * pi;
      final Path dashPath = Path()
        ..addArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweep,
        );
      canvas.drawPath(dashPath, paint);
    }
  }

  /// Draw an arrow from [start] to [end] with a filled head.
  static void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    bool useDashPattern = false,
    double strokeWidth = 2.5,
  }) {
    const double arrowLength = 15.0;
    const double arrowWidth = 12.0;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double angle = (end - start).direction;
    final Offset adjustedEnd =
        end - Offset(arrowLength * cos(angle), arrowLength * sin(angle));

    if (useDashPattern) {
      _drawDashedLine(canvas, start, adjustedEnd, paint);
    } else {
      canvas.drawLine(start, adjustedEnd, paint);
    }

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, arrowWidth / 4, fillPaint);

    final Offset perpendicular = Offset(-sin(angle), cos(angle));
    final Offset arrowBaseLeft =
        adjustedEnd + (perpendicular * (arrowWidth / 2));
    final Offset arrowBaseRight =
        adjustedEnd - (perpendicular * (arrowWidth / 2));
    final Path arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowBaseLeft.dx, arrowBaseLeft.dy)
      ..lineTo(arrowBaseRight.dx, arrowBaseRight.dy)
      ..close();
    canvas.drawPath(arrowPath, fillPaint);
  }

  /// Draw a dashed line between [start] and [end].
  static void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const double dashLength = 8.0;
    const double gapLength = 4.0;

    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double distance = sqrt(dx * dx + dy * dy);
    if (distance == 0) {
      return;
    }
    final double unitX = dx / distance;
    final double unitY = dy / distance;
    final int segmentCount = (distance / (dashLength + gapLength)).floor();

    double currentX = start.dx;
    double currentY = start.dy;
    for (int i = 0; i < segmentCount; i++) {
      final double dashEndX = currentX + unitX * dashLength;
      final double dashEndY = currentY + unitY * dashLength;
      canvas.drawLine(
        Offset(currentX, currentY),
        Offset(dashEndX, dashEndY),
        paint,
      );
      currentX = dashEndX + unitX * gapLength;
      currentY = dashEndY + unitY * gapLength;
    }
    final double remaining = distance - segmentCount * (dashLength + gapLength);
    if (remaining > 0) {
      final double dashPortion = min(remaining, dashLength);
      canvas.drawLine(
        Offset(currentX, currentY),
        Offset(currentX + unitX * dashPortion, currentY + unitY * dashPortion),
        paint,
      );
    }
  }

  /// Classify a move token into a visualization type.
  static AnalysisResultType _determineResultType(String move) {
    if (move.startsWith('x')) {
      return AnalysisResultType.remove;
    } else if (move.contains('-') &&
        move.length == 5 &&
        _standardMovePattern.hasMatch(move)) {
      return AnalysisResultType.move;
    } else if (move.length == 2 && _standardSquarePattern.hasMatch(move)) {
      return AnalysisResultType.place;
    }
    return AnalysisResultType.place;
  }

  /// Symbol shown inside a placement mark, preferring the step count.
  static String _getDisplaySymbolForOutcome(AnalysisOutcome outcome) {
    if (outcome.stepCount != null && outcome.stepCount! > 0) {
      return outcome.stepCount!.toString();
    }
    if (EnvironmentConfig.devMode &&
        outcome.valueStr != null &&
        outcome.valueStr!.isNotEmpty &&
        (outcome == AnalysisOutcome.advantage ||
            outcome == AnalysisOutcome.disadvantage)) {
      return outcome.valueStr!;
    }
    switch (outcome.name) {
      case 'win':
        return '✓';
      case 'draw':
        return '=';
      case 'loss':
        return '✗';
      case 'advantage':
        return '+';
      case 'disadvantage':
        return '-';
      case 'unknown':
      default:
        return '?';
    }
  }

  /// Convert a standard notation square (`a1`, `d5`) to a board position.
  static Offset _getPositionFromStandardNotation(
    String squareNotation,
    Size size,
  ) {
    if (squareNotation.length != 2 ||
        !_standardSquarePattern.hasMatch(squareNotation)) {
      logger.w("Invalid standard notation: $squareNotation");
      return size.center(Offset.zero);
    }
    final int square = notationToSquare(squareNotation);
    return pointFromSquare(square, size);
  }

  /// Whether only the best moves should be shown (flying mode).
  static bool _shouldFilterToOnlyBestMoves() {
    final MillBoardView view = GameController().activeBoardView;
    final RuleSettings rules = GameController().ruleSettingsForActiveBoard;
    if (!rules.mayFly || view.phase != Phase.moving) {
      return false;
    }
    final int onBoard = view.pieceOnBoardCountFor(view.sideToMove);
    return onBoard <= rules.flyPieceCount;
  }

  /// Display text for an analysis result, including step information.
  static String getAnalysisDisplayText(MoveAnalysisResult result) {
    return "${result.move}: ${result.outcome.displayString}";
  }

  /// Whether [result] carries perfect-database step information.
  static bool hasPerfectDatabaseInfo(MoveAnalysisResult result) {
    return result.outcome.stepCount != null && result.outcome.stepCount! > 0;
  }
}
