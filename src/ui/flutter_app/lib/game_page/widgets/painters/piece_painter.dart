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
  });

  /// The color of the piece.
  final PieceColor piece;

  /// The position the piece is placed at.
  ///
  /// This represents the final position on the canvas.
  /// To extract this information from the board index use [pointFromIndex].
  final Offset startPos;
  final Offset endPos;
  final PieceAnimationType animationType;
  final double animationProgress;
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
    final int? previousFocusIndex = GameController().gameInstance.previousFocusIndex;
    final int? blurIndex = GameController().gameInstance.blurIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
        DB().displaySettings.pieceWidth /
        6 -
        1;

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

        final Offset startPos = pointFromIndex(previousFocusIndex ?? index, size);
        final Offset endPos = pointFromIndex(index, size);
        final bool animated = focusIndex == index;

        late PieceAnimationType pieceAnimationType;

        if (GameController().position.phase == Phase.placing) {
          if (GameController().position.action == Act.place) {
            pieceAnimationType = PieceAnimationType.place;
          } else if (GameController().position.action == Act.remove) {
            pieceAnimationType = PieceAnimationType.remove;
          } else {
            pieceAnimationType = PieceAnimationType.none;
          }
        } else if (GameController().position.phase == Phase.moving) {
          if (GameController().position.action == Act.remove) {
            pieceAnimationType = PieceAnimationType.none;
          } else {
            pieceAnimationType = PieceAnimationType.move;
          }
        } else {
          pieceAnimationType = PieceAnimationType.none;
        }

        piecesToDraw.add(
          PiecePaintParam(
            piece: piece,
            startPos: startPos,
            endPos: endPos,
            animationType: pieceAnimationType,
            animationProgress: animated ? animationValue : 1.0,
            diameter: pieceWidth,
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

      final Offset currentPosition = Offset.lerp(
          piece.startPos,
          piece.endPos,
          piece.animationProgress
      )!;

      // Draw Border of Piece
      paint.color = piece.piece.borderColor;
      canvas.drawCircle(currentPosition, piece.diameter / 2, paint);

      // Draw the piece
      double currentDiameter;
      switch (piece.animationType) {
        case PieceAnimationType.place:
          currentDiameter = lerpDouble(1.1 * piece.diameter, piece.diameter, piece.animationProgress)!;
          break;
        case PieceAnimationType.remove:
          currentDiameter = lerpDouble(piece.diameter, 0.9 * piece.diameter, piece.animationProgress)!;
          break;
        case PieceAnimationType.move:
          currentDiameter = piece.diameter;
          break;
        case PieceAnimationType.none:
          currentDiameter = piece.diameter;
          break;
      }

      // Set the color of the piece
      paint.color = piece.piece.pieceColor;

      // Draw the piece with the current diameter
      canvas.drawCircle(currentPosition, currentDiameter / 2, paint);
    }

    // Draw focus and blur position
    if (focusIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        pointFromIndex(focusIndex, size),
        pieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null &&
        GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        pointFromIndex(blurIndex, size),
        pieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
