// mini_board.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/mill.dart';

/// MiniBoard widget displays a small Nine Men's Morris board given a board layout string.
/// Now it also accepts an optional [extMove] to highlight the last move.
class MiniBoard extends StatelessWidget {
  const MiniBoard({
    super.key,
    required this.boardLayout,
    this.extMove, // Optional: used to highlight the last move
  });

  final String boardLayout;
  final ExtMove? extMove;

  @override
  Widget build(BuildContext context) {
    // Constrain to a square aspect ratio so the board doesn't overflow.
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        color: DB().colorSettings.boardBackgroundColor,
        child: CustomPaint(
          painter: MiniBoardPainter(
            boardLayout: boardLayout,
            extMove: extMove,
          ),
        ),
      ),
    );
  }
}

/// MiniBoardPainter draws a miniature Nine Men's Morris board with equally spaced rings.
/// Additionally, if [extMove] is provided, it draws a highlight showing the last move:
/// - Red circle on the piece if placing
/// - Red arrow from origin to destination if moving
/// - Red X on removed piece if removing
class MiniBoardPainter extends CustomPainter {
  MiniBoardPainter({
    required this.boardLayout,
    this.extMove,
  }) {
    boardState = _parseBoardLayout(boardLayout);
  }

  final String boardLayout;

  /// The optional last move to highlight.
  final ExtMove? extMove;

  /// Holds the parsed board layout (24 squares).
  late final List<PieceColor> boardState;

