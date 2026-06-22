// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_source_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_studio_repository.dart';

void main() {
  test('source package round-trips to runtime opening entries', () {
    final SanmillOpeningBookSourcePackage package =
        SanmillOpeningBookSourcePackage.nmm(
          openings: <SanmillOpeningSourceEntry>[_sampleOpening()],
        );

    final String encoded = const JsonEncoder().convert(package.toJson());
    final SanmillOpeningBookSourcePackage decoded =
        SanmillOpeningBookSourcePackage.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
    final OpeningEntry entry = decoded.toOpeningEntries().single;

    expect(decoded.format, sanmillOpeningBookSourceFormat);
    expect(entry.id, 'center-cross');
    expect(entry.lineMoves, <String>['d2', 'd6', 'd5', 'e5']);
    expect(entry.branchMoves.single.deviationMove, 'g7');
    expect(entry.outcomeStats, <String, int>{'W': 3, 'B': 1, 'D': 2});
  });

  test('validation reports duplicate ids and invalid coordinates', () {
    final SanmillOpeningSourceEntry opening = _sampleOpening();
    final SanmillOpeningBookSourcePackage package =
        SanmillOpeningBookSourcePackage.nmm(
          openings: <SanmillOpeningSourceEntry>[
            opening,
            opening.copyWith(
              line: const SanmillOpeningLine(moves: <String>['d2', 'z9']),
            ),
          ],
        );

    final OpeningBookSourceValidationResult result =
        validateSanmillOpeningBookSource(package);

    expect(result.isValid, isFalse);
    expect(result.errors, contains('Duplicate opening id: center-cross'));
    expect(
      result.errors,
      contains(
        'Opening center-cross main line contains invalid coordinate: z9',
      ),
    );
  });

  test('studio repository accepts the legacy authored array format', () {
    final OpeningEntry legacy = _sampleOpening().toOpeningEntry();
    final String encoded = const JsonEncoder().convert(<Map<String, dynamic>>[
      legacy.toJson(),
    ]);

    final SanmillOpeningBookSourcePackage package =
        const OpeningBookStudioRepository().parseSourcePackage(encoded);

    expect(package.openings.single.id, legacy.id);
    expect(package.openings.single.line.moves, legacy.lineMoves);
  });
}

SanmillOpeningSourceEntry _sampleOpening() {
  return const SanmillOpeningSourceEntry(
    id: 'center-cross',
    name: 'Center Cross',
    family: 'Central',
    aliases: <String>['Cross setup'],
    side: 'both',
    favoredSide: 'W',
    confidence: 0.9,
    tags: <String>['placement', 'manual'],
    stats: SanmillOpeningStats(
      whiteWins: 3,
      blackWins: 1,
      draws: 2,
      sampleSize: 6,
    ),
    line: SanmillOpeningLine(
      moves: <String>['d2', 'd6', 'd5', 'e5'],
      comment: 'Controls the central files.',
      variations: <SanmillOpeningVariation>[
        SanmillOpeningVariation(
          id: 'center-cross-wing',
          name: 'Wing try',
          afterPly: 2,
          moves: <String>['g7', 'a1'],
        ),
      ],
    ),
    commonBlunders: <String>['c3 before d5'],
    recommendedResponses: <String, List<String>>{
      'W': <String>['d5'],
      'B': <String>['e5'],
    },
    source: 'book',
    sourceReference: 'test',
  );
}
