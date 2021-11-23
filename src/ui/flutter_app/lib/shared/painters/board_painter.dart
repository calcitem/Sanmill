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

part of 'package:sanmill/screens/game_page/game_page.dart';

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

  static void doPaint(
    Canvas canvas,
    Paint paint,
    double gridWidth,
    double squareWidth, {
    required double offsetX,
    required double offsetY,
  }) {
    paint.color = LocalDatabaseService.colorSettings.boardLineColor;
    paint.style = PaintingStyle.stroke;

    final left = offsetX;
    final top = offsetY;

    paint.strokeWidth = LocalDatabaseService.display.boardBorderLineWidth;

    if (LocalDatabaseService.display.isPieceCountInHandShown) {
      var pieceInHandCount =
          gameInstance.position.pieceInHandCount[PieceColor.black];

      if (gameInstance.position.pieceOnBoardCount[PieceColor.white] == 0 &&
          gameInstance.position.pieceOnBoardCount[PieceColor.black] == 0) {
        pieceInHandCount = LocalDatabaseService.rules.piecesCount;
      }

      var pieceInHandCountStr = "";

      // TODO: [Leptopoda] only paint it when the phase is placing.
      if (gameInstance.position.phase == Phase.placing) {
        pieceInHandCountStr = pieceInHandCount.toString();
      }

      final TextSpan textSpan = TextSpan(
        style: TextStyle(
          fontSize: 48,
          color: LocalDatabaseService.colorSettings.boardLineColor,
        ), // TODO
        text: pieceInHandCountStr,
      );

      final TextPainter textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          left + squareWidth * 3 - textPainter.width / 2,
          top + squareWidth * 3 - textPainter.height / 2,
        ),
      );
    }

    if (LocalDatabaseService.display.isNotationsShown) {
      const String verticalNotations = "abcdefg";
      const String horizontalNotations = "7654321";
      String notationV = "";
      String notationH = "";

      for (int i = 0; i < 7; i++) {
        notationV = verticalNotations[i];
        notationH = horizontalNotations[i];

        final TextSpan notationSpanV = TextSpan(
          style: AppTheme.notationTextStyle, // TODO
          text: notationV,
        );

        final TextSpan notationSpanH = TextSpan(
          style: AppTheme.notationTextStyle, // TODO
          text: notationH,
        );

        final TextPainter notationPainterV = TextPainter(
          text: notationSpanV,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        final TextPainter notationPainterH = TextPainter(
          text: notationSpanH,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        notationPainterV.layout();
        notationPainterH.layout();

        final offset = (boardWidth - squareWidth * 6) / 4;

        // Show notations "a b c d e f" on board

        if (LocalDatabaseService.preferences.developerMode) {
          notationPainterV.paint(
            canvas,
            Offset(
              left + squareWidth * i - notationPainterV.width / 2,
              top - offset - notationPainterV.height / 2,
            ),
          );
        }

        notationPainterV.paint(
          canvas,
          Offset(
            left + squareWidth * i - notationPainterV.width / 2,
            top + squareWidth * 6 + offset - notationPainterV.height / 2,
          ),
        );

        // Show notations "1 2 3 4 5 6 7" on board

        notationPainterH.paint(
          canvas,
          Offset(
            left - offset - notationPainterH.width / 2,
            top + squareWidth * i - notationPainterH.height / 2,
          ),
        );

        if (LocalDatabaseService.preferences.developerMode) {
          notationPainterH.paint(
            canvas,
            Offset(
              left + squareWidth * 6 + offset - notationPainterH.width / 2,
              top + squareWidth * i - notationPainterH.height / 2,
            ),
          );
        }
      }
    }

    // File C
    canvas.drawRect(
      Rect.fromLTWH(left, top, squareWidth * 6, squareWidth * 6),
      paint,
    );

    paint.strokeWidth = LocalDatabaseService.display.boardInnerLineWidth;
    final double bias = paint.strokeWidth / 2;

    // File B
    canvas.drawRect(
      Rect.fromLTWH(
        left + squareWidth * 1,
        top + squareWidth * 1,
        squareWidth * 4,
        squareWidth * 4,
      ),
      paint,
    );

    // File A
    canvas.drawRect(
      Rect.fromLTWH(
        left + squareWidth * 2,
        top + squareWidth * 2,
        squareWidth * 2,
        squareWidth * 2,
      ),
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

    // Point
    if (LocalDatabaseService.display.pointStyle != 0) {
      if (LocalDatabaseService.display.pointStyle == 1) {
        paint.style = PaintingStyle.fill;
      } else if (LocalDatabaseService.display.pointStyle == 2) {
        paint.style = PaintingStyle.stroke; // TODO: WIP
      }

      final double pointRadius = LocalDatabaseService.display.pointWidth;

      final points = [
        [0, 0],
        [0, 3],
        [0, 6],
        [1, 1],
        [1, 3],
        [1, 5],
        [2, 2],
        [2, 3],
        [2, 4],
        [3, 0],
        [3, 1],
        [3, 2],
        [3, 4],
        [3, 5],
        [3, 6],
        [4, 2],
        [4, 3],
        [4, 4],
        [5, 1],
        [5, 3],
        [5, 5],
        [6, 0],
        [6, 3],
        [6, 6],
      ];

      for (final point in points) {
        canvas.drawCircle(
          Offset(left + squareWidth * point[0], top + squareWidth * point[1]),
          pointRadius,
          paint,
        );
      }
    }

    if (!LocalDatabaseService.rules.hasDiagonalLines) {
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
