import 'package:flutter/material.dart';
import '../board/painter-base.dart';
import '../common/color-consts.dart';
import 'board-widget.dart';

class BoardPainter extends PainterBase {
  //
  BoardPainter({@required double width}) : super(width: width);

  @override
  void paint(Canvas canvas, Size size) {
    //
    doPaint(
      canvas,
      thePaint,
      gridWidth,
      squareSide,
      offsetX: BoardWidget.Padding + squareSide / 2,
      offsetY: BoardWidget.Padding + BoardWidget.DigitsHeight + squareSide / 2,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }

  static doPaint(
    Canvas canvas,
    Paint paint,
    double gridWidth,
    double squareSide, {
    double offsetX,
    double offsetY,
  }) {
    //
    paint.color = ColorConsts.BoardLine;
    paint.style = PaintingStyle.stroke;

    var left = offsetX;
    var top = offsetY;

    // 外框
    paint.strokeWidth = 2;

    canvas.drawRect(
      //Rect.fromLTWH(left, top, gridWidth, squareSide * 6),
      Rect.fromLTWH(left, top, squareSide * 6, squareSide * 6),
      paint,
    );

    paint.strokeWidth = 1;

    // 横线 (从上到下)

    canvas.drawLine(
      Offset(left + squareSide * 1, top + squareSide * 1),
      Offset(left + squareSide * 5, top + squareSide * 1),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 2, top + squareSide * 2),
      Offset(left + squareSide * 4, top + squareSide * 2),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 2, top + squareSide * 4),
      Offset(left + squareSide * 4, top + squareSide * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 1, top + squareSide * 5),
      Offset(left + squareSide * 5, top + squareSide * 5),
      paint,
    );

    // 中间的横线 (从左到右)

    canvas.drawLine(
      Offset(left, top + squareSide * 3),
      Offset(left + squareSide * 2, top + squareSide * 3),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 4, top + squareSide * 3),
      Offset(left + squareSide * 6, top + squareSide * 3),
      paint,
    );

    // 竖线 (从左到右)

    canvas.drawLine(
      Offset(left + squareSide * 1, top + squareSide * 1),
      Offset(left + squareSide * 1, top + squareSide * 5),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 2, top + squareSide * 2),
      Offset(left + squareSide * 2, top + squareSide * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 4, top + squareSide * 2),
      Offset(left + squareSide * 4, top + squareSide * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 5, top + squareSide * 1),
      Offset(left + squareSide * 5, top + squareSide * 5),
      paint,
    );

    // 中间的横线 (从上到下)

    canvas.drawLine(
      Offset(left + squareSide * 3, top),
      Offset(left + squareSide * 3, top + squareSide * 2),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareSide * 3, top + squareSide * 4),
      Offset(left + squareSide * 3, top + squareSide * 6),
      paint,
    );

    // 左上斜线
    canvas.drawLine(
      Offset(left + 0, top),
      Offset(left + squareSide * 2, top + squareSide * 2),
      paint,
    );

    // 右下斜线
    canvas.drawLine(
      Offset(left + squareSide * 4, top + squareSide * 4),
      Offset(left + squareSide * 6, top + squareSide * 6),
      paint,
    );

    // 右上斜线
    canvas.drawLine(
      Offset(left + squareSide * 6, top),
      Offset(left + squareSide * 4, top + squareSide * 2),
      paint,
    );

    // 左下斜线
    canvas.drawLine(
      Offset(left + squareSide * 2, top + squareSide * 4),
      Offset(left + squareSide * 0, top + squareSide * 6),
      paint,
    );
  }
}
