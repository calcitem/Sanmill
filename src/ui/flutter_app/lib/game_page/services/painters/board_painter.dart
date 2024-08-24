// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

part of '../../../game_page/services/painters/painters.dart';

/// Custom Board Painter
///
/// Painter to draw the Board. The pieces are drawn by [PiecePainter].
/// It asserts the Canvas to be a square.
class BoardPainter extends CustomPainter {
  BoardPainter(this.context);

  final BuildContext context;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);

    final Position position = GameController().position;
    final ColorSettings colorSettings = DB().colorSettings;
    final double boardBorderLineWidth =
        DB().displaySettings.boardBorderLineWidth;
    final Paint paint = _createPaint(colorSettings, boardBorderLineWidth, size);

    _drawBackground(canvas, size);
    _drawOptionalElements(canvas, size, position);

    final List<Offset> offset =
        points.map((Offset e) => offsetFromPoint(e, size)).toList();
    _drawLines(offset, canvas, paint, size);
    _drawPoints(offset, canvas, paint);
    _drawMillLines(offset, canvas, paint, size);
  }

  Paint _createPaint(
      ColorSettings colorSettings, double boardBorderLineWidth, Size size) {
    final Paint paint = Paint();
    paint.strokeWidth =
        boardBorderLineWidth * (isTablet(context) ? size.width ~/ 256 : 1);
    paint.color = Color.lerp(
      colorSettings.boardBackgroundColor,
      colorSettings.boardLineColor,
      colorSettings.boardLineColor.opacity,
    )!
        .withOpacity(1);
    paint.style = PaintingStyle.stroke;
    return paint;
  }

  void _drawOptionalElements(Canvas canvas, Size size, Position position) {
    if (_shouldDrawPieceCount(position)) {
      _drawPieceCount(position, canvas, size);
    }

    if (_shouldDrawNotations()) {
      _drawNotations(canvas, size);
    }
  }

  bool _shouldDrawPieceCount(Position position) {
    return DB().displaySettings.isPieceCountInHandShown &&
        GameController().gameInstance.gameMode != GameMode.setupPosition &&
        position.phase == Phase.placing;
  }

  bool _shouldDrawNotations() {
    return DB().displaySettings.isNotationsShown || EnvironmentConfig.devMode;
  }

  static void _drawBackground(Canvas canvas, Size size) {
    final Paint paint = Paint();
    paint.color = DB().colorSettings.boardBackgroundColor;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset.zero, Offset(size.width, size.height)),
        const Radius.circular(AppTheme.boardBorderRadius),
      ),
      paint,
    );
  }

  void _drawLines(List<Offset> offset, Canvas canvas, Paint paint, Size size) {
    _drawOuterRectangle(canvas, offset, paint);

    final double boardInnerLineWidth = DB().displaySettings.boardInnerLineWidth;
    paint.strokeWidth =
        boardInnerLineWidth * (isTablet(context) ? size.width ~/ 256 : 1);

    final Path path = _createLinePath(offset);
    canvas.drawPath(path, paint);
  }

  void _drawOuterRectangle(Canvas canvas, List<Offset> offset, Paint paint) {
    canvas.drawRect(Rect.fromPoints(offset[0], offset[23]), paint);
  }

  Path _createLinePath(List<Offset> offset) {
    final Path path = Path();
    path.addRect(Rect.fromPoints(offset[3], offset[20])); // File B
    path.addRect(Rect.fromPoints(offset[6], offset[17])); // File A
    _addMiddleHorizontalLines(path, offset);
    _addDiagonalLinesIfNeeded(path, offset);
    return path;
  }

  void _addMiddleHorizontalLines(Path path, List<Offset> offset) {
    path.addLine(offset[1], offset[7]);
    path.addLine(offset[16], offset[22]);
    path.addLine(offset[9], offset[11]);
    path.addLine(offset[12], offset[14]);
  }

  void _addDiagonalLinesIfNeeded(Path path, List<Offset> offset) {
    if (DB().ruleSettings.hasDiagonalLines) {
      path.addLine(offset[0], offset[6]);
      path.addLine(offset[17], offset[23]);
      path.addLine(offset[21], offset[15]);
      path.addLine(offset[8], offset[2]);
    }
  }

  void _drawMillLines(
      List<Offset> offset, Canvas canvas, Paint paint, Size size) {
    final double boardInnerLineWidth = DB().displaySettings.boardInnerLineWidth;
    paint.strokeWidth =
        boardInnerLineWidth * (isTablet(context) ? size.width ~/ 256 : 1) + 1;

    if (!DB().ruleSettings.oneTimeUseMill) {
      return;
    }

    final Map<PieceColor, List<List<int>>> formedMills =
        GameController().position.formedMills;

    final Color mixedColor = Color.lerp(
      DB().colorSettings.whitePieceColor,
      DB().colorSettings.blackPieceColor,
      0.5,
    )!;

    // Draw Mills with unique or mixed colors
    void drawMills(
        PieceColor color, List<List<int>> mills, Color defaultColor) {
      for (final List<int> mill in mills) {
        final Path path = Path();
        path.addLine(
            pointFromSquare(mill[0], size), pointFromSquare(mill[1], size));
        path.addLine(
            pointFromSquare(mill[1], size), pointFromSquare(mill[2], size));
        path.addLine(
            pointFromSquare(mill[2], size), pointFromSquare(mill[0], size));

        // Check if this mill exists in the opposite color mills
        final bool isShared = formedMills[color == PieceColor.white
                ? PieceColor.black
                : PieceColor.white]!
            .any((List<int> otherMill) => listEquals(mill, otherMill));

        paint.color = isShared ? mixedColor : defaultColor;

        if (paint.color == DB().colorSettings.boardBackgroundColor ||
            paint.color == DB().colorSettings.boardLineColor) {
          if (defaultColor == DB().colorSettings.whitePieceColor) {
            paint.color = Colors.red;
          } else {
            paint.color = Colors.blue;
          }
        }

        canvas.drawPath(path, paint);
      }
    }

    // Draw White and Black Mills, possibly with mixed color
    drawMills(PieceColor.white, formedMills[PieceColor.white]!,
        DB().colorSettings.whitePieceColor);
    drawMills(PieceColor.black, formedMills[PieceColor.black]!,
        DB().colorSettings.blackPieceColor);
  }

  static void _drawPoints(List<Offset> points, Canvas canvas, Paint paint) {
    final PaintingStyle? style = _getPointPaintingStyle();

    if (style == null) {
      return;
    }

    paint.style = style;

    final double pointRadius = DB().displaySettings.pointWidth;
    for (final Offset point in points) {
      canvas.drawCircle(point, pointRadius, paint);
    }
  }

  static PaintingStyle? _getPointPaintingStyle() {
    switch (DB().displaySettings.pointPaintingStyle) {
      case PointPaintingStyle.fill:
        return PaintingStyle.fill;
      case PointPaintingStyle.stroke:
        return PaintingStyle.stroke;
      case PointPaintingStyle.none:
        return null;
    }
  }

  static void _drawPieceCount(Position position, Canvas canvas, Size size) {
    final int pieceInHandCount = _calculatePieceInHandCount(position);

    final TextSpan textSpan = TextSpan(
      style: TextStyle(fontSize: 48, color: DB().colorSettings.boardLineColor),
      text: pieceInHandCount.toString(),
    );

    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas,
        size.center(-Offset(textPainter.width, textPainter.height) / 2));
  }

  static int _calculatePieceInHandCount(Position position) {
    if (position.pieceOnBoardCount[PieceColor.white] == 0 &&
        position.pieceOnBoardCount[PieceColor.black] == 0) {
      return DB().ruleSettings.piecesCount;
    } else {
      return position.pieceInHandCount[position.sideToMove]!;
    }
  }

  static void _drawNotations(Canvas canvas, Size size) {
    for (int i = 0; i < verticalNotations.length; i++) {
      _drawVerticalNotation(canvas, size, i);
      _drawHorizontalNotation(canvas, size, i);
    }
  }

  static void _drawVerticalNotation(Canvas canvas, Size size, int index) {
    final TextStyle notationTextStyle = TextStyle(
      color: DB().colorSettings.boardLineColor,
      fontSize: AppTheme.textScaler.scale(20),
    );

    final TextSpan notationSpan = TextSpan(
      style: notationTextStyle,
      text: verticalNotations[index],
    );

    final TextPainter notationPainter = TextPainter(
      text: notationSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    notationPainter.layout();
    final double offset = (boardMargin - notationPainter.width) / 2;
    notationPainter.paint(
        canvas,
        Offset(
            offset, offsetFromInt(index, size) - notationPainter.height / 2));
  }

  static void _drawHorizontalNotation(Canvas canvas, Size size, int index) {
    final TextStyle notationTextStyle = TextStyle(
      color: DB().colorSettings.boardLineColor,
      fontSize: AppTheme.textScaler.scale(20),
    );

    final TextSpan notationSpan = TextSpan(
      style: notationTextStyle,
      text: DB().generalSettings.screenReaderSupport
          ? horizontalNotations[index].toUpperCase()
          : horizontalNotations[index],
    );

    final TextPainter notationPainter = TextPainter(
      text: notationSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    notationPainter.layout();
    final double offset =
        size.height - (boardMargin + notationPainter.height) / 2;
    notationPainter.paint(canvas,
        Offset(offsetFromInt(index, size) - notationPainter.width / 2, offset));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
