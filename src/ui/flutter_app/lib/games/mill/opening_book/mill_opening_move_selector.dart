// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ignore_for_file: avoid_classes_with_only_static_members

// mill_opening_move_selector.dart
//
// Chooses which book move to play among the candidate moves an opening-book
// position offers. Every candidate is already a "best" move from the oracle, so
// the selector only decides preference/variety — it can never weaken the AI by
// picking a non-book move.
//
// Policy:
//   * shuffling off  -> deterministic first candidate (oracle lists best-first),
//                       identical to the legacy behaviour.
//   * shuffling on    -> rank-biased weighted sampling that favours earlier
//                       (stronger) candidates while still varying the opening,
//                       a lightweight temperature scheme. [bias] == 1 reduces to
//                       the legacy uniform shuffle; smaller values concentrate
//                       weight on the front of the list.

import 'dart:math';

abstract final class MillOpeningMoveSelector {
  /// Geometric weight ratio between successive candidates when shuffling.
  /// 1.0 == uniform; 0.6 mildly favours the stronger, earlier moves.
  static const double defaultBias = 0.6;

  /// Returns one move from [candidates] (which must be non-empty).
  static String select(
    List<String> candidates, {
    required bool shuffling,
    Random? random,
    double bias = defaultBias,
  }) {
    assert(candidates.isNotEmpty, 'candidate move list must not be empty');
    if (!shuffling || candidates.length == 1) {
      return candidates.first;
    }

    final Random rng = random ?? Random(DateTime.now().millisecondsSinceEpoch);
    if (bias >= 1.0) {
      // Uniform sampling: the legacy shuffle behaviour.
      return candidates[rng.nextInt(candidates.length)];
    }

    final List<double> weights = <double>[
      for (int i = 0; i < candidates.length; i++) pow(bias, i).toDouble(),
    ];
    final double total = weights.fold(0.0, (double a, double b) => a + b);
    double r = rng.nextDouble() * total;
    for (int i = 0; i < candidates.length; i++) {
      r -= weights[i];
      if (r <= 0) {
        return candidates[i];
      }
    }
    return candidates.last;
  }
}
