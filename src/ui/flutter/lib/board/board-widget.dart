import '../game/battle.dart';
import 'package:flutter/material.dart';
import '../common/color-consts.dart';
import 'board-painter.dart';
import 'pieces-painter.dart';
import 'words-on-board.dart';

class BoardWidget extends StatelessWidget {
  //
  static const Padding = 5.0, DigitsHeight = 0.0;

  final double width, height;
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
        color: ColorConsts.BoardBackground,
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
            vertical: Padding,
            horizontal: (width - Padding * 2) / 7 / 2 +
                Padding -
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
        final gridWidth = (width - Padding * 2) * 6 / 7;
        final squareSide = gridWidth / 8;

        final dx = d.localPosition.dx, dy = d.localPosition.dy;
        final row = (dy - Padding - DigitsHeight) ~/ squareSide;
        final column = (dx - Padding) ~/ squareSide;

        if (row < 0 || row > 6) return;
        if (column < 0 || column > 6) return;

        onBoardTap(context, row * 7 + column);
      },
    );
  }
}
