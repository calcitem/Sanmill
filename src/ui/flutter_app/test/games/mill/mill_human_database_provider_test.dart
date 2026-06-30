// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_human_database_provider.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

tgf.MillHumanDatabaseMove _move({
  required int total,
  required double scoreDelta,
  String notation = 'd6',
}) {
  return tgf.MillHumanDatabaseMove(
    notation: notation,
    wins: total,
    losses: 0,
    draws: 0,
    total: total,
    winPct: 0,
    scoreDelta: scoreDelta,
  );
}

/// Tally the chosen index over a fixed range of seeds, so the softmax draw is
/// exercised deterministically and its distribution can be asserted.
Map<int, int> _tally(
  List<tgf.MillHumanDatabaseMove> candidates, {
  required int skillLevel,
  int seeds = 500,
}) {
  final Map<int, int> counts = <int, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final int index = MillHumanDatabaseProvider.selectCandidateIndex(
      candidates,
      shuffling: true,
      skillLevel: skillLevel,
      random: Random(seed),
    );
    counts[index] = (counts[index] ?? 0) + 1;
  }
  return counts;
}

void main() {
  // Clear best (0), mid (1), weak (2); equal samples so only the score matters.
  List<tgf.MillHumanDatabaseMove> spread() => <tgf.MillHumanDatabaseMove>[
    _move(total: 50, scoreDelta: 0.40),
    _move(total: 50, scoreDelta: 0.20),
    _move(total: 50, scoreDelta: 0.00),
  ];

  group(
    'MillHumanDatabaseProvider.selectCandidateIndex (Move randomly off)',
    () {
      test('picks the highest confidence-weighted score', () {
        final List<tgf.MillHumanDatabaseMove> candidates =
            <tgf.MillHumanDatabaseMove>[
              _move(total: 100, scoreDelta: 0.10),
              _move(total: 10, scoreDelta: 0.40),
              _move(total: 50, scoreDelta: 0.20),
            ];

        final int index = MillHumanDatabaseProvider.selectCandidateIndex(
          candidates,
          shuffling: false,
          skillLevel: 15,
          random: Random(0),
        );

        expect(index, 1);
      });

      test('breaks score ties by the larger sample count', () {
        final List<tgf.MillHumanDatabaseMove> candidates =
            <tgf.MillHumanDatabaseMove>[
              _move(total: 20, scoreDelta: 0.30),
              _move(total: 50, scoreDelta: 0.30),
            ];

        final int index = MillHumanDatabaseProvider.selectCandidateIndex(
          candidates,
          shuffling: false,
          skillLevel: 1,
          random: Random(0),
        );

        expect(index, 1);
      });

      test('is independent of skill level', () {
        final List<tgf.MillHumanDatabaseMove> candidates = spread();
        for (final int skill in <int>[1, 15, 30]) {
          expect(
            MillHumanDatabaseProvider.selectCandidateIndex(
              candidates,
              shuffling: false,
              skillLevel: skill,
              random: Random(0),
            ),
            0,
          );
        }
      });
    },
  );

  group(
    'MillHumanDatabaseProvider.selectCandidateIndex (Move randomly on, skill→temperature)',
    () {
      test('max skill concentrates on the best-scoring move', () {
        final Map<int, int> counts = _tally(spread(), skillLevel: 30);
        // The best move dominates (low temperature), and the weakest is almost
        // never played.
        expect(counts[0] ?? 0, greaterThan(450));
        expect(counts[2] ?? 0, lessThan(10));
      });

      test('min skill spreads the draw toward weaker, more varied moves', () {
        final Map<int, int> counts = _tally(spread(), skillLevel: 1);
        // Variety: more than one move is played, including the weakest one, and
        // the best no longer dominates.
        expect(counts.keys.length, greaterThan(1));
        expect(counts[2] ?? 0, greaterThan(0));
        expect(counts[0] ?? 0, lessThan(350));
      });

      test('higher skill is strictly more concentrated than lower skill', () {
        final int hiBest = _tally(spread(), skillLevel: 30)[0] ?? 0;
        final int midBest = _tally(spread(), skillLevel: 15)[0] ?? 0;
        final int loBest = _tally(spread(), skillLevel: 1)[0] ?? 0;
        expect(hiBest, greaterThan(midBest));
        expect(midBest, greaterThan(loBest));
      });

      test('single candidate is always selected, any skill', () {
        final List<tgf.MillHumanDatabaseMove> only =
            <tgf.MillHumanDatabaseMove>[_move(total: 3, scoreDelta: 0.10)];
        for (final int skill in <int>[1, 30]) {
          expect(
            MillHumanDatabaseProvider.selectCandidateIndex(
              only,
              shuffling: true,
              skillLevel: skill,
              random: Random(skill),
            ),
            0,
          );
        }
      });
    },
  );

  group('MillHumanDatabaseProvider.minSamplesForSkill', () {
    test('spans 3 (min skill) to 30 (max skill)', () {
      expect(MillHumanDatabaseProvider.minSamplesForSkill(1), 3);
      expect(MillHumanDatabaseProvider.minSamplesForSkill(30), 30);
    });

    test('clamps out-of-range skill into the supported band', () {
      expect(MillHumanDatabaseProvider.minSamplesForSkill(-5), 3);
      expect(MillHumanDatabaseProvider.minSamplesForSkill(0), 3);
      expect(MillHumanDatabaseProvider.minSamplesForSkill(99), 30);
    });

    test('is monotonic non-decreasing in skill', () {
      int previous = 0;
      for (int skill = 1; skill <= 30; skill++) {
        final int samples = MillHumanDatabaseProvider.minSamplesForSkill(skill);
        expect(samples, greaterThanOrEqualTo(previous));
        expect(samples, inInclusiveRange(3, 30));
        previous = samples;
      }
    });
  });
}
