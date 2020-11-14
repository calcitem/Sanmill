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

import '../board/painter_base.dart';
import '../common/properties.dart';
import '../mill/mill.dart';
import '../mill/position.dart';
import 'board_widget.dart';

class PiecePaintStub {
  final String piece;
  final Offset pos;
  PiecePaintStub({this.piece, this.pos});
}

class PiecesPainter extends PainterBase {
  //
  final Position position;
  final int focusIndex, blurIndex;

  double pieceWidth;

  PiecesPainter({
    @required double width,
    @required this.position,
    this.focusIndex = Move.invalidValue,
    this.blurIndex = Move.invalidValue,
  }) : super(width: width) {
    //
    pieceWidth = squareWidth * 0.9; // 棋子大小
  }

  @override
  void paint(Canvas canvas, Size size) {
    //
    doPaint(
      canvas,
      thePaint,
      position: position,
      gridWidth: gridWidth,
      squareWidth: squareWidth,
      pieceWidth: pieceWidth,
      // 棋子放在线上中央
      offsetX: BoardWidget.padding + squareWidth / 2,
      offsetY: BoardWidget.padding + BoardWidget.digitsHeight + squareWidth / 2,
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
    double squareWidth,
    double pieceWidth,
    double offsetX,
    double offsetY,
    int focusIndex = Move.invalidValue,
    int blurIndex = Move.invalidValue,
  }) {
    //
    final left = offsetX;
    final top = offsetY;

    final shadowPath = Path();
    final piecesToDraw = <PiecePaintStub>[];

    // 在棋盘上画棋子
    for (var row = 0; row < 7; row++) {
      //
      for (var col = 0; col < 7; col++) {
        //
        final piece = position.pieceOnGrid(row * 7 + col); // 初始状态无棋子

        if (piece == Piece.noPiece) continue;

        var pos = Offset(left + squareWidth * col, top + squareWidth * row);

        piecesToDraw.add(PiecePaintStub(piece: piece, pos: pos));

        shadowPath.addOval(
          Rect.fromCenter(center: pos, width: pieceWidth, height: pieceWidth),
        );
      }
    }

    // 棋子下绘制阴影
    canvas.drawShadow(shadowPath, Colors.black, 2, true);

    paint.style = PaintingStyle.fill;

    /*
    final textStyle = TextStyle(
      color: ColorConst.PieceTextColor,
      fontSize: pieceSide * 0.8,
      height: 1.0,
    );
    */

    piecesToDraw.forEach((pps) {
      var pieceRadius = pieceWidth / 2;
      var pieceInnerRadius = pieceRadius * 0.99; // 决定棋子外圈有宽

      // 绘制棋子边界
      paint.color = Piece.isWhite(pps.piece)
          ? Properties.whitePieceBorderColor
          : Properties.blackPieceBorderColor;

      canvas.drawCircle(pps.pos, pieceRadius, paint); // 临时调试用

      // 绘制棋子内部

      // 棋子颜色
      paint.color = Piece.isWhite(pps.piece)
          ? Properties.whitePieceColor
          : Properties.blackPieceColor;
      //paint.color = ColorConst.WhitePieceColor;

      canvas.drawCircle(pps.pos, pieceInnerRadius, paint);
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

    if (focusIndex != Move.invalidValue) {
      //
      final int row = focusIndex ~/ 7, column = focusIndex % 7;

      paint.color = Properties.focusPositionColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        Offset(left + column * squareWidth, top + row * squareWidth),
        pieceWidth / 2,
        paint,
      );
    }

    if (blurIndex != Move.invalidValue) {
      //
      final row = blurIndex ~/ 7, column = blurIndex % 7;

      paint.color = Properties.blurPositionColor;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(left + column * squareWidth, top + row * squareWidth),
        pieceWidth / 2 * 0.8,
        paint,
      );
    }
  }
}
