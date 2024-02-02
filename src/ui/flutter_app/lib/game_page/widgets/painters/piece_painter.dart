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

part of '../../../game_page/widgets/painters/painters.dart';

/// Piece Information
///
/// Holds parameters needed to paint each piece.
@immutable
class PiecePaintParam {
  const PiecePaintParam({
    required this.gamePiece,
  });

  /// Direct reference to the GamePiece instance.
  final GamePiece gamePiece;

  /// Convenience getters to access GamePiece properties.
  PieceColor get piece => gamePiece.pieceColor;
  Offset get pos => gamePiece.position;
  bool get animated => gamePiece.animated;
  double get diameter => gamePiece.diameter;
}

/// Custom Piece Painter
///
/// Painter to draw each piece in [GameController.position] on the Board.
/// The board is drawn by [BoardPainter].
/// It asserts the Canvas to be a square.
class PiecePainter extends CustomPainter {
  PiecePainter({
    required this.animationValue,
  });

  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = GameController().gameInstance.focusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    // Draw pieces on board
    GameController().forEachPiece((int index, GamePiece gamePiece) {
      final Offset pos = pointFromIndex(index, size);
      final bool animated = focusIndex == index;
      if (animated) {
        gamePiece.updateAnimation(animationValue);
      } else {
        gamePiece.resetAnimation();
      }

      piecesToDraw.add(
        PiecePaintParam(
          gamePiece: gamePiece,
        ),
      );

      shadowPath.addOval(
        Rect.fromCircle(
          center: pos,
          radius: (gamePiece.animated ? gamePiece.diameter * gamePiece.animationValue : gamePiece.diameter) / 2,
        ),
      );
    });

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);
    paint.style = PaintingStyle.fill;

    const Color blurPositionColor = Colors.transparent; // Adjust this as necessary

    for (final PiecePaintParam pieceParam in piecesToDraw) {
      final GamePiece piece = pieceParam.gamePiece;

      final double pieceRadius = piece.diameter / 2;
      final double animatedPieceRadius = pieceRadius * piece.animationValue;
      final double pieceInnerRadius = pieceRadius * 0.99;
      final double animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // Draw Border of Piece
      paint.color = piece.borderColor;
      canvas.drawCircle(
        piece.position,
        piece.animated ? animatedPieceRadius : pieceRadius,
        paint,
      );
      // Draw the piece
      paint.color = piece.fillColor;
      canvas.drawCircle(
        piece.position,
        piece.animated ? animatedPieceInnerRadius : pieceInnerRadius,
        paint,
      );
    }

    // For focus and blur positions, compute a generic width for illustration
    final double genericPieceWidth = size.width / 7; // Assuming a 7x7 grid for simplicity
    final double animatedPieceWidth = genericPieceWidth * animationValue;

    // Draw focus and blur position
    if (focusIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        pointFromIndex(focusIndex, size),
        animatedPieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        pointFromIndex(blurIndex, size),
        animatedPieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) => animationValue != oldDelegate.animationValue;
}
