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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/l10n/resources.dart';
import 'package:sanmill/mill/game.dart';
import 'package:sanmill/mill/types.dart';
import 'package:sanmill/painting/board_painter.dart';
import 'package:sanmill/painting/pieces_painter.dart';
import 'package:sanmill/style/app_theme.dart';

class Board extends StatelessWidget {
  final double width;
  final double height;
  final Function(BuildContext, int) onBoardTap;
  final animationValue;
  List<String> squareDesc = [];
  final String tag = "[board]";

  Board({
    required this.width,
    required this.onBoardTap,
    required this.animationValue,
  }) : height = width;

  @override
  Widget build(BuildContext context) {
    var padding = AppTheme.boardPadding;

    buildSquareDescription(context);

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
              squareDesc[index],
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
          debugPrint("$tag Tap on column $column (ignored).");
          return;
        }

        final row = (dy - padding) ~/ squareWidth;
        if (row < 0 || row > 6) {
          debugPrint("$tag Tap on row $row (ignored).");
          return;
        }

        final index = row * 7 + column;

        debugPrint("$tag Tap on ($row, $column) <$index>");

        onBoardTap(context, index);
      },
    );
  }

  void buildSquareDescription(BuildContext context) {
    List<String> coordinates = [];
    List<String> pieceDesc = [];

    var map = [
      /* 1 */
      1,
      8,
      15,
      22,
      29,
      36,
      43,
      /* 2 */
      2,
      9,
      16,
      23,
      30,
      37,
      44,
      /* 3 */
      3,
      10,
      17,
      24,
      31,
      38,
      45,
      /* 4 */
      4,
      11,
      18,
      25,
      32,
      39,
      46,
      /* 5 */
      5,
      12,
      19,
      26,
      33,
      40,
      47,
      /* 6 */
      6,
      13,
      20,
      27,
      34,
      41,
      48,
      /* 7 */
      7,
      14,
      21,
      28,
      35,
      42,
      49
    ];

    var checkPoints = [
      /* 1 */
      1,
      0,
      0,
      1,
      0,
      0,
      1,
      /* 2 */
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      /* 3 */
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      /* 4 */
      1,
      1,
      1,
      0,
      1,
      1,
      1,
      /* 5 */
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      /* 6 */
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      /* 7 */
      1,
      0,
      0,
      1,
      0,
      0,
      1
    ];

    bool ltr = getBidirectionality(context) == Bidirectionality.leftToRight;

    if (ltr) {
      for (var file in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
        for (var rank in ['7', '6', '5', '4', '3', '2', '1']) {
          coordinates.add("$file$rank");
        }
      }
    } else {
      for (var file in ['g', 'f', 'e', 'd', 'c', 'b', 'a']) {
        for (var rank in ['7', '6', '5', '4', '3', '2', '1']) {
          coordinates.add("$file$rank");
        }
      }
    }

    for (var i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else if (Game.instance.position.pieceOnGrid(i) == PieceColor.white) {
        pieceDesc.add(S.of(context).whitePiece);
      } else if (Game.instance.position.pieceOnGrid(i) == PieceColor.black) {
        pieceDesc.add(S.of(context).blackPiece);
      } else if (Game.instance.position.pieceOnGrid(i) == PieceColor.ban) {
        pieceDesc.add(S.of(context).banPoint);
      } else if (Game.instance.position.pieceOnGrid(i) == PieceColor.none) {
        pieceDesc.add(S.of(context).emptyPoint);
      }
    }

    squareDesc.clear();

    for (var i = 0; i < 7 * 7; i++) {
      var desc = pieceDesc[map[i] - 1];
      if (desc == S.of(context).emptyPoint) {
        squareDesc.add(coordinates[i] + ": " + desc);
      } else {
        squareDesc.add(desc + ": " + coordinates[i]);
      }
    }
  }
}
