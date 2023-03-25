// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

part of '../painters.dart';

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

  /// The piece.
  final Piece piece;

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
/// Painter to draw each piece in [MillController.position] on the Board.
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
    final int? focusIndex = MillController().gameInstance.focusIndex;
    final int? blurIndex = MillController().gameInstance.blurIndex;

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

        final PieceColor pieceColor = MillController()
            .position
            .pieceOnGrid(index); // No Pieces when initial

        if (pieceColor == PieceColor.none) {
          continue;
        }

        final Offset pos = pointFromIndex(index, size);
        final bool animated = focusIndex == index;

        piecesToDraw.add(
          PiecePaintParam(
            piece: Piece(color: pieceColor),
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

    // Draw the pieces
    for (final PiecePaintParam pieceParam in piecesToDraw) {
      final Piece pieceWidget = pieceParam.piece;

      final double pieceDiameter = pieceParam.animated
          ? pieceParam.diameter * animationValue
          : pieceParam.diameter;

      canvas.save();
      canvas.translate(pieceParam.pos.dx - pieceDiameter / 2,
          pieceParam.pos.dy - pieceDiameter / 2);
      pieceWidget.paint(canvas, Size(pieceDiameter, pieceDiameter));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
