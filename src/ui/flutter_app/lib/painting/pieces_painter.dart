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
import 'package:sanmill/mill/position.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/style/app_theme.dart';

import 'painter_base.dart';

class PiecePaintParam {
  // TODO: null-safety
  final String? piece;
  final Offset? pos;
  final bool? animated;
  PiecePaintParam({this.piece, this.pos, this.animated});
}

class PiecesPainter extends PiecesBasePainter {
  final Position? position;
  final int? focusIndex, blurIndex;
  final animationValue;

  // TODO: null-safety
  double? pieceWidth = 0.0;
  double? animatedPieceWidth = 0.0;

  PiecesPainter({
    required double width,
    required this.position,
    this.focusIndex = invalidIndex,
    this.blurIndex = invalidIndex,
    required this.animationValue,
  }) : super(width: width) {
    pieceWidth = squareWidth * Config.pieceWidth;
    animatedPieceWidth = squareWidth * Config.pieceWidth * animationValue;
  }

  @override
  void paint(Canvas canvas, Size size) {
    doPaint(
      canvas,
      thePaint,
      position: position,
      gridWidth: gridWidth,
      squareWidth: squareWidth,
      pieceWidth: pieceWidth,
      animatedPieceWidth: animatedPieceWidth,
      offsetX: AppTheme.boardPadding + squareWidth / 2,
      offsetY: AppTheme.boardPadding + squareWidth / 2,
      focusIndex: focusIndex,
      blurIndex: blurIndex,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

  static doPaint(
    Canvas canvas,
    Paint paint, {
    Position? position,
    double? gridWidth,
    double? squareWidth,
    double? pieceWidth,
    double? animatedPieceWidth,
    double? offsetX,
    double? offsetY,
    int? focusIndex = invalidIndex,
    int? blurIndex = invalidIndex,
  }) {
    //
    final left = offsetX;
    final top = offsetY;

    final shadowPath = Path();
    final piecesToDraw = <PiecePaintParam>[];

    // TODO: null-safety
    Color? blurPositionColor;
    Color focusPositionColor;

    // Draw pieces on board
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;
        final piece = position!.pieceOnGrid(index); // No Pieces when initial

        if (piece == Piece.noPiece) continue;

        var pos = Offset(left! + squareWidth! * col, top! + squareWidth * row);
        var animated = (focusIndex == index);

        piecesToDraw
            .add(PiecePaintParam(piece: piece, pos: pos, animated: animated));

        shadowPath.addOval(
          Rect.fromCenter(center: pos, width: pieceWidth!, height: pieceWidth),
        );
      }
    }

    // Draw shadow of piece
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
      var pieceRadius = pieceWidth! / 2;
      var pieceInnerRadius = pieceRadius * 0.99;

      var animatedPieceRadius = animatedPieceWidth! / 2;
      var animatedPieceInnerRadius = animatedPieceRadius * 0.99;

      // Draw Border of Piece
      switch (pps.piece) {
        case Piece.whiteStone:
          paint.color = AppTheme.whitePieceBorderColor;
          canvas.drawCircle(
            pps.pos!,
            pps.animated! ? animatedPieceRadius : pieceRadius,
            paint,
          );
          paint.color = Color(Config.whitePieceColor);
          canvas.drawCircle(
            pps.pos!,
            pps.animated! ? animatedPieceInnerRadius : pieceInnerRadius,
            paint,
          );
          blurPositionColor = Color(Config.whitePieceColor).withOpacity(0.1);
          break;
        case Piece.blackStone:
          paint.color = AppTheme.blackPieceBorderColor;
          canvas.drawCircle(
            pps.pos!,
            pps.animated! ? animatedPieceRadius : pieceRadius,
            paint,
          );
          paint.color = Color(Config.blackPieceColor);
          canvas.drawCircle(
            pps.pos!,
            pps.animated! ? animatedPieceInnerRadius : pieceInnerRadius,
            paint,
          );
          blurPositionColor = Color(Config.blackPieceColor).withOpacity(0.1);
          break;
        case Piece.ban:
          //print("pps.piece is Ban");
          break;
        default:
          assert(false);
          break;
      }
    });

    // draw focus and blur position

    if (focusIndex != invalidIndex) {
      final int row = focusIndex! ~/ 7, column = focusIndex % 7;

      focusPositionColor = Color.fromARGB(
              (Color(Config.whitePieceColor).alpha +
                      Color(Config.blackPieceColor).alpha) ~/
                  2,
              (Color(Config.whitePieceColor).red +
                      Color(Config.blackPieceColor).red) ~/
                  2,
              (Color(Config.whitePieceColor).green +
                      Color(Config.blackPieceColor).green) ~/
                  2,
              (Color(Config.whitePieceColor).blue +
                      Color(Config.blackPieceColor).blue) ~/
                  2)
          .withOpacity(0.5);

      paint.color = focusPositionColor;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;

      canvas.drawCircle(
        Offset(left! + column * squareWidth!, top! + row * squareWidth),
        animatedPieceWidth! / 2,
        paint,
      );
    }

    if (blurIndex != invalidIndex) {
      final row = blurIndex! ~/ 7, column = blurIndex % 7;

      paint.color = blurPositionColor!;
      paint.style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(left! + column * squareWidth!, top! + row * squareWidth),
        animatedPieceWidth! / 2 * 0.8,
        paint,
      );
    }
  }
}
