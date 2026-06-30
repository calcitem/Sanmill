// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/mill_opening_book_symmetry.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';

import 'opening_book/opening_book_test_assets.dart';

// Exercises the 16-way symmetry lookup helpers against the SHIPPED oracle the
// app actually loads at runtime (assets/opening_books/.../opening_book.json),
// not a compile-time map.
void main() {
  late Map<String, List<String>> nmmOracle;
  late Map<String, List<String>> elFiljaOracle;

  setUpAll(() async {
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
    await OpeningBookRepository.instance.ensureLoaded();
    nmmOracle = OpeningBookRepository.instance.oracleFor(isElFilja: false);
    elFiljaOracle = OpeningBookRepository.instance.oracleFor(isElFilja: true);
  });

  tearDownAll(OpeningBookRepository.instance.resetForTest);

  test('canonical position returns its stored representative line', () {
    const String fen =
        '********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
    expect(lookupCanonicalOpeningBook(nmmOracle, fen), nmmOracle[fen]);
  });

  test('lookup misses cleanly for an unknown position', () {
    const String fen =
        'O@O@O@O@/O@O@O@O@/O@O@O@O@ w p p 9 0 9 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
    expect(lookupCanonicalOpeningBook(nmmOracle, fen), isNull);
  });

  test('non-canonical query is rotated back into its own frame', () {
    // White has played d2; the canonical key for this orbit stores the line in
    // the b4 frame, so the lookup must relabel it back to the d2 frame.
    const String fen =
        '********/****O***/******** b p p 1 8 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
    final List<String>? result = lookupCanonicalOpeningBook(nmmOracle, fen);
    expect(result, isNotNull);
    expect(result!.toSet(), <String>{'d6', 'f6', 'b6', 'f4', 'b4', 'b2', 'f2'});
  });

  group('every canonical entry resolves for all 16 symmetric variants', () {
    void verifyBook(Map<String, List<String>> book) {
      expect(book, isNotEmpty);
      for (final MapEntry<String, List<String>> entry in book.entries) {
        for (final TransformationType type in TransformationType.values) {
          final String queryFen = transformFEN(entry.key, type);
          final List<String>? result = lookupCanonicalOpeningBook(
            book,
            queryFen,
          );
          expect(
            result,
            isNotNull,
            reason: 'no book hit for ${type.name} of ${entry.key}',
          );
          // A symmetric variant must yield a book line of the same length as
          // the canonical representative (a rotated copy of the same moves).
          expect(
            result!.length,
            entry.value.length,
            reason: 'length mismatch for ${type.name} of ${entry.key}',
          );
        }
      }
    }

    test("nine men's morris", () {
      verifyBook(nmmOracle);
    });

    test('el filja', () {
      verifyBook(elFiljaOracle);
    });
  });
}
