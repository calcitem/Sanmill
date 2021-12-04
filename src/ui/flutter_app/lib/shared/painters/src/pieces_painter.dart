/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of '../painters.dart';

class _PiecePaintParam {
  final PieceColor piece;
  final Offset pos;
  final bool animated;

  const _PiecePaintParam({
    required this.piece,
    required this.pos,
    required this.animated,
  });
}

class PiecesPainter extends PiecesBasePainter {
  final Position position;
  final int? focusIndex;
  final int? blurIndex;
  final double animationValue;

  late final int pointStyle;
  late final double pointWidth;
  late final double pieceWidth;
  late final double animatedPieceWidth;

  PiecesPainter({
    required double width,
    required this.position,
    this.focusIndex,
    this.blurIndex,
    required this.animationValue,
  }) : super(width: width) {
    pointStyle = LocalDatabaseService.display.pointStyle;
    pointWidth = LocalDatabaseService.display.pointWidth;
    pieceWidth = _squareWidth * LocalDatabaseService.display.pieceWidth;
    animatedPieceWidth =
        _squareWidth * LocalDatabaseService.display.pieceWidth * animationValue;
  }

  @override
  void paint(Canvas canvas, Size size) => _doPaint(canvas, thePaint);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;

  void _doPaint(Canvas canvas, Paint paint) {
    final shadowPath = Path();
    final piecesToDraw = <_PiecePaintParam>[];

    // Draw pieces on board
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;
        final piece = position.pieceOnGrid(index); // No Pieces when initial

        if (piece == PieceColor.none) continue;

        final pos = _offset.translate(_squareWidth * col, _squareWidth * row);
        final animated = focusIndex == index;

        piecesToDraw
            .add(_PiecePaintParam(piece: piece, pos: pos, animated: animated));

        shadowPath.addOval(
          Rect.fromCenter(center: pos, width: pieceWidth, height: pieceWidth),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);
    paint.style = PaintingStyle.fill;

    late Color blurPositionColor;
    for (final pps in piecesToDraw) {
      final pieceRadius = pieceWidth / 2;
      final pieceInnerRadius = pieceRadius * 0.99;

      final animatedPieceRadius = animatedPieceWidth / 2;
      final animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // TODO: [Leptopoda] move the following attributes into [_PiecePaintParam]
      // Draw Border of Piece
      late final Color border;
      late final Color piece;
      switch (pps.piece) {
        case PieceColor.white:
          border = AppTheme.whitePieceBorderColor;
          piece = LocalDatabaseService.colorSettings.whitePieceColor;
          blurPositionColor = LocalDatabaseService.colorSettings.whitePieceColor
              .withOpacity(0.1);
          break;
        case PieceColor.black:
          border = AppTheme.blackPieceBorderColor;
          piece = LocalDatabaseService.colorSettings.blackPieceColor;

          blurPositionColor = LocalDatabaseService.colorSettings.blackPieceColor
              .withOpacity(0.1);
          break;
        default:
      }

      paint.color = border;
      canvas.drawCircle(
        pps.pos,
        pps.animated ? animatedPieceRadius : pieceRadius,
        paint,
      );
      paint.color = piece;
      canvas.drawCircle(
        pps.pos,
        pps.animated ? animatedPieceInnerRadius : pieceInnerRadius,
        paint,
      );
    }

    // draw focus and blur position
    if (focusIndex != null) {
      final row = focusIndex! ~/ 7;
      final column = focusIndex! % 7;

      paint.color = LocalDatabaseService.colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        _offset.translate(column * _squareWidth, row * _squareWidth),
        animatedPieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null) {
      final row = blurIndex! ~/ 7;
      final column = blurIndex! % 7;

      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        _offset.translate(column * _squareWidth, row * _squareWidth),
        animatedPieceWidth / 2 * 0.8,
        paint,
      );
    }
  }
}
