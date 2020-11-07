import 'package:flutter/material.dart';

import '../common/color.dart';
import '../game/battle.dart';
import 'board_painter.dart';
import 'pieces_painter.dart';
import 'words_on_board.dart';

class BoardWidget extends StatelessWidget {
  //
  static const padding = 5.0;
  static const digitsHeight = 0.0;

  static const double boardBorderRadius = 5;

  final double width;
  final double height;
  final Function(BuildContext, int) onBoardTap;

  BoardWidget({@required this.width, @required this.onBoardTap})
      : height = width;

  @override
  Widget build(BuildContext context) {
    //
    final boardContainer = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(boardBorderRadius),
        color: ColorConst.boardBackgroundColor,
      ),
      child: CustomPaint(
        painter: BoardPainter(width: width),
        foregroundPainter: PiecesPainter(
          width: width,
          position: Battle.shared.position,
          focusIndex: Battle.shared.focusIndex,
          blurIndex: Battle.shared.blurIndex,
        ),
        child: Container(
          margin: EdgeInsets.symmetric(
            vertical: padding,
            horizontal: (width - padding * 2) / 6 / 2 +
                padding -
                WordsOnBoard.digitsFontSize / 2,
          ),
          //child: WordsOnBoard(),
        ),
      ),
    );

    return GestureDetector(
      child: boardContainer,
      onTapUp: (d) {
        //
        final gridWidth = (width - padding * 2);
        final squareWidth = gridWidth / 7;

        final dx = d.localPosition.dx, dy = d.localPosition.dy;
        final row = (dy - padding - digitsHeight) ~/ squareWidth;
        final column = (dx - padding) ~/ squareWidth;

        if (row < 0 || row > 6) return;

        if (column < 0 || column > 6) return;

        onBoardTap(context, row * 6 + column);
      },
    );
  }
}
