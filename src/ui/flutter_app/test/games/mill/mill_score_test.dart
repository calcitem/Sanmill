// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_score.dart';
import 'package:sanmill/games/mill/mill_types.dart';

void main() {
  group('millScore master parity', () {
    setUp(resetMillScore);
    tearDown(resetMillScore);

    test('initial score is all zeros', () {
      expect(millScore[PieceColor.white], 0);
      expect(millScore[PieceColor.black], 0);
      expect(millScore[PieceColor.draw], 0);
    });

    test('millScoreString uses white-draw-black order', () {
      millScore[PieceColor.white] = 5;
      millScore[PieceColor.black] = 3;
      millScore[PieceColor.draw] = 2;

      expect(millScoreString, '5 - 2 - 3');
    });

    test('resetMillScore clears all score buckets', () {
      millScore[PieceColor.white] = 10;
      millScore[PieceColor.black] = 7;
      millScore[PieceColor.draw] = 3;

      resetMillScore();

      expect(millScore[PieceColor.white], 0);
      expect(millScore[PieceColor.black], 0);
      expect(millScore[PieceColor.draw], 0);
    });
  });
}