  /// Parse the board layout string into 24 PieceColors.
  /// Format: "outer/middle/inner", each 8 chars.
  static List<PieceColor> _parseBoardLayout(String layout) {
    final List<String> parts = layout.split('/');
    if (parts.length != 3 ||
        parts[0].length != 8 ||
        parts[1].length != 8 ||
        parts[2].length != 8) {
      // Invalid format => empty board.
      return List<PieceColor>.filled(24, PieceColor.none);
    }

    final List<PieceColor> state = <PieceColor>[];
    // We parse "outer/middle/inner" from left to right,
    // but store them in the order: inner => middle => outer
    // so indices 0..7 = inner, 8..15 = middle, 16..23 = outer.
    //
    // parts[0] => outer ring
    // parts[1] => middle ring
    // parts[2] => inner ring
    //
    // BUT the code below does it in reversed fashion to keep painting consistent.
    // If this mismatch is intentional, keep it. Otherwise reorder accordingly.

    // Inner ring from parts[0]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[0][i]));
    }
    // Middle ring from parts[1]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[1][i]));
    }
    // Outer ring from parts[2]
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[2][i]));
    }
    return state;
  }

  /// Convert character to piece color: 'O' => white, '@' => black, 'X' => "marked", else => none.
  static PieceColor _charToPieceColor(String ch) {
    switch (ch) {
      case 'O':
        return PieceColor.white;
      case '@':
        return PieceColor.black;
      case 'X':
        return PieceColor.marked;
      default:
        return PieceColor.none;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double minSide = math.min(w, h);

    // Center the board if w != h.
    final double offsetX = (w - minSide) / 2;
    final double offsetY = (h - minSide) / 2;

    // Adjusted parameters for balanced spacing:
    const double outerMarginFactor = 0.06;
    const double ringSpacingFactor = 0.13;

    // Piece radius factor:
    const double pieceRadiusFactor = 0.05;

    final double outerMargin = minSide * outerMarginFactor;
    final double ringSpacing = minSide * ringSpacingFactor;
    final double pieceRadius = minSide * pieceRadiusFactor;

    // Calculate margins for each ring:
    final double marginMiddle = outerMargin + ringSpacing;
    final double marginInner = outerMargin + ringSpacing * 2;

    // Board lines paint
    final Paint boardPaint = Paint()
      ..color = DB().colorSettings.boardLineColor
      ..style = PaintingStyle.stroke
      // Slightly scale the stroke width based on size
      ..strokeWidth = math.max(1.0, minSide * 0.003);

    // Calculate the squares offsets for each ring:
    final List<Offset> outerPoints = _ringPoints(
      offsetX,
      offsetY,
      outerMargin,
      minSide - 2 * outerMargin,
    );
    final List<Offset> middlePoints = _ringPoints(
      offsetX,
      offsetY,
      marginMiddle,
      minSide - 2 * marginMiddle,
    );
    final List<Offset> innerPoints = _ringPoints(
      offsetX,
      offsetY,
      marginInner,
      minSide - 2 * marginInner,
    );

    // Draw the three rings:
    _drawSquare(canvas, outerPoints, boardPaint);
    _drawSquare(canvas, middlePoints, boardPaint);
    _drawSquare(canvas, innerPoints, boardPaint);

    // Connect midpoints of each ring:
    _drawLine(canvas, outerPoints[1], middlePoints[1], boardPaint);
    _drawLine(canvas, middlePoints[1], innerPoints[1], boardPaint);

    _drawLine(canvas, outerPoints[3], middlePoints[3], boardPaint);
    _drawLine(canvas, middlePoints[3], innerPoints[3], boardPaint);

    _drawLine(canvas, outerPoints[5], middlePoints[5], boardPaint);
    _drawLine(canvas, middlePoints[5], innerPoints[5], boardPaint);

    _drawLine(canvas, outerPoints[7], middlePoints[7], boardPaint);
    _drawLine(canvas, middlePoints[7], innerPoints[7], boardPaint);

    // Draw pieces:
    for (int i = 0; i < 24; i++) {
      final PieceColor pc = boardState[i];
      if (pc == PieceColor.none) {
        continue;
      }

      // Determine ring position for each piece:
      Offset pos;
      if (i < 8) {
        // inner ring
        pos = innerPoints[(i + 1) % 8];
      } else if (i < 16) {
        // middle ring
        pos = middlePoints[((i - 8) + 1) % 8];
      } else {
        // outer ring
        pos = outerPoints[((i - 16) + 1) % 8];
      }

      final Paint piecePaint = Paint()
        ..color = (pc == PieceColor.white)
            ? DB().colorSettings.whitePieceColor
            : DB().colorSettings.blackPieceColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pos, pieceRadius, piecePaint);
    }

    // Finally, draw highlights for the last move (red circle/arrow/X):
    _drawMoveHighlight(
      canvas,
      innerPoints,
      middlePoints,
      outerPoints,
      pieceRadius,
    );
  }

  /// Draws highlights according to the last move (if any).
  /// - Placing => red circle around the destination
  /// - Moving => red arrow from origin to destination
  /// - Removing => red X at the removed location
  void _drawMoveHighlight(
    Canvas canvas,
    List<Offset> innerPoints,
    List<Offset> middlePoints,
    List<Offset> outerPoints,
    double pieceRadius,
  ) {
    if (extMove == null) return;

    final MoveType type = extMove!.type;
    if (type == MoveType.none || type == MoveType.draw) {
      return;
    }

    // Convert 'from' and 'to' squares to their ring offsets
    final Offset? fromPos = _convertSquareToOffset(
      extMove!.from,
      innerPoints,
      middlePoints,
      outerPoints,
    );
    final Offset? toPos = _convertSquareToOffset(
      extMove!.to,
      innerPoints,
      middlePoints,
      outerPoints,
    );

    final Paint highlightPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    switch (type) {
      case MoveType.place:
        // Draw red circle on 'to' location
        if (toPos != null) {
          canvas.drawCircle(toPos, pieceRadius * 1.4, highlightPaint);
        }
        break;

      case MoveType.move:
        // Red arrow from fromPos => toPos
        if (fromPos != null && toPos != null) {
          canvas.drawLine(fromPos, toPos, highlightPaint);
          _drawArrowHead(canvas, fromPos, toPos, highlightPaint);
        }
        break;

      case MoveType.remove:
        // Red X at 'toPos'
        if (toPos != null) {
          _drawRedX(canvas, toPos, pieceRadius * 2.0, highlightPaint);
        }
        break;

      case MoveType.none:
      case MoveType.draw:
        break;
    }
  }

  /// Convert a Nine Men's Morris square [sq] (8..31) to the appropriate
  /// Offset in [innerPoints], [middlePoints], or [outerPoints].
  ///
  /// - Inner ring:   squares 8..15
  /// - Middle ring:  squares 16..23
  /// - Outer ring:   squares 24..31
  ///
  /// We add 1 to the index (and mod 8) to match your existing painting logic
  ///   of `pos = ringPoints[(i + 1) % 8]`.
  Offset? _convertSquareToOffset(
    int sq,
    List<Offset> innerPoints,
    List<Offset> middlePoints,
    List<Offset> outerPoints,
  ) {
    // If sq < 8, it's usually a special sentinel (-1, 0, etc.) => no highlight
    if (sq < 8 || sq > 31) {
      return null;
    }

    // Decide which ring based on the numeric range.
    if (sq < 16) {
      // 8..15 => inner ring
      final int index = (sq - 8 + 1) % 8; // ex: sq=8 => index=(0+1)%8=1
      return innerPoints[index];
    } else if (sq < 24) {
      // 16..23 => middle ring
      final int index = (sq - 16 + 1) % 8;
      return middlePoints[index];
    } else {
      // 24..31 => outer ring
      final int index = (sq - 24 + 1) % 8;
      return outerPoints[index];
    }
  }

  /// Draw a small arrowhead at the "end" of the move line.
  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    const double arrowSize = 10.0;
    final double angle = math.atan2(to.dy - from.dy, to.dx - from.dx);

    // The arrowhead will be two small lines angled from the endpoint.
    final Offset arrowP1 = Offset(
      to.dx - arrowSize * math.cos(angle - math.pi / 6),
      to.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    final Offset arrowP2 = Offset(
      to.dx - arrowSize * math.cos(angle + math.pi / 6),
      to.dy - arrowSize * math.sin(angle + math.pi / 6),
    );

    final Path path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(arrowP1.dx, arrowP1.dy)
      ..moveTo(to.dx, to.dy)
      ..lineTo(arrowP2.dx, arrowP2.dy);

    canvas.drawPath(path, paint);
  }

  /// Draw a red X at the given position, with size given by [xSize].
  /// We create two diagonal lines crossing at [center].
  void _drawRedX(Canvas canvas, Offset center, double xSize, Paint paint) {
    final double half = xSize / 2;
    final Offset topLeft = Offset(center.dx - half, center.dy - half);
    final Offset topRight = Offset(center.dx + half, center.dy - half);
    final Offset bottomLeft = Offset(center.dx - half, center.dy + half);
    final Offset bottomRight = Offset(center.dx + half, center.dy + half);

    final Path path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..moveTo(topRight.dx, topRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy);

    canvas.drawPath(path, paint);
  }

  /// Create 8 points around a square ring:
  /// 0: top-left
  /// 1: top-center
  /// 2: top-right
  /// 3: right-center
  /// 4: bottom-right
  /// 5: bottom-center
  /// 6: bottom-left
  /// 7: left-center
  List<Offset> _ringPoints(
    double baseX,
    double baseY,
    double offset,
    double ringSide,
  ) {
    final double left = baseX + offset;
    final double top = baseY + offset;
    final double right = left + ringSide;
    final double bottom = top + ringSide;
    final double centerX = left + ringSide / 2;
    final double centerY = top + ringSide / 2;

    return <Offset>[
      Offset(left, top), // 0: top-left
      Offset(centerX, top), // 1: top-center
      Offset(right, top), // 2: top-right
      Offset(right, centerY), // 3: right-center
      Offset(right, bottom), // 4: bottom-right
      Offset(centerX, bottom), // 5: bottom-center
      Offset(left, bottom), // 6: bottom-left
      Offset(left, centerY), // 7: left-center
    ];
  }

  /// Draw a closed polygon from a list of points.
  void _drawSquare(Canvas canvas, List<Offset> points, Paint paint) {
    final Path path = Path()..addPolygon(points, true);
    canvas.drawPath(path, paint);
  }

  /// Draw a single line between two points.
  void _drawLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    canvas.drawLine(p1, p2, paint);
  }

  @override
  bool shouldRepaint(covariant MiniBoardPainter oldDelegate) {
    // Repaint if the boardLayout or last move changes
    return oldDelegate.boardLayout != boardLayout ||
        oldDelegate.extMove?.move != extMove?.move;
  }
}
