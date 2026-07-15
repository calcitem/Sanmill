// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../games/mill/mill_types.dart';

/// History rules that adapt Mill's multi-action turns to Offline Board UX.
abstract final class OfflineBoardHistory {
  /// Counts the trailing recorder actions belonging to the latest full turn.
  ///
  /// A Mill turn can contain a place/move followed by one or more captures.
  /// All of those actions retain the mover's side, so the trailing same-side
  /// group is the atomic unit exposed by the Offline Board undo button.
  static int? takeBackStepCount(List<PieceColor> actionSides) {
    if (actionSides.isEmpty) {
      return null;
    }
    assert(
      actionSides.every(
        (PieceColor side) =>
            side == PieceColor.white || side == PieceColor.black,
      ),
      'Offline Board history must record a playable side for every action.',
    );

    final PieceColor side = actionSides.last;
    int steps = 0;
    for (
      int index = actionSides.length - 1;
      index >= 0 && actionSides[index] == side;
      index--
    ) {
      steps++;
    }
    assert(steps > 0);
    return steps;
  }
}
