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
    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) * DB().displaySettings.pieceWidth / 6 - 1;
    const double shadowBlurRadius = 2.0;  // 阴影模糊半径
    const Color shadowColor = Colors.black;  // 阴影颜色
    const Offset shadowOffset = Offset(1.0, 1.0);  // 阴影偏移量

    // 绘制棋子及其阴影
    late Color blurPositionColor;
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;
        final PieceColor piece = GameController().position.pieceOnGrid(index);
        if (piece == PieceColor.none) {
          continue;
        }

        blurPositionColor = piece.blurPositionColor;

        final Offset startPos = pointFromIndex(previousFocusIndex ?? index, size);
        final Offset endPos = pointFromIndex(index, size);
        final Offset currentPosition = Offset.lerp(startPos, endPos, focusIndex == index ? animationValue : 1.0)!;

        // 绘制棋子的阴影
        final Path shadowPath = Path();
        shadowPath.addOval(Rect.fromCircle(center: currentPosition + shadowOffset, radius: pieceWidth / 2));
        canvas.drawShadow(shadowPath, shadowColor, shadowBlurRadius, true);

        // 绘制棋子边框
        paint.color = piece.borderColor; // 边框颜色
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(currentPosition, pieceWidth / 2, paint);

        // 绘制棋子的主体
        //paint.strokeWidth = 2; // 边框宽度
        paint.color = piece.pieceColor;
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(currentPosition, pieceWidth / 2 * 0.99 , paint);
      }
    }

    // 其他绘制代码，例如焦点圈和模糊圈
    if (focusIndex != null && GameController().gameInstance.gameMode != GameMode.setupPosition) {
      paint.color = DB().colorSettings.pieceHighlightColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      final Offset focusPosition = pointFromIndex(focusIndex, size);
      canvas.drawCircle(focusPosition, pieceWidth / 2, paint);
    }

    if (blurIndex != null && GameController().gameInstance.gameMode != GameMode.setupPosition) {
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
