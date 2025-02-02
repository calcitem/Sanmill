// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// mini_board.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/mill.dart';

/// MiniBoard widget displays a small Nine Men's Morris board given a board layout string.
/// The layout string is expected to have the format "outer/middle/inner", each with 8 chars.
/// For example: "O*@*O@*O/@@**O*@/O@O*@*O"
/// 'O' = white piece, '@' = black piece, otherwise empty.
class MiniBoard extends StatelessWidget {
  const MiniBoard({
    super.key,
    required this.boardLayout,
  });

  final String boardLayout;

  @override
  Widget build(BuildContext context) {
    // Constrain to a square aspect ratio so the board doesn't overflow.
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        color: DB().colorSettings.boardBackgroundColor,
        child: CustomPaint(
          painter: MiniBoardPainter(boardLayout: boardLayout),
        ),
      ),
    );
  }
}

/// MiniBoardPainter draws a miniature Nine Men's Morris board with equally spaced rings.
/// The layout string should have the format "outer/middle/inner", each with 8 characters.
class MiniBoardPainter extends CustomPainter {
  MiniBoardPainter({required this.boardLayout}) {
    boardState = _parseBoardLayout(boardLayout);
  }

  final String boardLayout;
  late final List<PieceColor> boardState;

  /// Parse the board layout string into 24 PieceColors.
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
    // but add them in the order: inner => middle => outer
    // so indices match the painting logic (0..7 = inner, 8..15 = middle, 16..23 = outer).
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[0][i])); // inner
    }
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[1][i])); // middle
    }
    for (int i = 0; i < 8; i++) {
      state.add(_charToPieceColor(parts[2][i])); // outer
    }
    return state;
  }

  /// Convert character to piece color:
  /// 'O' => white, '@' => black, otherwise => none.
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

    // Calculate the squares:
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

      // Determine ring positions for each piece:
      Offset pos;
      if (i < 8) {
        pos = innerPoints[(i + 1) % 8];
      } else if (i < 16) {
        pos = middlePoints[((i - 8) + 1) % 8];
      } else {
        pos = outerPoints[((i - 16) + 1) % 8];
      }

      final Paint piecePaint = Paint()
        ..color = (pc == PieceColor.white)
            ? DB().colorSettings.whitePieceColor
            : DB().colorSettings.blackPieceColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pos, pieceRadius, piecePaint);
    }
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
    return oldDelegate.boardLayout != boardLayout;
  }
}
