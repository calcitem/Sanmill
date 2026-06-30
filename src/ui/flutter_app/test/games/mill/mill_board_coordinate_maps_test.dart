// SPDX-License-Identifier: AGPL-3.0-or-later
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

    test('mill node line tables include standard and diagonal lines', () {
      expect(MillBoardCoordinateMaps.standardMillNodeLines, hasLength(16));
      expect(MillBoardCoordinateMaps.diagonalMillNodeLines, hasLength(20));
      expect(MillBoardCoordinateMaps.standardMillNodeLines.first, <int>[
        7,
        0,
        1,
      ]);
      expect(MillBoardCoordinateMaps.diagonalMillNodeLines.last, <int>[
        3,
        11,
        19,
      ]);
    });

    test('PlayOK numeric notation maps to standard notation', () {
      expect(MillBoardCoordinateMaps.playOkToStandardNotation, hasLength(24));
      expect(MillBoardCoordinateMaps.playOkToStandardNotation['1'], 'a7');
      expect(MillBoardCoordinateMaps.playOkToStandardNotation['24'], 'g1');
      for (final String notation
          in MillBoardCoordinateMaps.playOkToStandardNotation.values) {
        expect(
          MillBoardCoordinateMaps.notationToLegacySquare(notation),
          isNot(-1),
        );
      }
    });

    test('legacy square arithmetic preserves engine encoding', () {
      expect(MillBoardCoordinateMaps.legacySquareBegin, 8);
      expect(MillBoardCoordinateMaps.legacySquareEnd, 32);
      expect(MillBoardCoordinateMaps.legacySquareStorageSize, 40);
      expect(MillBoardCoordinateMaps.makeLegacySquare(0, 0), 0);
      expect(MillBoardCoordinateMaps.makeLegacySquare(-1, -1), -1);
      expect(MillBoardCoordinateMaps.makeLegacySquare(1, 1), 8);
      expect(MillBoardCoordinateMaps.makeLegacySquare(3, 8), 31);

      for (int file = 1; file <= MillBoardCoordinateMaps.fileNumber; file++) {
        for (int rank = 1; rank <= MillBoardCoordinateMaps.rankNumber; rank++) {
          final int square = MillBoardCoordinateMaps.makeLegacySquare(
            file,
            rank,
          );
          expect(MillBoardCoordinateMaps.isLegacySquareOk(square), isTrue);
          expect(MillBoardCoordinateMaps.fileOfLegacySquare(square), file);
          expect(MillBoardCoordinateMaps.rankOfLegacySquare(square), rank);
        }
      }
    });
  });
}
