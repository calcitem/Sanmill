// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_nag_merge.dart';

void main() {
  const String source = r'1. a7?! b6 $10 2. d6? (2. f6!!) f4 {note} $12 *';

  test('export switch leaves the original PGN byte-for-byte unchanged', () {
    final ReviewReport report = _report(include: false);
    expect(ReviewNagMerge.forExport(source, report), source);
  });

  test('merges quality NAGs by user, source, then automatic priority', () {
    final String exported = ReviewNagMerge.forExport(
      source,
      _report(include: true),
    );
    final PgnGame<PgnNodeData> reparsed = PgnGame.parsePgn(exported);
    final List<PgnNodeData> moves = reparsed.moves.mainline().toList();

    expect(moves, hasLength(4));
    expect(moves[0].nags, contains(6)); // Original ?! wins over automatic.
    expect(moves[1].nags, containsAll(<int>[2, 10])); // Auto ? + unknown.
    expect(moves[2].nags, contains(2)); // Original ? is not replaced.
    expect(moves[3].nags, containsAll(<int>[5, 12])); // User !? wins.
    expect(exported, contains('f6!!'));
    expect(exported, contains('{ note }'));
  });

  test('a null user override explicitly clears source quality NAGs', () {
    final ReviewReport report = _report(
      include: true,
    ).copyWith(userNagOverrides: const <int, int?>{0: null});
    final List<PgnNodeData> moves = PgnGame.parsePgn(
      ReviewNagMerge.forExport(source, report),
    ).moves.mainline().toList();

    expect(
      moves.first.nags?.where((int nag) => nag >= 1 && nag <= 6) ??
          const <int>[],
      isEmpty,
    );
  });

  test('does not attach a mainline review to a diverged exported line', () {
    final List<PgnNodeData> moves = PgnGame.parsePgn(
      ReviewNagMerge.forExport('1. f6 b6 *', _report(include: true)),
    ).moves.mainline().toList();

    expect(moves.first.nags, isNull);
    expect(moves.last.nags, contains(2));
  });
}

ReviewReport _report({required bool include}) {
  final DateTime now = DateTime.utc(2026, 7, 16);
  const List<ReviewGrade> grades = <ReviewGrade>[
    ReviewGrade.blunder,
    ReviewGrade.mistake,
    ReviewGrade.blunder,
    ReviewGrade.good,
  ];
  const List<String> sans = <String>['a7', 'b6', 'd6', 'f4'];
  return ReviewReport(
    recordId: 'record',
    pgnHash: 'pgn',
    rulesHash: 'rules',
    engineVersion: reviewEngineVersion,
    profile: ReviewProfile.quick,
    status: ReviewStatus.complete,
    actions: <ReviewActionEvaluation>[
      for (int index = 0; index < grades.length; index++)
        ReviewActionEvaluation(
          atomicIndex: index,
          groupIndex: index,
          move: 'a$index',
          side: index.isEven ? ReviewSide.white : ReviewSide.black,
          isHumanMove: true,
          legalRootActionCount: 2,
          bestScore: 20,
          playedScore: 10,
          loss: 10,
          grade: grades[index],
          profile: ReviewProfile.quick,
          candidates: <ReviewCandidate>[
            ReviewCandidate(
              rank: 1,
              move: 'b$index',
              score: 20,
              depth: 24,
              line: <String>['b$index'],
            ),
          ],
        ),
    ],
    turns: <ReviewTurnBoundary>[
      for (int index = 0; index < grades.length; index++)
        ReviewTurnBoundary(
          groupIndex: index,
          startAtomicIndex: index,
          endAtomicIndex: index,
          san: sans[index],
          anchorMove: sans[index],
          side: index.isEven ? ReviewSide.white : ReviewSide.black,
          sourceNags: const <int>[],
          boardLayout: '********/********/********',
        ),
    ],
    variationCount: 1,
    userNagOverrides: const <int, int?>{3: 5},
    includeAnnotationsOnExport: include,
    createdAt: now,
    updatedAt: now,
    lastAccessedAt: now,
  );
}
