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

/// Board Tap Callback
///
/// This function gets called once a valid [square] on the board has been tapped.
typedef BoardTapCallback = Future<void> Function(int square);

class _Board extends StatelessWidget {
  final double width;
  final double height;
  final BoardTapCallback onBoardTap;
  final Animation<double> animation;
  static const String _tag = "[board]";

  const _Board({
    required this.width,
    required this.onBoardTap,
    required this.animation,
  }) : height = width;

  @override
  Widget build(BuildContext context) {
    const padding = AppTheme.boardPadding;
    final _prefs = LocalDatabaseService.preferences;

    final customPaint = AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        return CustomPaint(
          painter: BoardPainter(width: width),
          foregroundPainter: PiecesPainter(
            width: width,
            position: controller.position,
            focusIndex: controller.gameInstance.focusIndex,
            blurIndex: controller.gameInstance.blurIndex,
            animationValue: animation.value,
          ),
          child: child,
        );
      },
      child: EnvironmentConfig.devMode || _prefs.screenReaderSupport
          ? const _BoardNotation()
          : null,
    );

    final boardContainer = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.boardBorderRadius),
        color: LocalDatabaseService.colorSettings.boardBackgroundColor,
      ),
      child: customPaint,
    );

    return RepaintBoundary(
      child: GestureDetector(
        child: boardContainer,
        onTapUp: (d) async {
          final gridWidth = width - padding * 2;
          final squareWidth = gridWidth / 7;
          final dx = d.localPosition.dx;
          final dy = d.localPosition.dy;

          final column = (dx - padding) ~/ squareWidth;
          if (column < 0 || column > 6) {
            return logger.v("$_tag Tap on column $column (ignored).");
          }

          final row = (dy - padding) ~/ squareWidth;
          if (row < 0 || row > 6) {
            return logger.v("$_tag Tap on row $row (ignored).");
          }

          final index = row * 7 + column;
          final int? square = indexToSquare[index];

          if (square == null) {
            return logger.v(
              "$_tag Tap not on a square ($row, $column) (ignored).",
            );
          }

          logger.v("$_tag Tap on ($row, $column) <$index>");

          await onBoardTap(square);
        },
      ),
    );
  }
}

class _BoardNotation extends StatelessWidget {
  const _BoardNotation({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final _squareDesc = _buildSquareDescription(context);

    return GridView(
      scrollDirection: Axis.horizontal,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      children: List.generate(
        7 * 7,
        (index) => Center(
          child: Text(
            _squareDesc[index],
            style: const TextStyle(
              color:
                  EnvironmentConfig.devMode ? Colors.red : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  List<String> _buildSquareDescription(BuildContext context) {
    final List<String> coordinates = [];
    final List<String> pieceDesc = [];
    final List<String> squareDesc = [];

    const map = [
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

    const checkPoints = [
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

    const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    const ranks = ['7', '6', '5', '4', '3', '2', '1'];
    final ltr = Directionality.of(context) == TextDirection.ltr;

    for (final file in ltr ? files : files.reversed) {
      for (final rank in ranks) {
        coordinates.add("$file$rank");
      }
    }

    for (var i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else {
        pieceDesc.add(controller.position.pieceOnGrid(i).pieceName(context));
      }
    }

    squareDesc.clear();

    for (var i = 0; i < 7 * 7; i++) {
      final desc = pieceDesc[map[i] - 1];
      if (desc == S.of(context).emptyPoint) {
        squareDesc.add("${coordinates[i]}: $desc");
      } else {
        squareDesc.add("$desc: ${coordinates[i]}");
      }
    }

    return squareDesc;
  }
}
