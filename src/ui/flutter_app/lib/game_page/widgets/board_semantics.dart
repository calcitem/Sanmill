// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_semantics.dart

part of 'game_page.dart';

/// Semantics for the Board
///
/// This Widget only contains [Semantics] nodes to help impaired people interact with the [GameBoard].
class _BoardSemantics extends StatefulWidget {
  const _BoardSemantics();

  @override
  State<_BoardSemantics> createState() => _BoardSemanticsState();
}

class _BoardSemanticsState extends State<_BoardSemantics> {
  @override
  void initState() {
    super.initState();
    GameController().boardSemanticsNotifier.addListener(updateBoardSemantics);
  }

  void updateBoardSemantics() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<String> squareDesc = _buildSquareDescription(context);

    return GridView(
      key: const Key('board_grid_view'),
      scrollDirection: Axis.horizontal,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      children: List<Widget>.generate(
        7 * 7,
        (int index) => Center(
          child: Semantics(
            key: Key('board_square_$index'),
            // Labels include the occupant, coordinate, and current highlight
            // state for assistive technologies.
            label: squareDesc[index],
          ),
        ),
      ),
    );
  }

  /// Builds a list of Strings representing the label of each semantic node.
  List<String> _buildSquareDescription(BuildContext context) {
    final List<String> coordinates = <String>[];
    final List<String> pieceDesc = <String>[];
    final List<String> squareDesc = <String>[];

    const List<int> map = <int>[
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

    const List<int> checkPoints = <int>[
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

    final bool ltr = Directionality.of(context) == TextDirection.ltr;

    for (final String file
        in ltr ? horizontalNotations : horizontalNotations.reversed) {
      for (final String rank in verticalNotations) {
        coordinates.add("${file.toUpperCase()}$rank");
      }
    }

    for (int i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else {
        pieceDesc.add(
          GameController().position.pieceOnGrid(i).pieceName(context),
        );
      }
    }

    squareDesc.clear();
    final int? focusedIndex = GameController().gameInstance.focusIndex;
    final int? removalIndex = GameController().gameInstance.removeIndex;

    for (int i = 0; i < 7 * 7; i++) {
      final int gridIndex = map[i] - 1;
      final String desc = pieceDesc[gridIndex];
      final bool isPoint = checkPoints[gridIndex] == 1;
      final String base =
          (desc == S.of(context).emptyPoint || desc == S.of(context).noPoint)
              ? "${coordinates[i]} ($desc)"
              : "$desc (${coordinates[i]})";

      if (!isPoint) {
        squareDesc.add(base);
        continue;
      }

      final List<String> qualifiers = <String>[];
      if (focusedIndex == gridIndex) {
        qualifiers.add(S.of(context).selected);
      }
      if (removalIndex == gridIndex) {
        qualifiers.add(S.of(context).tipRemove);
      }

      squareDesc.add(qualifiers.isEmpty
          ? base
          : "${qualifiers.join(' ')} $base");
    }

    return squareDesc;
  }

  @override
  void dispose() {
    GameController()
        .boardSemanticsNotifier
        .removeListener(updateBoardSemantics);
    super.dispose();
  }
}
