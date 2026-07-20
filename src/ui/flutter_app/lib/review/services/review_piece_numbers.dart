// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../games/mill/mill_action_codec.dart';
import '../models/review_models.dart';
import 'review_analysis_service.dart' show splitMillSan;

abstract final class ReviewPieceNumbers {
  static Map<int, int> forTurn(
    Iterable<ReviewTurnBoundary> turns,
    int targetGroupIndex,
  ) {
    final Map<int, int> byNode = <int, int>{};
    int lastPlacedNumber = 0;

    for (final ReviewTurnBoundary turn in turns) {
      for (final String move in splitMillSan(turn.san)) {
        final action = MillActionCodec.tgfActionFromMoveString(move);
        assert(
          action != null,
          'Review move $move must use valid Mill notation.',
        );
        if (action == null) {
          continue;
        }

        if (move.startsWith('x')) {
          byNode.remove(action.toNode);
        } else if (move.contains('-')) {
          final int? number = byNode.remove(action.fromNode);
          byNode.remove(action.toNode);
          if (number != null) {
            byNode[action.toNode] = number;
          }
        } else {
          lastPlacedNumber++;
          byNode[action.toNode] = lastPlacedNumber;
        }
      }
      if (turn.groupIndex == targetGroupIndex) {
        return Map<int, int>.unmodifiable(byNode);
      }
    }

    assert(false, 'Review turn $targetGroupIndex must exist in the report.');
    return const <int, int>{};
  }
}
