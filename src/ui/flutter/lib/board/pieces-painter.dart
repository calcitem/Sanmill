import 'package:flutter/material.dart';
import '../mill/mill-base.dart';
import '../common/color-consts.dart';
import '../board/painter-base.dart';
import '../mill/position.dart';
import 'board-widget.dart';

class PiecePaintStub {
  final String piece;
  final Offset pos;
  PiecePaintStub({this.piece, this.pos});
}

class PiecesPainter extends PainterBase {
  //
  final Position position;
  final int focusIndex, blurIndex;

  double pieceSide;

  PiecesPainter({
    @required double width,
    @required this.position,
    this.focusIndex = Move.InvalidIndex,
    this.blurIndex = Move.InvalidIndex,
  }) : super(width: width) {
    //
    pieceSide = squareSide * 0.9; // 棋子大小
  }

  @override
  void paint(Canvas canvas, Size size) {
    //
    doPaint(
      canvas,
      thePaint,
      position: position,
      gridWidth: gridWidth,
      squareSide: squareSide,
      pieceSide: pieceSide,
      // 棋子放在线上中央
      offsetX: BoardWidget.Padding + squareSide / 2,
      offsetY: BoardWidget.Padding + BoardWidget.DigitsHeight + squareSide / 2,
      focusIndex: focusIndex,
      blurIndex: blurIndex,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    // 每次重建 Painter 时都要重画
    return true;
  }

  static doPaint(
    Canvas canvas,
    Paint paint, {
    Position position,
    double gridWidth,
    double squareSide,
    double pieceSide,
    double offsetX,
    double offsetY,
    int focusIndex = Move.InvalidIndex,
    int blurIndex = Move.InvalidIndex,
  }) {
    //
    final left = offsetX, top = offsetY;

    final shadowPath = Path();
    final piecesToDraw = <PiecePaintStub>[];

    // 在棋盘上画棋子
    for (var row = 0; row < 7; row++) {
      //
      for (var column = 0; column < 7; column++) {
        //
        //final piece = position.pieceAt(row * 7 + column);
        final piece = position.pieceAt(row * 7 + column); // 改为9则全空

        if (piece == Piece.Empty) continue;

        var pos = Offset(left + squareSide * column, top + squareSide * row);

        piecesToDraw.add(PiecePaintStub(piece: piece, pos: pos));

        shadowPath.addOval(
          Rect.fromCenter(center: pos, width: pieceSide, height: pieceSide),
        );
      }
    }

    // 棋子下绘制阴影
    canvas.drawShadow(shadowPath, Colors.black, 2, true);

    paint.style = PaintingStyle.fill;

    /*
    final textStyle = TextStyle(
      color: ColorConsts.PieceTextColor,
      fontSize: pieceSide * 0.8,
      height: 1.0,
    );
    */

    piecesToDraw.forEach((pps) {
      //
      paint.color = Piece.isWhite(pps.piece)
          ? ColorConsts.WhitePieceBorderColor
          : ColorConsts.BlackPieceBorderColor;

      canvas.drawCircle(pps.pos, pieceSide / 2, paint); // 临时调试用

      // 棋子颜色
      paint.color = Piece.isWhite(pps.piece)
          ? ColorConsts.WhitePieceColor
          : ColorConsts.BlackPieceColor;
      //paint.color = ColorConsts.WhitePieceColor;

      canvas.drawCircle(pps.pos, pieceSide * 0.8 / 2, paint); // 决定棋子外圈有宽
      /*
      final textSpan = TextSpan(text: Piece.Names[pps.piece], style: textStyle);

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();


      final metric = textPainter.computeLineMetrics()[0];
      final textSize = textPainter.size;

      // 从顶上算，文字的 Baseline 在 2/3 高度线上
      final textOffset = pps.pos - Offset(textSize.width / 2, metric.baseline - textSize.height / 3);

      textPainter.paint(canvas, textOffset);
      */
    });

    // draw focus and blur position

    if (focusIndex != Move.InvalidIndex) {
      //
      final int row = focusIndex ~/ 7, column = focusIndex % 7;

      paint.color = ColorConsts.FocusPosition;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        Offset(left + column * squareSide, top + row * squareSide),
        pieceSide / 2,
        paint,
      );
    }

    if (blurIndex != Move.InvalidIndex) {
      //
      final row = blurIndex ~/ 7, column = blurIndex % 7;

      paint.color = ColorConsts.BlurPosition;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(left + column * squareSide, top + row * squareSide),
        pieceSide / 2 * 0.8,
        paint,
      );
    }
  }
}
