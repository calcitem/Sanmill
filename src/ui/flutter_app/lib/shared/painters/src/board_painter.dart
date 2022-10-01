// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../painters.dart';

/// Custom Board Painter
///
/// Painter to draw the Board. The pieces are drawn by [PiecePainter].
/// It asserts the Canvas to be a square.
class BoardPainter extends CustomPainter {
  BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    final position = MillController().position;
    final colorSettings = DB().colorSettings;
    final paint = Paint();

    paint.strokeWidth = DB().displaySettings.boardBorderLineWidth;
    paint.color = Color.lerp(
      colorSettings.boardBackgroundColor,
      colorSettings.boardLineColor,
      colorSettings.boardLineColor.opacity,
    )!
        .withOpacity(1);
    paint.style = PaintingStyle.stroke;

    _drawBackground(canvas, size);

    if (DB().displaySettings.isPieceCountInHandShown &&
        position.phase == Phase.placing) {
      _drawPieceCount(position, canvas, size);
    }

    if (DB().displaySettings.isNotationsShown || EnvironmentConfig.devMode) {
      _drawNotations(canvas, size);
    }

    final List<Offset> offset =
        points.map((e) => offsetFromPoint(e, size)).toList();

    _drawLines(offset, canvas, paint);

    // Point
    if (DB().displaySettings.pointStyle != null) {
      _drawPoints(offset, canvas, paint);
    }
  }

  /// Draws the background of the Board.
  static void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = DB().colorSettings.boardBackgroundColor;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset.zero, Offset(size.width, size.height)),
        const Radius.circular(AppTheme.boardBorderRadius),
      ),
      paint,
    );
  }

  /// Draws the lines of the Board.
  static void _drawLines(List<Offset> offset, Canvas canvas, Paint paint) {
    // File C
    canvas.drawRect(Rect.fromPoints(offset[0], offset[23]), paint);

    paint.strokeWidth = DB().displaySettings.boardInnerLineWidth;

    final path = Path();
    // File B
    path.addRect(Rect.fromPoints(offset[3], offset[20]));

    // File A
    path.addRect(Rect.fromPoints(offset[6], offset[17]));

    // Middle horizontal lines (offsetX to Right)
    path.addLine(offset[1], offset[7]);
    path.addLine(offset[16], offset[22]);

    // Middle horizontal lines (offsetY to Bottom)
    path.addLine(offset[9], offset[11]);
    path.addLine(offset[12], offset[14]);

    if (DB().ruleSettings.hasDiagonalLines) {
      // offsetY offsetX diagonal line
      path.addLine(offset[0], offset[6]);

      // Lower right diagonal line
      path.addLine(offset[17], offset[23]);

      // offsetY right diagonal line
      path.addLine(offset[21], offset[15]);

      // Lower offsetX diagonal line
      path.addLine(offset[8], offset[2]);
    }

    canvas.drawPath(path, paint);
  }

  /// Draws the points representing each field.
  static void _drawPoints(List<Offset> points, Canvas canvas, Paint paint) {
    paint.style = DB().displaySettings.pointStyle!;
    final double pointRadius = DB().displaySettings.pointWidth;

    for (final point in points) {
      canvas.drawCircle(point, pointRadius, paint);
    }
  }

  /// Draws the [position.pieceOnBoardCount] in the middle of the Board.
  static void _drawPieceCount(Position position, Canvas canvas, Size size) {
    final int pieceInHandCount;
    if (position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      pieceInHandCount = DB().ruleSettings.piecesCount;
    } else {
      pieceInHandCount = position.pieceInHandCount[PieceColor.black]!;
    }

    final TextSpan textSpan = TextSpan(
      style: TextStyle(
        fontSize: 48,
        color: DB().colorSettings.boardLineColor,
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
      size.center(
        -Offset(textPainter.width, textPainter.height) / 2,
      ),
    );
  }

  /// Draws the numbering of the fields displayed at the side.
  static void _drawNotations(Canvas canvas, Size size) {
    for (int i = 0; i < verticalNotations.length; i++) {
      final TextSpan notationSpanV = TextSpan(
        style: AppTheme.notationTextStyle, // TODO
        text: verticalNotations[i],
      );

      final TextSpan notationSpanH = TextSpan(
        style: AppTheme.notationTextStyle, // TODO
        text: horizontalNotations[i],
      );

      final TextPainter notationPainterH = TextPainter(
        text: notationSpanV,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      final TextPainter notationPainterV = TextPainter(
        text: notationSpanH,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      notationPainterH.layout();
      notationPainterV.layout();

      final horizontalOffset =
          size.height - (boardMargin + notationPainterH.height) / 2;
      final verticalOffset = (boardMargin - notationPainterV.width) / 2;

      // Show notations "a b c d e f" on board
      notationPainterH.paint(
        canvas,
        Offset(
          offsetFromInt(i, size) - notationPainterH.width / 2,
          horizontalOffset,
        ),
      );

      // Show notations "1 2 3 4 5 6 7" on board
      notationPainterV.paint(
        canvas,
        Offset(
          verticalOffset,
          offsetFromInt(i, size) - notationPainterV.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
