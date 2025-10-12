// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_painter.dart

part of '../../../game_page/services/painters/painters.dart';

/// Custom Board Painter
///
/// Painter to draw the Board. The pieces are drawn by [PiecePainter].
/// It asserts the Canvas to be a square.
class BoardPainter extends CustomPainter {
  BoardPainter(this.context, this.backgroundImage);

  final BuildContext context;
  final ui.Image? backgroundImage;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    final Position position = GameController().position;
    final ColorSettings colorSettings = DB().colorSettings;
    final double boardBorderLineWidth =
        DB().displaySettings.boardBorderLineWidth;
    final Paint paint = _createPaint(colorSettings, boardBorderLineWidth, size);

    _drawBackground(canvas, size, colorSettings);
    _drawOptionalElements(canvas, size, position);

    final List<Offset> offset = points
        .map((Offset e) => offsetFromPointWithInnerSize(e, size))
        .toList();
    _drawLines(offset, canvas, paint, size);
    _drawPoints(offset, canvas, paint);
    _drawMillLines(offset, canvas, paint, size);

    // Add analysis renderer to draw analysis results
    if (AnalysisMode.isEnabled) {
      AnalysisRenderer.render(
        canvas,
        size,
        size.width / 7,
      ); // Divide by number of points per row
    }
  }

  Paint _createPaint(
    ColorSettings colorSettings,
    double boardBorderLineWidth,
    Size size,
  ) {
    final Paint paint = Paint();
    paint.strokeWidth =
        boardBorderLineWidth * (isTablet(context) ? size.width ~/ 256 : 1);
    paint.color = colorSettings.boardLineColor;
    paint.style = PaintingStyle.stroke;
    return paint;
  }

  void _drawOptionalElements(Canvas canvas, Size size, Position position) {
    if (_shouldDrawPieceCount(position)) {
      _drawPieceCount(position, canvas, size);
    }

    if (_shouldDrawNotations()) {
      _drawNotations(canvas, size);
    }
  }

  bool _shouldDrawPieceCount(Position position) {
    return DB().displaySettings.isPieceCountInHandShown &&
        GameController().gameInstance.gameMode != GameMode.setupPosition &&
        position.phase == Phase.placing;
  }

  bool _shouldDrawNotations() {
    return DB().displaySettings.isNotationsShown || EnvironmentConfig.devMode;
  }

  void _drawBackground(Canvas canvas, Size size, ColorSettings colorSettings) {
    final Paint paint = Paint();
    final double cornerRadius = DB().displaySettings.boardCornerRadius;
    final bool shadowEnabled = DB().displaySettings.boardShadowEnabled;
    final Rect boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final RRect boardRRect =
        RRect.fromRectAndRadius(boardRect, Radius.circular(cornerRadius));

    // If enabled, draw a drop shadow beneath the board to give it a 3D effect.
    if (shadowEnabled) {
      _drawBoardShadow(canvas, size, cornerRadius);
    }

    // Draw the main board surface (color or image) on top of the shadow.
    if (backgroundImage != null) {
      canvas.clipRRect(boardRRect);
      canvas.drawImageRect(
        backgroundImage!,
        Rect.fromLTWH(
          0,
          0,
          backgroundImage!.width.toDouble(),
          backgroundImage!.height.toDouble(),
        ),
        boardRect,
        paint,
      );
    } else {
      _drawTexturedBoard(canvas, boardRRect, colorSettings.boardBackgroundColor);
    }
  }

  /// Draw a single, softer, blurred drop shadow to create depth below the board.
  /// The shadow is offset to the right and bottom to simulate a light source
  /// from the top-left.
  void _drawBoardShadow(Canvas canvas, Size size, double cornerRadius) {
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

    final RRect shadowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 5, size.width, size.height),
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(shadowRect, shadowPaint);
  }

  void _drawTexturedBoard(
    Canvas canvas,
    RRect boardRRect,
    Color baseColor,
  ) {
    final Rect rect = boardRRect.outerRect;

    final Paint gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        <Color>[
          _adjustColorBrightness(baseColor, 0.12),
          baseColor,
          _adjustColorBrightness(baseColor, -0.2),
        ],
        <double>[0.0, 0.55, 1.0],
      );

    canvas.drawRRect(boardRRect, gradientPaint);

    _drawCenterGlow(canvas, boardRRect);
    _drawWoodGrain(canvas, boardRRect);
    _drawEdgeHighlights(canvas, boardRRect);
  }

  void _drawCenterGlow(Canvas canvas, RRect boardRRect) {
    final Rect rect = boardRRect.outerRect;
    final Paint glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        rect.shortestSide * 0.55,
        <Color>[
          Colors.white.withOpacity(0.12),
          Colors.transparent,
        ],
      );

    canvas.save();
    canvas.clipRRect(boardRRect);
    canvas.drawRect(rect, glowPaint);
    canvas.restore();
  }

  void _drawWoodGrain(Canvas canvas, RRect boardRRect) {
    final Rect rect = boardRRect.outerRect;
    final double horizontalStep = rect.height / 24;
    final double amplitude = rect.width * 0.02;

    final Paint grainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, rect.height * 0.0015);

    canvas.save();
    canvas.clipRRect(boardRRect);
    for (double y = rect.top + horizontalStep;
        y < rect.bottom;
        y += horizontalStep) {
      final double progress = (y - rect.top) / rect.height;
      final double oscillation = sin(progress * pi);
      grainPaint.color = Colors.black.withOpacity(0.01 + 0.02 * oscillation.abs());

      final double offset = amplitude * sin(progress * pi * 2);
      canvas.drawLine(
        Offset(rect.left, y + offset),
        Offset(rect.right, y - offset),
        grainPaint,
      );
    }
    canvas.restore();

    final double verticalStep = rect.width / 12;
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = max(1.0, rect.width * 0.001);

    canvas.save();
    canvas.clipRRect(boardRRect);
    for (double x = rect.left + verticalStep;
        x < rect.right;
        x += verticalStep) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        highlightPaint,
      );
    }
    canvas.restore();
  }

  void _drawEdgeHighlights(Canvas canvas, RRect boardRRect) {
    final Rect rect = boardRRect.outerRect;
    final double outerStroke = max(2.0, rect.shortestSide * 0.015);

    final Paint rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerStroke
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        <Color>[
          Colors.white.withOpacity(0.35),
          Colors.transparent,
          Colors.black.withOpacity(0.35),
        ],
      );

    canvas.drawRRect(boardRRect.deflate(outerStroke / 2), rimPaint);

    final Paint innerStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, rect.shortestSide * 0.006)
      ..color = Colors.black.withOpacity(0.18);

    canvas.drawRRect(boardRRect.deflate(outerStroke * 1.1), innerStrokePaint);
  }

  Color _adjustColorBrightness(Color color, double amount) {
    final HSLColor hsl = HSLColor.fromColor(color);
    final double lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  void _drawLines(List<Offset> offset, Canvas canvas, Paint paint, Size size) {
    _drawOuterRectangle(canvas, offset, paint);

    final double boardInnerLineWidth = DB().displaySettings.boardInnerLineWidth;
    paint.strokeWidth =
        boardInnerLineWidth * (isTablet(context) ? size.width ~/ 256 : 1);

    final Path path = _createLinePath(offset);
    canvas.drawPath(path, paint);
  }

  void _drawOuterRectangle(Canvas canvas, List<Offset> offset, Paint paint) {
    canvas.drawRect(Rect.fromPoints(offset[0], offset[23]), paint);
  }

  static Path _createLinePath(List<Offset> offset) {
    final Path path = Path();
    path.addRect(Rect.fromPoints(offset[3], offset[20])); // File B
    path.addRect(Rect.fromPoints(offset[6], offset[17])); // File A
    _addMiddleHorizontalLines(path, offset);
    _addDiagonalLinesIfNeeded(path, offset);
    return path;
  }

  static void _addMiddleHorizontalLines(Path path, List<Offset> offset) {
    path.addLine(offset[1], offset[7]);
    path.addLine(offset[16], offset[22]);
    path.addLine(offset[9], offset[11]);
    path.addLine(offset[12], offset[14]);
  }

  static void _addDiagonalLinesIfNeeded(Path path, List<Offset> offset) {
    if (DB().ruleSettings.hasDiagonalLines) {
      path.addLine(offset[0], offset[6]);
      path.addLine(offset[17], offset[23]);
      path.addLine(offset[21], offset[15]);
      path.addLine(offset[8], offset[2]);
    }
  }

  void _drawMillLines(
    List<Offset> offset,
    Canvas canvas,
    Paint paint,
    Size size,
  ) {
    final double boardInnerLineWidth = DB().displaySettings.boardInnerLineWidth;
    paint.strokeWidth =
        boardInnerLineWidth * (isTablet(context) ? size.width ~/ 256 : 1) + 1;

    if (!DB().ruleSettings.oneTimeUseMill) {
      return;
    }

    final Map<PieceColor, List<List<int>>> formedMills =
        GameController().position.formedMills;

    final Color mixedColor = Color.lerp(
      DB().colorSettings.whitePieceColor,
      DB().colorSettings.blackPieceColor,
      0.5,
    )!;

    // Draw Mills with unique or mixed colors
    void drawMills(
      PieceColor color,
      List<List<int>> mills,
      Color defaultColor,
    ) {
      for (final List<int> mill in mills) {
        final Path path = Path();
        path.addLine(
          pointFromSquare(mill[0], size),
          pointFromSquare(mill[1], size),
        );
        path.addLine(
          pointFromSquare(mill[1], size),
          pointFromSquare(mill[2], size),
        );
        path.addLine(
          pointFromSquare(mill[2], size),
          pointFromSquare(mill[0], size),
        );

        // Check if this mill exists in the opposite color mills
        final bool isShared =
            formedMills[color == PieceColor.white
                    ? PieceColor.black
                    : PieceColor.white]!
                .any((List<int> otherMill) => listEquals(mill, otherMill));

        paint.color = isShared ? mixedColor : defaultColor;

        if (paint.color == DB().colorSettings.boardBackgroundColor ||
            paint.color == DB().colorSettings.boardLineColor) {
          if (defaultColor == DB().colorSettings.whitePieceColor) {
            paint.color = Colors.red;
          } else {
            paint.color = Colors.blue;
          }
        }

        canvas.drawPath(path, paint);
      }
    }

    // Draw White and Black Mills, possibly with mixed color
    drawMills(
      PieceColor.white,
      formedMills[PieceColor.white]!,
      DB().colorSettings.whitePieceColor,
    );
    drawMills(
      PieceColor.black,
      formedMills[PieceColor.black]!,
      DB().colorSettings.blackPieceColor,
    );
  }

  static void _drawPoints(List<Offset> points, Canvas canvas, Paint paint) {
    final PaintingStyle? style = getPointPaintingStyle();

    if (style == null) {
      return;
    }

    final double pointRadius = DB().displaySettings.pointWidth;

    if (style == PaintingStyle.stroke) {
      // For stroke style, first clear the background inside each circle to make it truly hollow
      final Paint clearPaint = Paint()
        ..color = DB().colorSettings.boardBackgroundColor
        ..style = PaintingStyle.fill;

      for (final Offset point in points) {
        // Clear the area inside the circle
        canvas.drawCircle(point, pointRadius, clearPaint);
      }

      // Then draw the stroke outline
      paint.style = PaintingStyle.stroke;
      for (final Offset point in points) {
        canvas.drawCircle(point, pointRadius, paint);
      }
    } else {
      // For fill style, draw normally
      paint.style = style;
      for (final Offset point in points) {
        canvas.drawCircle(point, pointRadius, paint);
      }
    }
  }

  static PaintingStyle? getPointPaintingStyle() {
    switch (DB().displaySettings.pointPaintingStyle) {
      case PointPaintingStyle.fill:
        return PaintingStyle.fill;
      case PointPaintingStyle.stroke:
        return PaintingStyle.stroke;
      case PointPaintingStyle.none:
        return null;
    }
  }

  static void _drawPieceCount(Position position, Canvas canvas, Size size) {
    final int pieceInHandCount = _calculatePieceInHandCount(position);

    final TextSpan textSpan = TextSpan(
      style: TextStyle(
        fontSize: 48,
        color: DB().colorSettings.boardLineColor.withValues(alpha: 1.0),
      ),
      text: pieceInHandCount.toString(),
    );

    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      size.center(-Offset(textPainter.width, textPainter.height) / 2),
    );
  }

  static int _calculatePieceInHandCount(Position position) {
    if (position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      return DB().ruleSettings.piecesCount;
    } else {
      return position.pieceInHandCount[position.sideToMove]!;
    }
  }

  static void _drawNotations(Canvas canvas, Size size) {
    for (int i = 0; i < verticalNotations.length; i++) {
      _drawVerticalNotation(canvas, size, i);
      _drawHorizontalNotation(canvas, size, i);
    }
  }

  static void _drawVerticalNotation(Canvas canvas, Size size, int index) {
    final TextStyle notationTextStyle = TextStyle(
      color: DB().colorSettings.boardLineColor.withValues(alpha: 1.0),
      fontSize: AppTheme.textScaler.scale(20),
    );

    final TextSpan notationSpan = TextSpan(
      style: notationTextStyle,
      text: verticalNotations[index],
    );

    final TextPainter notationPainter = TextPainter(
      text: notationSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    notationPainter.layout();
    final double offset = (boardMargin - notationPainter.width) / 2;
    notationPainter.paint(
      canvas,
      Offset(offset, offsetFromInt(index, size) - notationPainter.height / 2),
    );
  }

  static void _drawHorizontalNotation(Canvas canvas, Size size, int index) {
    final TextStyle notationTextStyle = TextStyle(
      color: DB().colorSettings.boardLineColor.withValues(alpha: 1.0),
      fontSize: AppTheme.textScaler.scale(20),
    );

    final TextSpan notationSpan = TextSpan(
      style: notationTextStyle,
      text: DB().generalSettings.screenReaderSupport
          ? horizontalNotations[index].toUpperCase()
          : horizontalNotations[index],
    );

    final TextPainter notationPainter = TextPainter(
      text: notationSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    notationPainter.layout();
    final double offset =
        size.height - (boardMargin + notationPainter.height) / 2;
    notationPainter.paint(
      canvas,
      Offset(offsetFromInt(index, size) - notationPainter.width / 2, offset),
    );
  }

  static void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    List<Color> colors,
    double strokeWidth,
    double dashLength,
    double spaceLength,
  ) {
    final Paint paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      colors,
      paint,
      dashLength,
      spaceLength,
    );
    _drawDashedLine(
      canvas,
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.bottom),
      colors,
      paint,
      dashLength,
      spaceLength,
    );
    _drawDashedLine(
      canvas,
      Offset(rect.right, rect.bottom),
      Offset(rect.left, rect.bottom),
      colors,
      paint,
      dashLength,
      spaceLength,
    );
    _drawDashedLine(
      canvas,
      Offset(rect.left, rect.bottom),
      Offset(rect.left, rect.top),
      colors,
      paint,
      dashLength,
      spaceLength,
    );
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    List<Color> colors,
    double strokeWidth,
    double dashLength,
    double spaceLength,
  ) {
    final Paint paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final PathMetrics pathMetrics = path.computeMetrics();
    int colorIndex = 0;

    for (final PathMetric metric in pathMetrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        paint.color = colors[colorIndex];
        colorIndex = (colorIndex + 1) % colors.length;
        final double nextDistance = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, nextDistance), paint);
        distance = nextDistance + spaceLength;
      }
    }
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    List<Color> colors,
    Paint paint,
    double dashLength,
    double spaceLength,
  ) {
    final double totalLength = (end - start).distance;
    final double dx = (end.dx - start.dx) / totalLength;
    final double dy = (end.dy - start.dy) / totalLength;

    double distance = 0.0;
    int colorIndex = 0;

    while (distance < totalLength) {
      paint.color = colors[colorIndex];
      colorIndex = (colorIndex + 1) % colors.length;

      final Offset from = Offset(
        start.dx + dx * distance,
        start.dy + dy * distance,
      );
      distance += dashLength;

      if (distance > totalLength) {
        distance = totalLength;
      }
      final Offset to = Offset(
        start.dx + dx * distance,
        start.dy + dy * distance,
      );

      canvas.drawLine(from, to, paint);
      distance += spaceLength;
    }
  }

  static void drawReferenceLines(Canvas canvas, Size size) {
    final List<Color> colors = <Color>[
      Colors.black,
      Colors.white,
      Colors.yellow,
      Colors.blue,
      Colors.red,
    ];

    const double strokeWidth = 2.0;
    const double dashLength = 10.0;
    const double spaceLength = 5.0;

    final List<Offset> offset = points
        .map((Offset e) => offsetFromPointWithInnerSize(e, size))
        .toList();

    _drawDashedRect(
      canvas,
      Rect.fromPoints(offset[0], offset[23]),
      colors,
      strokeWidth,
      dashLength,
      spaceLength,
    );

    final Path path = _createLinePath(offset);

    _drawDashedPath(canvas, path, colors, strokeWidth, dashLength, spaceLength);

    final PaintingStyle? style = getPointPaintingStyle();
    if (style != null) {
      final Paint pointPaint = Paint()..style = style;
      final double pointRadius = DB().displaySettings.pointWidth;
      for (final Offset point in offset) {
        canvas.drawCircle(point, pointRadius, pointPaint);
      }
    }
  }

  static void drawDashedCircle(Canvas canvas, Offset center, double radius) {
    final List<Color> colors = <Color>[
      Colors.black,
      Colors.white,
      Colors.yellow,
      Colors.blue,
      Colors.red,
    ];

    const double strokeWidth = 2.0;
    const double dashLength = 10.0;
    const double spaceLength = 5.0;
    final Paint paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double distance = 0.0;
    final double circumference = 2 * pi * radius;
    int colorIndex = 0;

    while (distance < circumference) {
      paint.color = colors[colorIndex];
      colorIndex = (colorIndex + 1) % colors.length;

      // Calculate the start and end points of each dashed segment on the circle
      final double startAngle = distance / radius;
      final double endAngle = ((distance + dashLength) / radius).clamp(
        0,
        2 * pi,
      );

      final Path path = Path();
      path.arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
        false,
      );
      canvas.drawPath(path, paint);

      distance += dashLength + spaceLength;
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    // Always repaint to reflect dynamic appearance settings such as shadow toggle,
    // inner-ring scaling, line widths, etc. Board is lightweight enough for this.
    return true;
  }
}
