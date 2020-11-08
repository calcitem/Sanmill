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

import '../common/properties.dart';
import '../game/battle.dart';
import 'board_painter.dart';
import 'pieces_painter.dart';
import 'words_on_board.dart';

class BoardWidget extends StatelessWidget {
  //
  static const padding = 5.0;
  static const digitsHeight = 0.0;

  static const double boardBorderRadius = 5;

  final double width;
  final double height;
  final Function(BuildContext, int) onBoardTap;

  BoardWidget({@required this.width, @required this.onBoardTap})
      : height = width;

  @override
  Widget build(BuildContext context) {
    //
    final boardContainer = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(boardBorderRadius),
        color: Properties.boardBackgroundColor,
      ),
      child: CustomPaint(
        painter: BoardPainter(width: width),
        foregroundPainter: PiecesPainter(
          width: width,
          position: Battle.shared.position,
          focusIndex: Battle.shared.focusIndex,
          blurIndex: Battle.shared.blurIndex,
        ),
        child: Container(
          margin: EdgeInsets.symmetric(
            vertical: padding,
            horizontal: (width - padding * 2) / 6 / 2 +
                padding -
                WordsOnBoard.digitsFontSize / 2,
          ),
          //child: WordsOnBoard(),
        ),
      ),
    );

    return GestureDetector(
      child: boardContainer,
      onTapUp: (d) {
        //
        final gridWidth = (width - padding * 2);
        final squareWidth = gridWidth / 7;

        final dx = d.localPosition.dx, dy = d.localPosition.dy;
        final row = (dy - padding - digitsHeight) ~/ squareWidth;
        final column = (dx - padding) ~/ squareWidth;

        final index = row * 7 + column;

        print("Tap on ($row, $column) <$index>");

        if (row < 0 || row > 6) return;

        if (column < 0 || column > 6) return;

        onBoardTap(context, index);
      },
    );
  }
}
