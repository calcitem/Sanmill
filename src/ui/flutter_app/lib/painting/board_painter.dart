/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/mill.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/style/colors.dart';
import 'package:sanmill/widgets/board.dart';

import 'painter_base.dart';

class BoardPainter extends PiecesBasePainter {
  BoardPainter({required double width}) : super(width: width);

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
    required double offsetX,
    required double offsetY,
  }) {
    paint.color = Color(Config.boardLineColor);
    paint.style = PaintingStyle.stroke;

    var left = offsetX;
    var top = offsetY;

    paint.strokeWidth = Config.boardBorderLineWidth;

    if (Config.isPieceCountInHandShown) {
      var pieceInHandCount =
          Game.shared.position.pieceInHandCount[PieceColor.white];

      var pieceInHandCountStr = "";

      if (Game.shared.position.phase == Phase.placing) {
        pieceInHandCountStr = pieceInHandCount.toString();
      }

      TextSpan textSpan = TextSpan(
          style:
              TextStyle(fontSize: 48, color: UIColors.boardLineColor), // TODO
          text: pieceInHandCountStr);

      TextPainter textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr);

      textPainter.layout();

      textPainter.paint(
          canvas,
          Offset(left + squareWidth * 3 - textPainter.width / 2,
              top + squareWidth * 3 - textPainter.height / 2));
    }

    canvas.drawRect(
      Rect.fromLTWH(left, top, squareWidth * 6, squareWidth * 6),
      paint,
    );

    paint.strokeWidth = Config.boardInnerLineWidth;

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

    if (!Config.hasDiagonalLines) {
      return;
    }

    // top left diagonal line
    canvas.drawLine(
      Offset(left + 0, top),
      Offset(left + squareWidth * 2, top + squareWidth * 2),
      paint,
    );

    // lower right diagonal line
    canvas.drawLine(
      Offset(left + squareWidth * 4, top + squareWidth * 4),
      Offset(left + squareWidth * 6, top + squareWidth * 6),
      paint,
    );

    // top right diagonal line
    canvas.drawLine(
      Offset(left + squareWidth * 6, top),
      Offset(left + squareWidth * 4, top + squareWidth * 2),
      paint,
    );

    // lower left diagonal line
    canvas.drawLine(
      Offset(left + squareWidth * 2, top + squareWidth * 4),
      Offset(left + squareWidth * 0, top + squareWidth * 6),
      paint,
    );
  }
}
