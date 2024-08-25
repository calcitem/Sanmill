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

part of '../../../game_page/services/painters/painters.dart';

/// Piece Animation Type
///
/// The type of animation to play when placing/moving/removing a piece.
enum PieceAnimationType {
  none,
  place,
  remove,
  move,
}

/// Piece Information
///
/// Holds parameters needed to paint each piece.
@immutable
class PiecePaintParam {
  const PiecePaintParam({
    required this.piece,
    required this.startPos,
    required this.endPos,
    required this.animationType,
    required this.animationProgress,
    required this.diameter,
    this.squareAttribute,
    this.image,
  });

  /// The color of the piece.
  final PieceColor piece;

  /// The start position of the piece.
  ///
  /// This represents the starting position on the canvas before animation.
  final Offset startPos;

  /// The end position of the piece.
  ///
  /// This represents the final position on the canvas after animation.
  final Offset endPos;

  /// The type of animation to play.
  final PieceAnimationType animationType;

  /// The progress of the animation.
  final double animationProgress;

  final double diameter;
  final SquareAttribute? squareAttribute;
  final ui.Image? image; // Image for the piece
}

/// Custom Piece Painter
///
/// Painter to draw each piece in [GameController.position] on the Board.
/// The board is drawn by [BoardPainter].
/// It asserts the Canvas to be a square.
class PiecePainter extends CustomPainter {
  PiecePainter({
    required this.animationValue,
    required this.pieceImages, // Add pieceImages parameter
  });

  /// The value representing the piece animation when placing.
  final double animationValue;
  final Map<PieceColor, ui.Image?>? pieceImages; // Add pieceImages field

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = GameController().gameInstance.focusIndex;
    final int? previousFocusIndex =
        GameController().gameInstance.previousFocusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;

    final Paint paint = Paint();
    const double shadowBlurRadius = 2.0; // Shadow blur radius
    const Color shadowColor = Colors.black; // Shadow color
    const Offset shadowOffset = Offset(1.0, 1.0); // Shadow offset

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;

    // Draw pieces on board
    late Color blurPositionColor;
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;
        final PieceColor piece = GameController().position.pieceOnGrid(index);
        if (piece == PieceColor.none) {
          continue;
        }

        final int sq = indexToSquare[index]!;
        final SquareAttribute squareAttribute =
            GameController().position.sqAttrList[sq];

        blurPositionColor = piece.blurPositionColor;

        final Offset startPos =
            pointFromIndex(previousFocusIndex ?? index, size);
        final Offset endPos = pointFromIndex(index, size);
        final Offset currentPosition = Offset.lerp(
            startPos, endPos, focusIndex == index ? animationValue : 1.0)!;

        final ui.Image? image =
            pieceImages == null ? null : pieceImages?[piece];

        // Draw the piece's shadow
        final Path shadowPath = Path();
        shadowPath.addOval(Rect.fromCircle(
            center: currentPosition + shadowOffset, radius: pieceWidth / 2));
        canvas.drawShadow(shadowPath, shadowColor, shadowBlurRadius, true);

        if (image != null) {
          // Draw the piece image if available
          paintImage(
            canvas: canvas,
            rect: Rect.fromCircle(
              center: currentPosition,
              radius: pieceWidth / 2 * 0.99,
            ),
            image: image,
            fit: BoxFit.cover,
          );
        } else {
          // Draw the piece border and body if image is not available
          paint.color = piece.borderColor;

          if (DB().colorSettings.boardBackgroundColor == Colors.white) {
            paint.style = PaintingStyle.stroke;
            paint.strokeWidth = 4.0;
          } else {
            paint.style = PaintingStyle.fill;
          }

          canvas.drawCircle(
            currentPosition,
            pieceWidth / 2,
            paint,
          );

          paint.style = PaintingStyle.fill;
          paint.color = piece.pieceColor;
          canvas.drawCircle(
            currentPosition,
            pieceWidth / 2 * 0.99,
            paint,
          );
        }

        // Draw focus position
        if (focusIndex != null &&
            GameController().gameInstance.gameMode != GameMode.setupPosition &&
            focusIndex == index) {
          // Only draw circle for the moving piece
          paint.color = DB().colorSettings.pieceHighlightColor;
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 2;

          // Use currentPosition to follow the piece movement
          final Offset focusPosition = currentPosition;
          canvas.drawCircle(focusPosition, pieceWidth / 2, paint);
        }

        // Draw number on piece if necessary
        if (DB().displaySettings.isNumbersOnPiecesShown &&
            squareAttribute.placedPieceNumber != null &&
            squareAttribute.placedPieceNumber > 0) {
          final TextPainter textPainter = TextPainter(
            text: TextSpan(
              text: squareAttribute.placedPieceNumber.toString(),
              style: TextStyle(
                color: piece.pieceColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                fontSize: pieceWidth * 0.5,
              ),
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();

          final Offset textOffset = Offset(
            currentPosition.dx - textPainter.width / 2,
            currentPosition.dy - textPainter.height / 2,
          );

          textPainter.paint(canvas, textOffset);
        }
      }
    }

    // Draw blur position

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      if (kDebugMode) {
        if (blurPositionColor == Colors.transparent) {
          throw Exception('Blur position color is transparent');
        }
      }
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      final Offset blurPosition = pointFromIndex(blurIndex, size);
      canvas.drawCircle(blurPosition, pieceWidth / 2 * 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
