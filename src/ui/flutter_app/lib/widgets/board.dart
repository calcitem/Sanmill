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
import 'package:sanmill/painting/board_painter.dart';
import 'package:sanmill/painting/pieces_painter.dart';
import 'package:sanmill/style/app_theme.dart';

class Board extends StatelessWidget {
  final double width;
  final double height;
  final Function(BuildContext, int) onBoardTap;
  final animationValue;
  final String tag = "[board]";

  Board({
    required this.width,
    required this.onBoardTap,
    required this.animationValue,
  }) : height = width;

  @override
  Widget build(BuildContext context) {
    var padding = AppTheme.boardPadding;

    var coordinates = [];

    for (var file in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
      for (var rank in ['7', '6', '5', '4', '3', '2', '1']) {
        coordinates.add("$file$rank");
      }
    }

    var container = Container(
      margin: EdgeInsets.symmetric(
        vertical: 0,
        horizontal: 0,
      ),
      child: GridView(
        scrollDirection: Axis.horizontal,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
        ),
        children: List.generate(7 * 7, (index) {
          return Center(
            child: Text(
              coordinates[index],
              style: TextStyle(
                fontSize: Config.fontSize,
                color: Config.developerMode ? Colors.red : Colors.transparent,
              ),
            ),
          );
        }),
      ),
    );

    var customPaint = CustomPaint(
      painter: BoardPainter(width: width),
      foregroundPainter: PiecesPainter(
        width: width,
        position: Game.instance.position,
        focusIndex: Game.instance.focusIndex,
        blurIndex: Game.instance.blurIndex,
        animationValue: animationValue,
      ),
      child: container,
    );

    final boardContainer = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.boardBorderRadius),
        color: Color(Config.boardBackgroundColor),
      ),
      child: customPaint,
    );

    return GestureDetector(
      /*
      child: Semantics(
        label: S.of(context).board,
        child: boardContainer,
      ),
      */
      child: boardContainer,
      onTapUp: (d) {
        final gridWidth = (width - padding * 2);
        final squareWidth = gridWidth / 7;
        final dx = d.localPosition.dx;
        final dy = d.localPosition.dy;

        final column = (dx - padding) ~/ squareWidth;
        if (column < 0 || column > 6) {
          print("$tag Tap on column $column (ignored).");
          return;
        }

        final row = (dy - padding) ~/ squareWidth;
        if (row < 0 || row > 6) {
          print("$tag Tap on row $row (ignored).");
          return;
        }

        final index = row * 7 + column;

        print("$tag Tap on ($row, $column) <$index>");

        onBoardTap(context, index);
      },
    );
  }
}
