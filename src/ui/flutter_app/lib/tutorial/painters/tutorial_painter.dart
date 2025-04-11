// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// tutorial_painter.dart

import 'package:flutter/material.dart';

import '../../../game_page/services/mill.dart';
import '../../game_page/services/painters/painters.dart';
import '../../game_page/services/painters/piece.dart';
import '../../shared/database/database.dart';

/// Preview Piece Painter
class TutorialPainter extends CustomPainter {
  TutorialPainter({this.blurIndex, this.focusIndex, required this.pieceList});

  final int? focusIndex;
  final int? blurIndex;
  final List<PieceColor> pieceList;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<Piece> piecesToDraw = <Piece>[];

    final double pieceWidth = size.width * DB().displaySettings.pieceWidth / 7;

    // Draw pieces on board
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;
        final PieceColor piece = pieceList[index]; // No Pieces when initial
        if (piece == PieceColor.none) {
          continue;
        }

        final Offset pos = pointFromIndex(index, size);

        piecesToDraw.add(
          Piece(
            pieceColor: piece,
            pos: pos,
            diameter: pieceWidth,
            index: index,
          ),
        );

        shadowPath.addOval(
          Rect.fromCircle(
            center: pos,
            radius: pieceWidth / 2,
          ),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);
    paint.style = PaintingStyle.fill;

    late Color blurPositionColor;
    for (final Piece piece in piecesToDraw) {
      assert(
        piece.pieceColor == PieceColor.black ||
            piece.pieceColor == PieceColor.white ||
            piece.pieceColor == PieceColor.marked,
      );
      blurPositionColor = piece.pieceColor.blurPositionColor;

      final double pieceRadius = pieceWidth / 2;
      final double pieceInnerRadius = pieceRadius * 0.99;

      // Draw Border of Piece
      paint.color = piece.pieceColor.borderColor;
      canvas.drawCircle(
        piece.pos,
        pieceRadius,
        paint,
      );
      // Draw the piece
      paint.color = piece.pieceColor.mainColor;
      canvas.drawCircle(
        piece.pos,
        pieceInnerRadius,
        paint,
      );
    }

    // Draw focus and blur position
    if (focusIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        pointFromIndex(focusIndex!, size),
        pieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        pointFromIndex(blurIndex!, size),
        pieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(TutorialPainter oldDelegate) => true;
}
