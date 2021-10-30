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

part of 'package:sanmill/screens/game_page/game_page.dart';

class PiecePaintParam {
  final String piece;
  final Offset pos;
  final bool animated;
  PiecePaintParam({
    required this.piece,
    required this.pos,
    required this.animated,
  });
}

class PiecesPainter extends PiecesBasePainter {
  final Position position;
  final int focusIndex;
  final int blurIndex;
  final double animationValue;

  int pointStyle = 0;
  double pointWidth = 10.0;
  double pieceWidth = 0.0;
  double animatedPieceWidth = 0.0;

  PiecesPainter({
    required double width,
    required this.position,
    this.focusIndex = invalidIndex,
    this.blurIndex = invalidIndex,
    required this.animationValue,
  }) : super(width: width) {
    pointStyle = LocalDatabaseService.display.pointStyle;
    pointWidth = LocalDatabaseService.display.pointWidth;
    pieceWidth = squareWidth * LocalDatabaseService.display.pieceWidth;
    animatedPieceWidth =
        squareWidth * LocalDatabaseService.display.pieceWidth * animationValue;
  }

  @override
  void paint(Canvas canvas, Size size) {
    doPaint(
      canvas,
      thePaint,
      position: position,
      gridWidth: gridWidth,
      squareWidth: squareWidth,
      pointStyle: pointStyle,
      pointWidth: pointWidth,
      pieceWidth: pieceWidth,
      animatedPieceWidth: animatedPieceWidth,
      offsetX: AppTheme.boardPadding + squareWidth / 2,
      offsetY: AppTheme.boardPadding + squareWidth / 2,
      focusIndex: focusIndex,
      blurIndex: blurIndex,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

  static void doPaint(
    Canvas canvas,
    Paint paint, {
    required Position position,
    required double gridWidth,
    required double squareWidth,
    required int pointStyle,
    required double pointWidth,
    required double pieceWidth,
    required double animatedPieceWidth,
    required double offsetX,
    required double offsetY,
    int focusIndex = invalidIndex,
    int blurIndex = invalidIndex,
  }) {
    final left = offsetX;
    final top = offsetY;

    final shadowPath = Path();
    final piecesToDraw = <PiecePaintParam>[];

    late Color blurPositionColor;
    Color focusPositionColor;

    // Draw pieces on board
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;
        final piece = position.pieceOnGrid(index); // No Pieces when initial

        if (piece == Piece.noPiece) continue;

        final pos = Offset(left + squareWidth * col, top + squareWidth * row);
        final animated = focusIndex == index;

        piecesToDraw
            .add(PiecePaintParam(piece: piece, pos: pos, animated: animated));

        shadowPath.addOval(
          Rect.fromCenter(center: pos, width: pieceWidth, height: pieceWidth),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);

    paint.style = PaintingStyle.fill;

    for (final pps in piecesToDraw) {
      final pieceRadius = pieceWidth / 2;
      final pieceInnerRadius = pieceRadius * 0.99;

      final animatedPieceRadius = animatedPieceWidth / 2;
      final animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // Draw Border of Piece
      switch (pps.piece) {
        case Piece.whiteStone:
          paint.color = AppTheme.whitePieceBorderColor;
          canvas.drawCircle(
            pps.pos,
            pps.animated ? animatedPieceRadius : pieceRadius,
            paint,
          );
          paint.color = LocalDatabaseService.colorSettings.whitePieceColor;
          canvas.drawCircle(
            pps.pos,
            pps.animated ? animatedPieceInnerRadius : pieceInnerRadius,
            paint,
          );
          blurPositionColor = LocalDatabaseService.colorSettings.whitePieceColor
              .withOpacity(0.1);
          break;
        case Piece.blackStone:
          paint.color = AppTheme.blackPieceBorderColor;
          canvas.drawCircle(
            pps.pos,
            pps.animated ? animatedPieceRadius : pieceRadius,
            paint,
          );
          paint.color = LocalDatabaseService.colorSettings.blackPieceColor;
          canvas.drawCircle(
            pps.pos,
            pps.animated ? animatedPieceInnerRadius : pieceInnerRadius,
            paint,
          );
          blurPositionColor = LocalDatabaseService.colorSettings.blackPieceColor
              .withOpacity(0.1);
          break;
        case Piece.ban:
          //print("pps.piece is Ban");
          break;
        default:
          assert(false);
          break;
      }
    }

    // draw focus and blur position

    final int row = focusIndex ~/ 7;
    final int column = focusIndex % 7;

    if (focusIndex != invalidIndex) {
      focusPositionColor =
          LocalDatabaseService.colorSettings.pieceHighlightColor;

      paint.color = focusPositionColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        Offset(left + column * squareWidth, top + row * squareWidth),
        animatedPieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != invalidIndex) {
      final row = blurIndex ~/ 7;
      final column = blurIndex % 7;

      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(left + column * squareWidth, top + row * squareWidth),
        animatedPieceWidth / 2 * 0.8,
        paint,
      );
    }
  }
}
