import 'package:flutter/material.dart';

import '../board/painter_base.dart';
import '../common/color.dart';
import 'board_widget.dart';

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
      squareWidth,
      offsetX: BoardWidget.padding + squareWidth / 2,
      offsetY: BoardWidget.padding + BoardWidget.digitsHeight + squareWidth / 2,
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
    double squareWidth, {
    double offsetX,
    double offsetY,
  }) {
    //
    paint.color = ColorConst.boardLineColor;
    paint.style = PaintingStyle.stroke;

    const double borderLineWidth = 2.0;
    const double innerLineWidth = 1.0;

    var left = offsetX;
    var top = offsetY;

    paint.strokeWidth = borderLineWidth;

    canvas.drawRect(
      Rect.fromLTWH(left, top, squareWidth * 6, squareWidth * 6),
      paint,
    );

    paint.strokeWidth = innerLineWidth;

    // Horizontal lines (Top to Bottom)

    canvas.drawLine(
      Offset(left + squareWidth * 1, top + squareWidth * 1),
      Offset(left + squareWidth * 5, top + squareWidth * 1),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 2, top + squareWidth * 2),
      Offset(left + squareWidth * 4, top + squareWidth * 2),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 2, top + squareWidth * 4),
      Offset(left + squareWidth * 4, top + squareWidth * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 1, top + squareWidth * 5),
      Offset(left + squareWidth * 5, top + squareWidth * 5),
      paint,
    );

    // Middle horizontal lines (Left to Right)

    canvas.drawLine(
      Offset(left, top + squareWidth * 3),
      Offset(left + squareWidth * 2, top + squareWidth * 3),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 4, top + squareWidth * 3),
      Offset(left + squareWidth * 6, top + squareWidth * 3),
      paint,
    );

    // Ordinate Lines (Left to Right)

    canvas.drawLine(
      Offset(left + squareWidth * 1, top + squareWidth * 1),
      Offset(left + squareWidth * 1, top + squareWidth * 5),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 2, top + squareWidth * 2),
      Offset(left + squareWidth * 2, top + squareWidth * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 4, top + squareWidth * 2),
      Offset(left + squareWidth * 4, top + squareWidth * 4),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 5, top + squareWidth * 1),
      Offset(left + squareWidth * 5, top + squareWidth * 5),
      paint,
    );

    // Middle horizontal lines (Top to Bottom)

    canvas.drawLine(
      Offset(left + squareWidth * 3, top),
      Offset(left + squareWidth * 3, top + squareWidth * 2),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 3, top + squareWidth * 4),
      Offset(left + squareWidth * 3, top + squareWidth * 6),
      paint,
    );

    // top left oblique line
    canvas.drawLine(
      Offset(left + 0, top),
      Offset(left + squareWidth * 2, top + squareWidth * 2),
      paint,
    );

    // lower right oblique line
    canvas.drawLine(
      Offset(left + squareWidth * 4, top + squareWidth * 4),
      Offset(left + squareWidth * 6, top + squareWidth * 6),
      paint,
    );

    // top right oblique line
    canvas.drawLine(
      Offset(left + squareWidth * 6, top),
      Offset(left + squareWidth * 4, top + squareWidth * 2),
      paint,
    );

    // lower left oblique line
    canvas.drawLine(
      Offset(left + squareWidth * 2, top + squareWidth * 4),
      Offset(left + squareWidth * 0, top + squareWidth * 6),
      paint,
    );
  }
}
