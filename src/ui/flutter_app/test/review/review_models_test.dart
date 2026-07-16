// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  group('ReviewGrading', () {
    test('uses the documented loss boundaries', () {
      const int best = 20;
      expect(_grade(best, 20), ReviewGrade.best);
      expect(_grade(best, 19), ReviewGrade.best);
      expect(_grade(best, 18), ReviewGrade.good);
      expect(_grade(best, 17), ReviewGrade.good);
      expect(_grade(best, 16), ReviewGrade.dubious);
      expect(_grade(best, 13), ReviewGrade.dubious);
      expect(_grade(best, 12), ReviewGrade.mistake);
      expect(_grade(best, 6), ReviewGrade.mistake);
      expect(_grade(best, 5), ReviewGrade.blunder);
    });

    test('treats a worse win-draw-loss band as a blunder', () {
      expect(_grade(80, 79), ReviewGrade.blunder);
      expect(_grade(-79, -80), ReviewGrade.blunder);
    });
  });

  group('PrivateGameRecord', () {
    test('deduplicates by movetext, initial position, result, and rules', () {
      final DateTime now = DateTime.utc(2026, 7, 16);
      final PrivateGameRecord first = PrivateGameRecord.create(
        sourcePgn: '[Event "First"]\n\n1. a7 b6 *',
        initialFen: null,
        result: '*',
        rules: const RuleSettings(),
        completedAt: now,
        white: 'A',
        black: 'B',
        humanSides: const <ReviewSide>{ReviewSide.white},
        finalBoardLayout: null,
        moveCount: 2,
      );
      final PrivateGameRecord sameGame = PrivateGameRecord.create(
        sourcePgn: '[Event "Renamed"]\n[Date "2026.07.16"]\n\n1. a7  b6 *',
        initialFen: '',
        result: '*',
        rules: const RuleSettings(),
        completedAt: now.add(const Duration(minutes: 1)),
        white: 'A',
        black: 'B',
        humanSides: const <ReviewSide>{ReviewSide.white},
        finalBoardLayout: null,
        moveCount: 2,
      );
      final PrivateGameRecord customRules = PrivateGameRecord.create(
        sourcePgn: sameGame.sourcePgn,
        initialFen: '',
        result: '*',
        rules: const RuleSettings(nMoveRule: 99),
        completedAt: now,
        white: 'A',
        black: 'B',
        humanSides: const <ReviewSide>{ReviewSide.white},
        finalBoardLayout: null,
        moveCount: 2,
      );

      expect(sameGame.id, first.id);
      expect(customRules.id, isNot(first.id));
    });
  });

  test('PGN cache identity ignores housekeeping tags but includes FEN', () {
    const String first = '[Date "2026.07.16"]\n\n1. a7 b6 *';
    const String renamed = '[Date "2027.01.01"]\n[Round "8"]\n\n1. a7 b6 *';
    const String setup =
        '[FEN "********/********/******** w p p 9 9 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"]\n\n'
        '1. a7 b6 *';

    expect(pgnFingerprint(renamed), pgnFingerprint(first));
    expect(pgnFingerprint(setup), isNot(pgnFingerprint(first)));
  });

  group('ReviewReport', () {
    test('filters correction candidates to human mistakes', () {
      final ReviewReport report = _report(
        grades: const <ReviewGrade>[
          ReviewGrade.mistake,
          ReviewGrade.blunder,
          ReviewGrade.good,
        ],
        human: const <bool>[true, false, true],
      );

      expect(
        report.humanMistakes.map(
          (ReviewActionEvaluation value) => value.groupIndex,
        ),
        <int>[0],
      );
    });

    test('resolves NAG priority as user, source, then automatic', () {
      final ReviewReport report = _report(
        grades: const <ReviewGrade>[
          ReviewGrade.blunder,
          ReviewGrade.blunder,
          ReviewGrade.dubious,
        ],
        sourceNags: const <List<int>>[
          <int>[1],
          <int>[10],
          <int>[],
        ],
        overrides: const <int, int?>{0: 5, 2: null},
      );

      expect(report.effectiveQualityNagForTurn(0), 5);
      expect(report.effectiveQualityNagForTurn(1), 4);
      expect(report.effectiveQualityNagForTurn(2), isNull);
    });

    test(
      'round-trips versioned data and invalidates every cache dimension',
      () {
        final ReviewReport report = _report(
          grades: const <ReviewGrade>[ReviewGrade.mistake],
        );
        final ReviewReport restored = ReviewReport.fromJson(report.toJson());
        expect(restored.version, reviewSchemaVersion);
        expect(restored.actions.single.grade, ReviewGrade.mistake);
        expect(restored.cacheKey, report.cacheKey);

        final Set<String> keys = <String>{
          ReviewReport.cacheKeyFor(
            pgnHash: 'a',
            rulesHash: 'r',
            engineVersion: 'e',
            profile: ReviewProfile.quick,
          ),
          ReviewReport.cacheKeyFor(
            pgnHash: 'b',
            rulesHash: 'r',
            engineVersion: 'e',
            profile: ReviewProfile.quick,
          ),
          ReviewReport.cacheKeyFor(
            pgnHash: 'a',
            rulesHash: 's',
            engineVersion: 'e',
            profile: ReviewProfile.quick,
          ),
          ReviewReport.cacheKeyFor(
            pgnHash: 'a',
            rulesHash: 'r',
            engineVersion: 'f',
            profile: ReviewProfile.quick,
          ),
          ReviewReport.cacheKeyFor(
            pgnHash: 'a',
            rulesHash: 'r',
            engineVersion: 'e',
            profile: ReviewProfile.deep,
          ),
        };
        expect(keys, hasLength(5));
      },
    );
  });
}

