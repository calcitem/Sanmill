// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/opening_book/mill_opening_recognizer.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';

OpeningEntry _entry({
  required String id,
  required List<String> line,
  String name = 'Test Opening',
  String favoredSide = 'equal',
  List<Map<String, dynamic>> branches = const <Map<String, dynamic>>[],
}) {
  return OpeningEntry.fromJson(<String, dynamic>{
    'id': id,
    'name': name,
    'family': 'Test',
    'side': 'W',
    'source': 'book',
    'sourceReference': 'Ref 1',
    'lineMoves': line,
    'favoredSide': favoredSide,
    'branchMoves': branches,
  });
}

void main() {
  final List<OpeningEntry> book = <OpeningEntry>[
    _entry(
      id: 'o1',
      name: 'Mill Rush',
      favoredSide: 'W',
      line: <String>['d2', 'd6', 'f4', 'b4', 'f2', 'f6', 'b2', 'b6'],
      branches: <Map<String, dynamic>>[
        <String, dynamic>{
          'branchId': 'o1-dev',
          'deviationPly': 5,
          'deviationMove': 'd1',
          'name': 'Mill Rush — d1 Variant',
          'strategicNotes': 'Sideline.',
        },
      ],
    ),
  ];

  test('empty input or empty book yields none', () {
    expect(
      MillOpeningRecognizer.recognize(const <String>[], book).status,
      MillOpeningStatus.none,
    );
    expect(
      MillOpeningRecognizer.recognize(const <String>[
        'd2',
      ], const <OpeningEntry>[]).status,
      MillOpeningStatus.none,
    );
  });

  test('exact in-order prefix match returns the opening and next move', () {
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
      'd2',
      'd6',
    ], book);
    expect(r.isNamed, isTrue);
    expect(r.name, 'Mill Rush');
    expect(r.sourceReference, 'Ref 1');
    expect(r.favoredSide, 'W');
    expect(r.nextMove, 'f4');
  });

  test('full unique line is graded exact', () {
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
      'd2',
      'd6',
      'f4',
      'b4',
      'f2',
      'f6',
      'b2',
      'b6',
    ], book);
    expect(r.status, MillOpeningStatus.exact);
    expect(r.openingId, 'o1');
  });

  test('rotated variant is recognised as the same opening', () {
    const TransformationType t = TransformationType.rotate90;
    final List<String> rotated = <String>[
      'd2',
      'd6',
    ].map((String m) => transformMoveNotation(m, t)).toList();
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(
      rotated,
      book,
    );
    expect(r.openingId, 'o1');
    // The book's next move (f4) must come back in the rotated board frame.
    expect(r.nextMove, transformMoveNotation('f4', t));
  });

  test('reordered placements per side are recognised as a transposition', () {
    // Single-opening book so the match is unambiguous. The line's first two
    // ply fix d6 and f4 (90 deg apart on the ring); the only isometry fixing
    // both is the identity, so swapping White's d2/b4 order yields a genuine
    // transposition rather than a symmetric exact match.
    final List<OpeningEntry> single = <OpeningEntry>[
      _entry(
        id: 'o2',
        name: 'Cross Transposition',
        line: <String>['d2', 'd6', 'b4', 'f4'],
      ),
    ];
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
      'b4',
      'd6',
      'd2',
      'f4',
    ], single);
    expect(r.status, MillOpeningStatus.transposition);
    expect(r.openingId, 'o2');
  });

  test('a known branch deviation is recognised', () {
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
      'd2',
      'd6',
      'f4',
      'b4',
      'd1',
    ], book);
    expect(r.status, MillOpeningStatus.deviation);
    expect(r.branchName, 'Mill Rush — d1 Variant');
    expect(r.deviationPly, 5);
    expect(r.deviationMove, 'd1');
  });

  test('unmatched sequence past the commit ply is novel', () {
    final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
      'a1',
      'g7',
      'g1',
      'a7',
      'a4',
      'g4',
    ], book);
    expect(r.status, MillOpeningStatus.novel);
    expect(r.isNamed, isFalse);
  });

  group('favoredOpeningMoves (director)', () {
    test('empty history offers the favoured first move for that side', () {
      // o1 favours White; at ply 0 its first move (d2) is a candidate.
      final List<String> moves = MillOpeningRecognizer.favoredOpeningMoves(
        const <String>[],
        book,
        'W',
      );
      expect(moves, isNotEmpty);
      expect(moves, contains('d2'));
    });

    test('no candidates for a side the book does not favour', () {
      expect(
        MillOpeningRecognizer.favoredOpeningMoves(const <String>[], book, 'B'),
        isEmpty,
      );
    });

    test('a consistent prefix extends the favoured line', () {
      final List<String> moves = MillOpeningRecognizer.favoredOpeningMoves(
        <String>['d2', 'd6'],
        book,
        'W',
      );
      expect(moves, contains('f4'));
    });

    test('history off the favoured line yields no follow move', () {
      final List<String> moves = MillOpeningRecognizer.favoredOpeningMoves(
        <String>['a1', 'g7'],
        book,
        'W',
      );
      expect(moves, isEmpty);
    });

    test('invalid side is rejected', () {
      expect(
        MillOpeningRecognizer.favoredOpeningMoves(
          const <String>['d2'],
          book,
          '',
        ),
        isEmpty,
      );
    });
  });
}
