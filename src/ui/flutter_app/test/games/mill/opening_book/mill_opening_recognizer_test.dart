// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/games/mill/opening_book/mill_opening_recognizer.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';

OpeningEntry _entry({
  required String id,
  required List<String> line,
  String name = 'Test Opening',
  String family = 'Test',
  String favoredSide = 'equal',
  List<Map<String, dynamic>> branches = const <Map<String, dynamic>>[],
}) {
  return OpeningEntry.fromJson(<String, dynamic>{
    'id': id,
    'name': name,
    'family': family,
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

  group('shared prefix ambiguity (Z Mill vs Battle Lines)', () {
    // Both are curated book lines that share the exact d2/d6/f4/b4 start and
    // only diverge at ply 5; Battle Lines has the longer line.
    final List<OpeningEntry> shared = <OpeningEntry>[
      _entry(
        id: 'battle-lines',
        name: 'Battle Lines',
        family: 'Battle Lines',
        line: <String>[
          'd2',
          'd6',
          'f4',
          'b4',
          'f6',
          'b6',
          'f2',
          'b2',
          'd1',
          'd7',
        ],
      ),
      _entry(
        id: 'z-mill-open',
        name: 'Z Mill — Open',
        family: 'Z Mill',
        line: <String>['d2', 'd6', 'f4', 'b4', 'c4', 'c5', 'e3', 'e5'],
      ),
    ];

    test('shared prefix stays ambiguous and lists both families', () {
      final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
        'd2',
        'd6',
        'f4',
        'b4',
      ], shared);
      // No longer committed to the longer line's single name.
      expect(r.status, MillOpeningStatus.probable);
      expect(
        r.candidateFamilies,
        containsAll(<String>['Battle Lines', 'Z Mill']),
      );
    });

    test('the divergent move resolves to the right single opening', () {
      final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
        'd2',
        'd6',
        'f4',
        'b4',
        'c4',
      ], shared);
      expect(r.status, MillOpeningStatus.exact);
      expect(r.openingId, 'z-mill-open');
      expect(r.candidateFamilies, <String>['Z Mill']);
    });

    test('a long learned import never outvotes a curated line', () {
      final List<OpeningEntry> mixed = <OpeningEntry>[
        _entry(
          id: 'z-mill-open',
          name: 'Z Mill — Open',
          family: 'Z Mill',
          line: <String>['d2', 'd6', 'f4', 'b4', 'c4', 'c5', 'e3', 'e5'],
        ),
        // Imported (learned) line: different family, shares the prefix, far
        // longer. Previously this hijacked the name via the longest-line rule.
        OpeningEntry.fromJson(<String, dynamic>{
          'id': 'book-99-aaaaaa',
          'name': 'Battle Lines — Black Loss',
          'family': 'Battle Lines',
          'source': 'learned',
          'confidence': 0.8,
          'line_moves': <String>[
            'd2',
            'd6',
            'f4',
            'b4',
            'f6',
            'f2',
            'b6',
            'b2',
            'd3',
            'g4',
            'c4',
            'c3',
            'a4',
            'e5',
            'd5',
            'd7',
            'g7',
            'e3',
          ],
          'favoredSide': 'equal',
        }),
      ];
      final MillOpeningRecognition r = MillOpeningRecognizer.recognize(<String>[
        'd2',
        'd6',
        'f4',
        'b4',
      ], mixed);
      // Curated tier wins naming; the learned family is excluded entirely.
      expect(r.openingId, 'z-mill-open');
      expect(r.candidateFamilies, <String>['Z Mill']);
      expect(r.status, MillOpeningStatus.exact);
    });
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

  group('bookContinuationMoves (oracle-miss fallback)', () {
    test('extends a matching line regardless of which side it favours', () {
      // o1 favours White, but the continuation fallback is side-independent.
      final List<String> moves = MillOpeningRecognizer.bookContinuationMoves(
        <String>['d2', 'd6'],
        book,
      );
      expect(moves, contains('f4'));
      // The favoured-side director would not offer this line to Black, proving
      // the continuation path is broader than the director.
      expect(
        MillOpeningRecognizer.favoredOpeningMoves(
          <String>['d2', 'd6'],
          book,
          'B',
        ),
        isEmpty,
      );
    });

    test('history off every line yields no continuation', () {
      expect(
        MillOpeningRecognizer.bookContinuationMoves(<String>['a1', 'g7'], book),
        isEmpty,
      );
    });

    test('higher-confidence line is offered first', () {
      final List<OpeningEntry> mixed = <OpeningEntry>[
        OpeningEntry.fromJson(<String, dynamic>{
          'id': 'low',
          'name': 'Low confidence',
          'source': 'learned',
          'confidence': 0.3,
          'lineMoves': <String>['d2', 'd6', 'b4'],
          'favoredSide': 'equal',
        }),
        OpeningEntry.fromJson(<String, dynamic>{
          'id': 'high',
          'name': 'High confidence',
          'source': 'book',
          'confidence': 0.9,
          'lineMoves': <String>['d2', 'd6', 'f4'],
          'favoredSide': 'equal',
        }),
      ];
      final List<String> moves = MillOpeningRecognizer.bookContinuationMoves(
        <String>['d2', 'd6'],
        mixed,
      );
      expect(moves.first, 'f4');
      expect(moves, containsAll(<String>['f4', 'b4']));
    });
  });
}
