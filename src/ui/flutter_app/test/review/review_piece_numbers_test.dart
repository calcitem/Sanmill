// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_piece_numbers.dart';

void main() {
  test('rebuilds piece numbers through placement, movement, and removal', () {
    final Map<int, int> numbers = ReviewPieceNumbers.forTurn(
      <ReviewTurnBoundary>[
        _turn(0, 'a7'),
        _turn(1, 'b6'),
        _turn(2, 'a7-a4xb6'),
      ],
      2,
    );

    expect(numbers, <int, int>{
      MillBoardCoordinateMaps.notationToNode('a4'): 1,
    });
  });

  test('stops at the selected complete turn', () {
    final Map<int, int> numbers = ReviewPieceNumbers.forTurn(
      <ReviewTurnBoundary>[
        _turn(0, 'a7'),
        _turn(1, 'b6'),
        _turn(2, 'a7-a4xb6'),
      ],
      1,
    );

    expect(numbers, <int, int>{
      MillBoardCoordinateMaps.notationToNode('a7'): 1,
      MillBoardCoordinateMaps.notationToNode('b6'): 2,
    });
  });
}

ReviewTurnBoundary _turn(int groupIndex, String san) => ReviewTurnBoundary(
  groupIndex: groupIndex,
  startAtomicIndex: groupIndex,
  endAtomicIndex: groupIndex,
  san: san,
  anchorMove: san,
  side: groupIndex.isEven ? ReviewSide.white : ReviewSide.black,
  sourceNags: const <int>[],
  boardLayout: '********/********/********',
);
