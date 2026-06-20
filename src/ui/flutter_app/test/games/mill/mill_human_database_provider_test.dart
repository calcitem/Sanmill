// SPDX-License-Identifier: GPL-3.0-or-later
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

void main() {
  group('MillHumanDatabaseProvider.selectCandidateIndex', () {
    test('off picks the highest confidence-weighted score', () {
      final List<tgf.MillHumanDatabaseMove> candidates =
          <tgf.MillHumanDatabaseMove>[
            _move(total: 100, scoreDelta: 0.10),
            _move(total: 10, scoreDelta: 0.40),
            _move(total: 50, scoreDelta: 0.20),
          ];

      final int index = MillHumanDatabaseProvider.selectCandidateIndex(
        candidates,
        shuffling: false,
        random: Random(0),
      );

      expect(index, 1);
    });

    test('off breaks score ties by the larger sample count', () {
      final List<tgf.MillHumanDatabaseMove> candidates =
          <tgf.MillHumanDatabaseMove>[
            _move(total: 20, scoreDelta: 0.30),
            _move(total: 50, scoreDelta: 0.30),
          ];

      final int index = MillHumanDatabaseProvider.selectCandidateIndex(
        candidates,
        shuffling: false,
        random: Random(0),
      );

      expect(index, 1);
    });

    test('on never picks moves outside the mainstream pool', () {
      // maxTotal = 100 -> threshold = max(10, 25) = 25; only A and B qualify.
      final List<tgf.MillHumanDatabaseMove> candidates =
          <tgf.MillHumanDatabaseMove>[
            _move(total: 100, scoreDelta: 0.0), // A: in pool
            _move(total: 50, scoreDelta: 0.0), // B: in pool
            _move(total: 5, scoreDelta: 0.5), // C: rare, excluded
          ];

      final Set<int> chosen = <int>{};
      for (int seed = 0; seed < 500; seed++) {
        chosen.add(
          MillHumanDatabaseProvider.selectCandidateIndex(
            candidates,
            shuffling: true,
            random: Random(seed),
          ),
        );
      }

      expect(chosen.contains(2), isFalse);
      expect(chosen, containsAll(<int>[0, 1]));
    });

    test('on falls back to the best score when the pool is empty', () {
      // maxTotal = 8 -> threshold = max(10, 2) = 10; nothing qualifies.
      final List<tgf.MillHumanDatabaseMove> candidates =
          <tgf.MillHumanDatabaseMove>[
            _move(total: 5, scoreDelta: 0.10),
            _move(total: 8, scoreDelta: 0.40),
            _move(total: 3, scoreDelta: 0.20),
          ];

      for (int seed = 0; seed < 50; seed++) {
        final int index = MillHumanDatabaseProvider.selectCandidateIndex(
          candidates,
          shuffling: true,
          random: Random(seed),
        );
        expect(index, 1);
      }
    });

    test('single candidate is always selected in both modes', () {
      final List<tgf.MillHumanDatabaseMove> popular =
          <tgf.MillHumanDatabaseMove>[_move(total: 100, scoreDelta: 0.10)];
      final List<tgf.MillHumanDatabaseMove> rare = <tgf.MillHumanDatabaseMove>[
        _move(total: 3, scoreDelta: 0.10),
      ];

      expect(
        MillHumanDatabaseProvider.selectCandidateIndex(
          popular,
          shuffling: false,
          random: Random(0),
        ),
        0,
      );
      expect(
        MillHumanDatabaseProvider.selectCandidateIndex(
          popular,
          shuffling: true,
          random: Random(0),
        ),
        0,
      );
      // Rare single move: pool is empty, but the fallback still returns it.
      expect(
        MillHumanDatabaseProvider.selectCandidateIndex(
          rare,
          shuffling: true,
          random: Random(0),
        ),
        0,
      );
    });
  });
}
