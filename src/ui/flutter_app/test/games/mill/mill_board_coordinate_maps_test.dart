// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';

void main() {
  group('MillBoardCoordinateMaps', () {
    test('square/grid maps are inverse over all 24 points', () {
      expect(MillBoardCoordinateMaps.squareToGridIndex, hasLength(24));
      expect(MillBoardCoordinateMaps.gridIndexToSquare, hasLength(24));

      for (final MapEntry<int, int> entry
          in MillBoardCoordinateMaps.squareToGridIndex.entries) {
        expect(
          MillBoardCoordinateMaps.gridIndexToSquare[entry.value],
          entry.key,
        );
      }
    });

    test('notation maps are inverse over all 24 points', () {
      expect(MillBoardCoordinateMaps.squareToNotation, hasLength(24));
      expect(MillBoardCoordinateMaps.notationToSquare, hasLength(24));

      for (final MapEntry<int, String> entry
          in MillBoardCoordinateMaps.squareToNotation.entries) {
        expect(
          MillBoardCoordinateMaps.notationToLegacySquare(entry.value),
          entry.key,
        );
        expect(
          MillBoardCoordinateMaps.legacySquareToNotation(entry.key),
          entry.value,
        );
      }
    });

    test('node/square/notation maps agree for all 24 points', () {
      expect(MillBoardCoordinateMaps.nodeToLegacySquare, hasLength(24));
      expect(MillBoardCoordinateMaps.legacySquareToNode, hasLength(24));

      for (final MapEntry<int, int> entry
          in MillBoardCoordinateMaps.nodeToLegacySquare.entries) {
        final String notation = MillBoardCoordinateMaps.nodeToNotation(
          entry.key,
        );
        expect(notation, isNotEmpty);
        expect(
          MillBoardCoordinateMaps.legacySquareToNode[entry.value],
          entry.key,
        );
        expect(MillBoardCoordinateMaps.notationToNode(notation), entry.key);
      }
    });
  });
}
