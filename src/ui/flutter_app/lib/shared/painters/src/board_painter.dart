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

part of '../painters.dart';

class BoardPainter extends PiecesBasePainter {
  BoardPainter({required double width}) : super(width: width);

  @override
  void paint(Canvas canvas, Size size) => _doPaint(canvas, thePaint);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;

  void _doPaint(Canvas canvas, Paint paint) {
    paint.strokeWidth = LocalDatabaseService.display.boardBorderLineWidth;
    paint.color = LocalDatabaseService.colorSettings.boardLineColor;
    paint.style = PaintingStyle.stroke;

    if (LocalDatabaseService.display.isPieceCountInHandShown &&
        controller.position.phase == Phase.placing) {
      final int pieceInHandCount;
      if (controller.position.pieceOnBoardCount[PieceColor.white] == 0 &&
          controller.position.pieceOnBoardCount[PieceColor.black] == 0) {
        pieceInHandCount = LocalDatabaseService.rules.piecesCount;
      } else {
        pieceInHandCount =
            controller.position.pieceInHandCount[PieceColor.black]!;
      }

      final TextSpan textSpan = TextSpan(
        style: TextStyle(
          fontSize: 48,
          color: LocalDatabaseService.colorSettings.boardLineColor,
        ), // TODO
        text: pieceInHandCount.toString(),
      );

      final TextPainter textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        _offset.translate(
          _squareWidth * 3 - textPainter.width / 2,
          _squareWidth * 3 - textPainter.height / 2,
        ),
      );
    }

    if (LocalDatabaseService.display.isNotationsShown) {
      const String verticalNotations = "abcdefg";
      const String horizontalNotations = "7654321";

      for (int i = 0; i < 7; i++) {
        final String notationV = verticalNotations[i];
        final String notationH = horizontalNotations[i];

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

        final offset = (width - _squareWidth * 6) / 4;

        // Show notations "a b c d e f" on board
        if (EnvironmentConfig.devMode) {
          notationPainterV.paint(
            canvas,
            _offset.translate(
              _squareWidth * i - notationPainterV.width / 2,
              -offset - notationPainterV.height / 2,
            ),
          );
        }

        notationPainterV.paint(
          canvas,
          _offset.translate(
            _squareWidth * i - notationPainterV.width / 2,
            _squareWidth * 6 + offset - notationPainterV.height / 2,
          ),
        );

        // Show notations "1 2 3 4 5 6 7" on board
        notationPainterH.paint(
          canvas,
          _offset.translate(
            -offset - notationPainterH.width / 2,
            _squareWidth * i - notationPainterH.height / 2,
          ),
        );

        if (EnvironmentConfig.devMode) {
          notationPainterH.paint(
            canvas,
            _offset.translate(
              _squareWidth * 6 + offset - notationPainterH.width / 2,
              _squareWidth * i - notationPainterH.height / 2,
            ),
          );
        }
      }
    }

    final points = [
      _offset + Offset(_squareWidth * 0, _squareWidth * 0), // 0
      _offset + Offset(_squareWidth * 0, _squareWidth * 3), // 1
      _offset + Offset(_squareWidth * 0, _squareWidth * 6), // 2
      _offset + Offset(_squareWidth * 1, _squareWidth * 1), // 3
      _offset + Offset(_squareWidth * 1, _squareWidth * 3), // 4
      _offset + Offset(_squareWidth * 1, _squareWidth * 5), // 5
      _offset + Offset(_squareWidth * 2, _squareWidth * 2), // 6
      _offset + Offset(_squareWidth * 2, _squareWidth * 3), // 7
      _offset + Offset(_squareWidth * 2, _squareWidth * 4), // 8
      _offset + Offset(_squareWidth * 3, _squareWidth * 0), // 9
      _offset + Offset(_squareWidth * 3, _squareWidth * 1), // 10
      _offset + Offset(_squareWidth * 3, _squareWidth * 2), // 11
      _offset + Offset(_squareWidth * 3, _squareWidth * 4), // 12
      _offset + Offset(_squareWidth * 3, _squareWidth * 5), // 13
      _offset + Offset(_squareWidth * 3, _squareWidth * 6), // 14
      _offset + Offset(_squareWidth * 4, _squareWidth * 2), // 15
      _offset + Offset(_squareWidth * 4, _squareWidth * 3), // 16
      _offset + Offset(_squareWidth * 4, _squareWidth * 4), // 17
      _offset + Offset(_squareWidth * 5, _squareWidth * 1), // 18
      _offset + Offset(_squareWidth * 5, _squareWidth * 3), // 19
      _offset + Offset(_squareWidth * 5, _squareWidth * 5), // 20
      _offset + Offset(_squareWidth * 6, _squareWidth * 0), // 21
      _offset + Offset(_squareWidth * 6, _squareWidth * 3), // 22
      _offset + Offset(_squareWidth * 6, _squareWidth * 6), // 23
    ];

    // File C
    canvas.drawRect(
      Rect.fromLTWH(_offset.dx, _offset.dy, _squareWidth * 6, _squareWidth * 6),
      paint,
    );

    paint.strokeWidth = LocalDatabaseService.display.boardInnerLineWidth;
    final double bias = paint.strokeWidth / 2;

    // File B
    canvas.drawRect(
      Rect.fromLTWH(
        _offset.dx + _squareWidth * 1,
        _offset.dy + _squareWidth * 1,
        _squareWidth * 4,
        _squareWidth * 4,
      ),
      paint,
    );

    // File A
    canvas.drawRect(
      Rect.fromLTWH(
        _offset.dx + _squareWidth * 2,
        _offset.dy + _squareWidth * 2,
        _squareWidth * 2,
        _squareWidth * 2,
      ),
      paint,
    );

    // Middle horizontal lines (offsetX to Right)
    canvas.drawLine(
      points[1].translate(-bias, 0),
      points[7].translate(bias, 0),
      paint,
    );

    canvas.drawLine(
      points[16].translate(-bias, 0),
      points[22].translate(bias, 0),
      paint,
    );

    // Middle horizontal lines (offsetY to Bottom)
    canvas.drawLine(
      points[9].translate(0, -bias),
      points[11].translate(0, bias),
      paint,
    );

    canvas.drawLine(
      points[12].translate(0, -bias),
      points[14].translate(0, bias),
      paint,
    );

    // Point
    if (LocalDatabaseService.display.pointStyle != null) {
      paint.style = LocalDatabaseService.display.pointStyle!;
      _drawPoint(points, canvas, paint);
    }

    if (LocalDatabaseService.rules.hasDiagonalLines) {
      // offsetY offsetX diagonal line
      canvas.drawLine(points[0], points[6], paint);

      // lower right diagonal line
      canvas.drawLine(points[17], points[23], paint);

      // offsetY right diagonal line
      canvas.drawLine(points[21], points[15], paint);

      // lower offsetX diagonal line
      canvas.drawLine(points[8], points[2], paint);
    }
  }

  static void _drawPoint(List<Offset> points, Canvas canvas, Paint paint) {
    final double pointRadius = LocalDatabaseService.display.pointWidth;

    for (final point in points) {
      canvas.drawCircle(point, pointRadius, paint);
    }
  }
}
