// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// board_semantics.dart

part of 'game_page.dart';

/// Semantics for the Board
///
/// This Widget only contains [Semantics] nodes to help impaired people interact with the [GameBoard].
class _BoardSemantics extends StatefulWidget {
  const _BoardSemantics({required this.onSquareTap});

  final Future<void> Function(int square) onSquareTap;

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
      children: List<Widget>.generate(7 * 7, (int index) {
        final int gridIndex = _semanticIndexToGridIndex[index] - 1;
        final int? square =
            MillBoardCoordinateMaps.gridIndexToSquare[gridIndex];
        return Center(
          child: Semantics(
            key: Key('board_square_$index'),
            label: squareDesc[index],
            button: square != null,
            enabled: square != null,
            onTap: square == null
                ? null
                : () => unawaited(widget.onSquareTap(square)),
          ),
        );
      }),
    );
  }

  static const List<int> _semanticIndexToGridIndex = <int>[
    1,
    8,
    15,
    22,
    29,
    36,
    43,
    2,
    9,
    16,
    23,
    30,
    37,
    44,
    3,
    10,
    17,
    24,
    31,
    38,
    45,
    4,
    11,
    18,
    25,
    32,
    39,
    46,
    5,
    12,
    19,
    26,
    33,
    40,
    47,
    6,
    13,
    20,
    27,
    34,
    41,
    48,
    7,
    14,
    21,
    28,
    35,
    42,
    49,
  ];

  /// Builds the same coordinate and occupancy descriptions as `master`.
  List<String> _buildSquareDescription(BuildContext context) {
    final List<String> coordinates = <String>[];
    final List<String> pieceDesc = <String>[];
    final List<String> squareDesc = <String>[];

    const List<int> checkPoints = <int>[
      1,
      0,
      0,
      1,
      0,
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      1,
      1,
      1,
      0,
      1,
      1,
      1,
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      0,
      1,
      0,
      0,
      1,
    ];

    final bool ltr = Directionality.of(context) == TextDirection.ltr;
    for (final String file
        in ltr ? horizontalNotations : horizontalNotations.reversed) {
      for (final String rank in verticalNotations) {
        coordinates.add('${file.toUpperCase()}$rank');
      }
    }

    final MillBoardView boardView = GameController().activeBoardView;
    for (int i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else {
        pieceDesc.add(boardView.pieceOnGrid(i).pieceName(context));
      }
    }

    for (int i = 0; i < 7 * 7; i++) {
      final String desc = pieceDesc[_semanticIndexToGridIndex[i] - 1];
      if (desc == S.of(context).emptyPoint) {
        squareDesc.add('${coordinates[i]}: $desc');
      } else {
        squareDesc.add('$desc: ${coordinates[i]}');
      }
    }

    return squareDesc;
  }

  @override
  void dispose() {
    GameController().boardSemanticsNotifier.removeListener(
      updateBoardSemantics,
    );
    super.dispose();
  }
}
