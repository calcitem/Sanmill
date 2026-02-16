// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// pgn_square_test.dart
//
// Tests for the PGN module's Square class and helper functions.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Square.parse
  // ---------------------------------------------------------------------------
  group('Square.parse', () {
    test("should parse valid Nine Men's Morris squares", () {
      expect(Square.parse('a1'), isNotNull);
      expect(Square.parse('a1')!.name, 'a1');

      expect(Square.parse('d5'), isNotNull);
      expect(Square.parse('d5')!.name, 'd5');

      expect(Square.parse('g7'), isNotNull);
      expect(Square.parse('g7')!.name, 'g7');
    });

    test('should parse all valid file-rank combinations', () {
      const List<String> files = <String>['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      const List<String> ranks = <String>['1', '2', '3', '4', '5', '6', '7'];

      for (final String file in files) {
        for (final String rank in ranks) {
          final Square? sq = Square.parse('$file$rank');
          expect(sq, isNotNull, reason: 'Should parse "$file$rank"');
          expect(sq!.name, '$file$rank');
        }
      }
    });

    test('should return null for invalid notation', () {
      expect(Square.parse(''), isNull);
      expect(Square.parse('z9'), isNull);
      expect(Square.parse('a0'), isNull);
      expect(Square.parse('a8'), isNull);
      expect(Square.parse('h1'), isNull);
      expect(Square.parse('abc'), isNull);
      expect(Square.parse('1a'), isNull);
    });

    test('should return null for single character', () {
      expect(Square.parse('a'), isNull);
      expect(Square.parse('1'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Square equality
  // ---------------------------------------------------------------------------
  group('Square equality', () {
    test('should be equal for same name', () {
      expect(const Square('a1'), const Square('a1'));
      expect(const Square('d5'), const Square('d5'));
    });

    test('should not be equal for different names', () {
      expect(const Square('a1'), isNot(const Square('a2')));
      expect(const Square('a1'), isNot(const Square('b1')));
    });

    test('hashCode should be consistent with equality', () {
      expect(const Square('a1').hashCode, const Square('a1').hashCode);
      // Different squares should (likely) have different hashes
      expect(const Square('a1').hashCode, isNot(const Square('g7').hashCode));
    });
  });

  // ---------------------------------------------------------------------------
  // fromPgn result parsing
  // ---------------------------------------------------------------------------
  group('fromPgn', () {
    test('should return valid results as-is', () {
      expect(fromPgn('1-0'), '1-0');
      expect(fromPgn('0-1'), '0-1');
      expect(fromPgn('1/2-1/2'), '1/2-1/2');
    });

    test('should return * for unknown result', () {
      expect(fromPgn('*'), '*');
      expect(fromPgn(null), '*');
      expect(fromPgn('unknown'), '*');
      expect(fromPgn(''), '*');
    });
  });

  // ---------------------------------------------------------------------------
  // toPgnString
  // ---------------------------------------------------------------------------
  group('toPgnString', () {
    test('should return the same string', () {
      expect(toPgnString('1-0'), '1-0');
      expect(toPgnString('0-1'), '0-1');
      expect(toPgnString('1/2-1/2'), '1/2-1/2');
      expect(toPgnString('*'), '*');
    });
  });
}
