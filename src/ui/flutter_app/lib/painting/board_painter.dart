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
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/game_page.dart';

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
      offsetX: AppTheme.boardPadding + squareWidth / 2,
      offsetY: AppTheme.boardPadding + squareWidth / 2,
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
          Game.instance.position.pieceInHandCount[PieceColor.black];

      if (Game.instance.position.pieceOnBoardCount[PieceColor.white] == 0 &&
          Game.instance.position.pieceOnBoardCount[PieceColor.black] == 0) {
        pieceInHandCount = Config.piecesCount;
      }

      var pieceInHandCountStr = "";

      if (Game.instance.position.phase == Phase.placing) {
        pieceInHandCountStr = pieceInHandCount.toString();
      }

      TextSpan textSpan = TextSpan(
          style: TextStyle(
              fontSize: 48, color: Color(Config.boardLineColor)), // TODO
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

    if (Config.isNotationsShown) {
      String verticalNotations = "abcdefg";
      String horizontalNotations = "7654321";
      String notationV = "";
      String notationH = "";

      for (int i = 0; i < 7; i++) {
        notationV = verticalNotations[i];
        notationH = horizontalNotations[i];

        TextSpan notationSpanV = TextSpan(
          style:
              TextStyle(fontSize: 20, color: AppTheme.boardLineColor), // TODO
          text: notationV,
        );

        TextSpan notationSpanH = TextSpan(
          style:
              TextStyle(fontSize: 20, color: AppTheme.boardLineColor), // TODO
          text: notationH,
        );

        TextPainter notationPainterV = TextPainter(
          text: notationSpanV,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        TextPainter notationPainterH = TextPainter(
          text: notationSpanH,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        notationPainterV.layout();
        notationPainterH.layout();

        var offset = (boardWidth - squareWidth * 6) / 4;

        /* Show notations "a b c d e f" on board */

        if (Config.developerMode) {
          notationPainterV.paint(
            canvas,
            Offset(left + squareWidth * i - notationPainterV.width / 2,
                top - offset - notationPainterV.height / 2),
          );
        }

        notationPainterV.paint(
          canvas,
          Offset(left + squareWidth * i - notationPainterV.width / 2,
              top + squareWidth * 6 + offset - notationPainterV.height / 2),
        );

        /* Show notations "1 2 3 4 5 6 7" on board */

        notationPainterH.paint(
          canvas,
          Offset(left - offset - notationPainterH.width / 2,
              top + squareWidth * i - notationPainterH.height / 2),
        );

        if (Config.developerMode) {
          notationPainterH.paint(
            canvas,
            Offset(left + squareWidth * 6 + offset - notationPainterH.width / 2,
                top + squareWidth * i - notationPainterH.height / 2),
          );
        }
      }
    }

    // File C
    canvas.drawRect(
      Rect.fromLTWH(left, top, squareWidth * 6, squareWidth * 6),
      paint,
    );

    paint.strokeWidth = Config.boardInnerLineWidth;
    double bias = paint.strokeWidth / 2;

    // File B
    canvas.drawRect(
      Rect.fromLTWH(left + squareWidth * 1, top + squareWidth * 1,
          squareWidth * 4, squareWidth * 4),
      paint,
    );

    // File A
    canvas.drawRect(
      Rect.fromLTWH(left + squareWidth * 2, top + squareWidth * 2,
          squareWidth * 2, squareWidth * 2),
      paint,
    );

    // Middle horizontal lines (Left to Right)

    canvas.drawLine(
      Offset(left - bias, top + squareWidth * 3),
      Offset(left + squareWidth * 2 + bias, top + squareWidth * 3),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 4 - bias, top + squareWidth * 3),
      Offset(left + squareWidth * 6 + bias, top + squareWidth * 3),
      paint,
    );

    // Middle horizontal lines (Top to Bottom)

    canvas.drawLine(
      Offset(left + squareWidth * 3, top - bias),
      Offset(left + squareWidth * 3, top + squareWidth * 2 + bias),
      paint,
    );

    canvas.drawLine(
      Offset(left + squareWidth * 3, top + squareWidth * 4 - bias),
      Offset(left + squareWidth * 3, top + squareWidth * 6 + bias),
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