ReviewGrade _grade(int best, int played) =>
    ReviewGrading.grade(bestScore: best, playedScore: played);

ReviewReport _report({
  required List<ReviewGrade> grades,
  List<bool>? human,
  List<List<int>>? sourceNags,
  Map<int, int?> overrides = const <int, int?>{},
  bool includeAnnotationsOnExport = false,
}) {
  final DateTime now = DateTime.utc(2026, 7, 16);
  final List<ReviewActionEvaluation> actions = <ReviewActionEvaluation>[
    for (int index = 0; index < grades.length; index++)
      ReviewActionEvaluation(
        atomicIndex: index,
        groupIndex: index,
        move: 'a${index + 1}',
        side: index.isEven ? ReviewSide.white : ReviewSide.black,
        isHumanMove: human?[index] ?? true,
        legalRootActionCount: 3,
        bestScore: 20,
        playedScore: 10,
        loss: 10,
        grade: grades[index],
        profile: ReviewProfile.quick,
        candidates: <ReviewCandidate>[
          ReviewCandidate(
            rank: 1,
            move: 'b${index + 1}',
            score: 20,
            depth: 24,
            line: <String>['b${index + 1}'],
          ),
          ReviewCandidate(
            rank: 2,
            move: 'a${index + 1}',
            score: 10,
            depth: 24,
            line: <String>['a${index + 1}'],
          ),
        ],
      ),
  ];
  return ReviewReport(
    recordId: 'record',
    pgnHash: 'pgn',
    rulesHash: 'rules',
    engineVersion: reviewEngineVersion,
    profile: ReviewProfile.quick,
    status: ReviewStatus.complete,
    actions: actions,
    turns: <ReviewTurnBoundary>[
      for (int index = 0; index < grades.length; index++)
        ReviewTurnBoundary(
          groupIndex: index,
          startAtomicIndex: index,
          endAtomicIndex: index,
          san: 'a${index + 1}',
          anchorMove: 'a${index + 1}',
          side: index.isEven ? ReviewSide.white : ReviewSide.black,
          sourceNags: sourceNags?[index] ?? const <int>[],
          boardLayout: '********/********/********',
        ),
    ],
    variationCount: 0,
    userNagOverrides: overrides,
    includeAnnotationsOnExport: includeAnnotationsOnExport,
    createdAt: now,
    updatedAt: now,
    lastAccessedAt: now,
  );
}
