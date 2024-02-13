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
    required this.piece,
    required this.pos,
    required this.animated,
    required this.diameter,
  });

  /// The color of the piece.
  final PieceColor piece;

  /// The position the piece is placed at.
  ///
  /// This represents the final position on the canvas.
  /// To extract this information from the board index use [pointFromIndex].
  final Offset pos;
  final bool animated;
  final double diameter;
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

  /// The value representing the piece animation when placing.
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = GameController().gameInstance.focusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;
    final double animatedPieceWidth = pieceWidth * animationValue;

    // Draw pieces on board
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;

        final PieceColor piece = GameController()
            .position
            .pieceOnGrid(index); // No Pieces when initial

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
            radius: (animated ? animatedPieceWidth : pieceWidth) / 2,
          ),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);
    paint.style = PaintingStyle.fill;

    Color blurPositionColor = Colors.transparent;
    for (final PiecePaintParam piece in piecesToDraw) {
      assert(
        piece.piece == PieceColor.black ||
            piece.piece == PieceColor.white ||
            piece.piece == PieceColor.ban,
      );
      blurPositionColor = piece.piece.blurPositionColor;

      final double pieceRadius = pieceWidth / 2;
      final double pieceInnerRadius = pieceRadius * 0.99;

      final double animatedPieceRadius = animatedPieceWidth / 2;
      final double animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // Draw Border of Piece
      paint.color = piece.piece.borderColor;
      canvas.drawCircle(
        piece.pos,
        piece.animated ? animatedPieceRadius : pieceRadius,
        paint,
      );
      // Draw the piece
      paint.color = piece.piece.pieceColor;
      canvas.drawCircle(
        piece.pos,
        piece.animated ? animatedPieceInnerRadius : pieceInnerRadius,
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
        pointFromIndex(focusIndex, size),
        animatedPieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      if (kDebugMode) {
        if (blurPositionColor == Colors.transparent) {
          throw Exception('Blur position color is transparent');
        }
      }
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
  bool shouldRepaint(PiecePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
