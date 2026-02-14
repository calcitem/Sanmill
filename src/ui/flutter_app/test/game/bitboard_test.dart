// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// bitboard_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';

void main() {
  group('initBitboards', () {
    setUp(() {
      initBitboards();
    });

    test('should set squareBB[s] = 1 << s for each valid square', () {
      for (int s = 8; s < 32; s++) {
        expect(
          squareBB[s],
          1 << s,
          reason: 'squareBB[$s] should be ${1 << s}',
        );
      }
    });

    test('squareBB[0..7] should remain 0 (not board squares)', () {
      for (int s = 0; s < 8; s++) {
        expect(squareBB[s], 0, reason: 'squareBB[$s] should be 0');
      }
    });

    test('each valid square should have a unique bit', () {
      final Set<int> seen = <int>{};
      for (int s = 8; s < 32; s++) {
        expect(
          seen.contains(squareBB[s]),
          isFalse,
          reason: 'squareBB[$s] should be unique',
        );
        seen.add(squareBB[s]);
      }
    });

    test('each squareBB value should be a power of 2', () {
      for (int s = 8; s < 32; s++) {
        final int val = squareBB[s];
        expect(val, isNonZero);
        // A power of 2 has exactly one bit set: val & (val - 1) == 0
        expect(
          val & (val - 1),
          0,
          reason: 'squareBB[$s] = $val should be a power of 2',
        );
      }
    });
  });

  group('squareBb()', () {
    setUp(() {
      initBitboards();
    });

    test('should return the correct bitboard for valid squares', () {
      for (int s = 8; s < 32; s++) {
        expect(
          squareBb(s),
          1 << s,
          reason: 'squareBb($s)',
        );
      }
    });

    test('should return 0 for out-of-range squares', () {
      expect(squareBb(0), 0);
      expect(squareBb(7), 0);
      expect(squareBb(32), 0);
      expect(squareBb(-1), 0);
      expect(squareBb(100), 0);
    });

    test('OR-ing two squareBb values should give combined mask', () {
      final int combined = squareBb(8) | squareBb(9);
      expect(combined, (1 << 8) | (1 << 9));
    });
  });
}
