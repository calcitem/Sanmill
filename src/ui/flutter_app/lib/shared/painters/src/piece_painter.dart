// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

/// Pice Information
///
/// Holds parameters needed to paint each piece.
@immutable
class _PiecePaintParam {
  /// The color of the piece.
  final PieceColor piece;

  /// The position the pice is placed at.
  ///
  /// This represents the final position on the canvas.
  /// To extract this information from the board index use [pointFromIndex].
  final Offset pos;
  final bool animated;
  final double diameter;

  const _PiecePaintParam({
    required this.piece,
    required this.pos,
    required this.animated,
    required this.diameter,
  });

  // TODO: [Leptopoda] Consider putting this into the PieceColorExtension
  /// Gets the border color of the current piece type.
  Color get borderColor {
    switch (piece) {
      case PieceColor.white:
        return AppTheme.whitePieceBorderColor;
      case PieceColor.black:
        return AppTheme.blackPieceBorderColor;
      default:
        throw Error();
    }
  }

  // TODO: [Leptopoda] Consider putting this into the PieceColorExtension
  /// Gets the color of the current piece
  Color get pieceColor {
    final colorSettings = DB().colorSettings;
    switch (piece) {
      case PieceColor.white:
        return colorSettings.whitePieceColor;
      case PieceColor.black:
        return colorSettings.blackPieceColor;
      default:
        throw Error();
    }
  }

  // TODO: [Leptopoda] Consider putting this into the PieceColorExtension
  /// Gets the color for the blurred position
  Color get blurPositionColor => pieceColor.withOpacity(0.1);
}

/// Custom Piece Painter
///
/// Painter to draw each piece in [MillController.position] on the Board.
/// The board is drawn by [BoardPainter].
/// It asserts the Canvas to be a square.
class PiecePainter extends CustomPainter {
  /// The value representing the piece animation when placing.
  final double animationValue;

  PiecePainter({
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final focusIndex = MillController().gameInstance.focusIndex;
    final blurIndex = MillController().gameInstance.blurIndex;

    final paint = Paint();
    final shadowPath = Path();
    final piecesToDraw = <_PiecePaintParam>[];

    final _pieceWidth = size.width * DB().displaySettings.pieceWidth;
    final _animatedPieceWidth = _pieceWidth * animationValue;

    // Draw pieces on board
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;

        final piece = MillController()
            .position
            .pieceOnGrid(index); // No Pieces when initial

        if (piece == PieceColor.none) continue;

        final pos = pointFromIndex(index, size);
        final animated = focusIndex == index;

        piecesToDraw.add(
          _PiecePaintParam(
            piece: piece,
            pos: pos,
            animated: animated,
            diameter: _pieceWidth,
          ),
        );

        shadowPath.addOval(
          Rect.fromCircle(
            center: pos,
            radius: (animated ? _animatedPieceWidth : _pieceWidth) / 2,
          ),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);
    paint.style = PaintingStyle.fill;

    late Color blurPositionColor;
    for (final piece in piecesToDraw) {
      assert(
        piece.piece == PieceColor.black || piece.piece == PieceColor.white,
      );
      blurPositionColor = piece.blurPositionColor;

      final pieceRadius = _pieceWidth / 2;
      final pieceInnerRadius = pieceRadius * 0.99;

      final animatedPieceRadius = _animatedPieceWidth / 2;
      final animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // Draw Border of Piece
      paint.color = piece.borderColor;
      canvas.drawCircle(
        piece.pos,
        piece.animated ? animatedPieceRadius : pieceRadius,
        paint,
      );
      // Draw the piece
      paint.color = piece.pieceColor;
      canvas.drawCircle(
        piece.pos,
        piece.animated ? animatedPieceInnerRadius : pieceInnerRadius,
        paint,
      );
    }

    // Draw focus and blur position
    if (focusIndex != null) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        pointFromIndex(focusIndex, size),
        _animatedPieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != null) {
      paint.color = blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        pointFromIndex(blurIndex, size),
        _animatedPieceWidth / 2 * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PiecePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
