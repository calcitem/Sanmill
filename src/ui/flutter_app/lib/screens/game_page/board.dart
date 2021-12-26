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

part of './game_page.dart';

/// Game Board
///
/// The board the game is played on. This widget will also handle the input from the user.
class _Board extends StatefulWidget {
  static const String _tag = "[board]";

  const _Board({Key? key}) : super(key: key);

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: LocalDatabaseService.display.animationDuration.toInt(),
      ),
    );

    // sqrt(1.618) = 1.272
    _animation = Tween(begin: 1.27, end: 1.0).animate(_animationController);
  }

  @override
  Widget build(BuildContext context) {
    final tapHandler = TapHandler(
      animationController: _animationController,
      context: context,
    );

    final customPaint = AnimatedBuilder(
      animation: _animation,
      builder: (_, child) {
        return CustomPaint(
          painter: BoardPainter(),
          foregroundPainter: PiecesPainter(
            focusIndex: MillController().gameInstance.focusIndex,
            blurIndex: MillController().gameInstance.blurIndex,
            animationValue: _animation.value,
          ),
          child: child,
        );
      },
      child: LocalDatabaseService.preferences.screenReaderSupport
          ? const _BoardSemantics()
          : null,
    );

    return LayoutBuilder(
      builder: (context, constrains) {
        final dimension = constrains.maxWidth;
        const padding = AppTheme.boardPadding;

        return SizedBox.square(
          dimension: dimension,
          child: GestureDetector(
            child: customPaint,
            onTapUp: (d) async {
              final gridWidth = dimension - padding * 2;
              final squareWidth = gridWidth / 7;
              // TODO: [Leptopoda] directly store the offset so we can work with it while painting
              final dx = d.localPosition.dx;
              final dy = d.localPosition.dy;

              final column = (dx - padding) ~/ squareWidth;
              if (column < 0 || column > 6) {
                return logger
                    .v("${_Board._tag} Tap on column $column (ignored).");
              }

              final row = (dy - padding) ~/ squareWidth;
              if (row < 0 || row > 6) {
                return logger.v("${_Board._tag} Tap on row $row (ignored).");
              }

              final index = row * 7 + column;
              final int? square = indexToSquare[index];

              if (square == null) {
                return logger.v(
                  "${_Board._tag} Tap not on a square ($row, $column) (ignored).",
                );
              }

              logger.v("${_Board._tag} Tap on ($row, $column) <$index>");

              await tapHandler.onBoardTap(square);
            },
          ),
        );
      },
    );
  }
}

/// Semantics for the Board
///
/// This Widget only contains [Semantics] nodes to help impaired people interact with the [_Board].
class _BoardSemantics extends StatelessWidget {
  const _BoardSemantics({Key? key}) : super(key: key);

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
          child: Semantics(
            // TODO: [Calcitem] add more descriptive informations
            label: _squareDesc[index],
          ),
        ),
      ),
    );
  }

  /// Builds a list of Strings representing the label of each semantic node.
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

    final ltr = Directionality.of(context) == TextDirection.ltr;

    for (final file in ltr ? verticalNotations : verticalNotations.reversed) {
      for (final rank in horizontalNotations) {
        coordinates.add("$file$rank");
      }
    }

    for (var i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else {
        pieceDesc.add(
          MillController().position.pieceOnGrid(i).pieceName(context),
        );
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
