import 'package:flutter/material.dart';

import '../common/color-consts.dart';
import '../game/battle.dart';
import 'board-painter.dart';
import 'pieces-painter.dart';
import 'words-on-board.dart';

class BoardWidget extends StatelessWidget {
  //
  static const padding = 5.0;
  static const digitsHeight = 0.0;

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
        borderRadius: BorderRadius.circular(5),
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
            horizontal: (width - padding * 2) / 7 / 2 +
                padding -
                WordsOnBoard.DigitsFontSize / 2,
          ),
          //child: WordsOnBoard(),
        ),
      ),
    );

    return GestureDetector(
      child: boardContainer,
      onTapUp: (d) {
        //
        final gridWidth = (width - padding * 2) * 6 / 7;
        final squareSide = gridWidth / 8;

        final dx = d.localPosition.dx, dy = d.localPosition.dy;
        final row = (dy - padding - digitsHeight) ~/ squareSide;
        final column = (dx - padding) ~/ squareSide;

        if (row < 0 || row > 6) return;

        if (column < 0 || column > 6) return;

        onBoardTap(context, row * 7 + column);
      },
    );
  }
}
