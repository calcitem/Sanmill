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

import 'package:flutter/material.dart';

import '../../../game_page/services/mill.dart';
import '../../game_page/widgets/painters/painters.dart';
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
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

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
        final bool animated = focusIndex == index;

        piecesToDraw.add(
          PiecePaintParam(
            piece: piece,
            pos: pos,
            animated: animated,
            diameter: pieceWidth,
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
    for (final PiecePaintParam piece in piecesToDraw) {
      assert(
        piece.piece == PieceColor.black ||
            piece.piece == PieceColor.white ||
            piece.piece == PieceColor.ban,
      );
      blurPositionColor = piece.piece.blurPositionColor;

      final double pieceRadius = pieceWidth / 2;
      final double pieceInnerRadius = pieceRadius * 0.99;

      // Draw Border of Piece
      paint.color = piece.piece.borderColor;
      canvas.drawCircle(
        piece.pos,
        pieceRadius,
        paint,
      );
      // Draw the piece
      paint.color = piece.piece.pieceColor;
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
