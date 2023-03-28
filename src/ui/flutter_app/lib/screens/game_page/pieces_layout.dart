import 'package:flutter/material.dart';

import '../../services/database/database.dart';
import '../../services/mill/mill.dart';
import '../../shared/painters/painters.dart';
import '../../shared/theme/app_theme.dart';

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

class PiecesLayout {
  //
  final double width;
  final Position position;
  final int? focusIndex, blurIndex;

  final double pieceAnimationValue;
  final bool opponentHuman;

  PiecesLayout(
    this.width,
    this.position, {
    required this.pieceAnimationValue,
    this.focusIndex,
    this.blurIndex,
    this.opponentHuman = false,
  });

  Widget buildPiecesLayout(BuildContext context) {
    final List<Widget> pieces = <Widget>[];
    final double squareSide = width / 8;
    final double diameter = squareSide * 0.8;
    final double pieceAnimationValue = this.pieceAnimationValue;
    final bool opponentHuman = this.opponentHuman;

    final int? focusIndex = MillController().gameInstance.focusIndex;
    final int? blurIndex = MillController().gameInstance.blurIndex;

    final Paint paint = Paint();
    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    final size = Size(width, width); // TODO: Is width board width?

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;

    // Draw pieces on board
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;

        final PieceColor piece = MillController()
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
            radius: (animated ? pieceWidth : pieceWidth) / 2,
          ),
        );
      }
    }

    // Draw shadow of piece
    //drawShadowOfPiece(paint, shadowPath, piecesToDraw, pieceWidth);

    //canvas.drawShadow(shadowPath, Colors.black, 2, true);
    //paint.style = PaintingStyle.fill;

    late Color blurPositionColor;
    late Color focusPositionColor;

    blurPositionColor =
        DB().colorSettings.blackPieceColor.withOpacity(0.5); // TODO
    focusPositionColor = AppTheme.blackPieceBorderColor; // TODO

    // Draw blur position
    if (blurIndex != null) {
      final Offset pos = pointFromIndex(blurIndex, size);
      final double radius = pieceWidth / 2;

      pieces.add(
        Positioned(
          left: pos.dx - radius,
          top: pos.dy - radius,
          child: Container(
            width: pieceWidth,
            height: pieceWidth,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: blurPositionColor,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: pieces,
    );
  }
}
