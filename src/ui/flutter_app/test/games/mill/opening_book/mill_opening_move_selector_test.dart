// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/opening_book/mill_opening_move_selector.dart';

void main() {
  const List<String> candidates = <String>['d2', 'b4', 'd6', 'f4'];

  test('deterministic first candidate when shuffling is off', () {
    for (int i = 0; i < 8; i++) {
      expect(
        MillOpeningMoveSelector.select(candidates, shuffling: false),
        'd2',
      );
    }
  });

  test('single candidate is returned regardless of shuffling', () {
    expect(
      MillOpeningMoveSelector.select(<String>['d2'], shuffling: true),
      'd2',
    );
  });

  test('shuffling only ever returns one of the candidates', () {
    final Random rng = Random(42);
    for (int i = 0; i < 200; i++) {
      final String move = MillOpeningMoveSelector.select(
        candidates,
        shuffling: true,
        random: rng,
      );
      expect(candidates.contains(move), isTrue);
    }
  });

  test('rank bias favours earlier candidates over later ones', () {
    final Random rng = Random(7);
    final Map<String, int> counts = <String, int>{};
    for (int i = 0; i < 4000; i++) {
      final String move = MillOpeningMoveSelector.select(
        candidates,
        shuffling: true,
        random: rng,
      );
      counts[move] = (counts[move] ?? 0) + 1;
    }
    final int firstCount = counts['d2'] ?? 0;
    final int lastCount = counts['f4'] ?? 0;
    expect(firstCount, greaterThan(lastCount));
  });

  test('bias of 0.0 always returns the first candidate', () {
    final Random rng = Random(99);
    for (int i = 0; i < 100; i++) {
      expect(
        MillOpeningMoveSelector.select(
          candidates,
          shuffling: true,
          random: rng,
          bias: 0.0,
        ),
        'd2',
      );
    }
  });

  test('bias of 1.0 reproduces a uniform shuffle', () {
    final Random rng = Random(123);
    final Map<String, int> counts = <String, int>{};
    for (int i = 0; i < 4000; i++) {
      final String move = MillOpeningMoveSelector.select(
        candidates,
        shuffling: true,
        random: rng,
        bias: 1.0,
      );
      counts[move] = (counts[move] ?? 0) + 1;
    }
    // Every candidate should be sampled a non-trivial number of times.
    for (final String move in candidates) {
      expect(counts[move] ?? 0, greaterThan(500));
    }
  });
}
