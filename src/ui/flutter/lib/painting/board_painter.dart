/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/widgets/board.dart';

import 'painter_base.dart';

class BoardPainter extends PiecesBasePainter {
  BoardPainter({@required double width}) : super(width: width);

  @override
  void paint(Canvas canvas, Size size) {
    doPaint(
      canvas,
      thePaint,
      gridWidth,
      squareWidth,
      offsetX: Board.padding + squareWidth / 2,
      offsetY: Board.padding + Board.digitsHeight + squareWidth / 2,
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
    paint.color = UIColors.boardLineColor;
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
