// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/import_export/pgn.dart';
import '../models/review_models.dart';

abstract final class ReviewNagMerge {
  /// Returns a newly parsed and serialized PGN; [sourcePgn] is never mutated.
  static String forExport(String sourcePgn, ReviewReport report) {
    if (!report.includeAnnotationsOnExport) {
      return sourcePgn;
    }
    final PgnGame<PgnNodeData> copy = PgnGame.parsePgn(sourcePgn);
    final List<PgnNodeData> mainline = copy.moves.mainline().toList();
    final Map<int, ReviewTurnBoundary> reviewedTurns =
        <int, ReviewTurnBoundary>{
          for (final ReviewTurnBoundary turn in report.turns)
            turn.groupIndex: turn,
        };
    for (int groupIndex = 0; groupIndex < mainline.length; groupIndex++) {
      final PgnNodeData move = mainline[groupIndex];
      final ReviewTurnBoundary? reviewedTurn = reviewedTurns[groupIndex];
      if (reviewedTurn == null ||
          move.san.toLowerCase() != reviewedTurn.san.toLowerCase()) {
        continue;
      }
      final List<int> original = List<int>.from(move.nags ?? const <int>[]);
      final bool hasOriginalQuality = original.any(_isQualityNag);
      final bool hasUserOverride = report.userNagOverrides.containsKey(
        groupIndex,
      );

      if (hasUserOverride) {
        original.removeWhere(_isQualityNag);
        final int? override = report.userNagOverrides[groupIndex];
        if (override != null) {
          original.insert(0, override);
        }
      } else if (!hasOriginalQuality) {
        final int? automatic = automaticNagForGrade(
          report.gradeForTurn(groupIndex),
        );
        if (automatic != null) {
          original.insert(0, automatic);
        }
      }
      move.nags = original.isEmpty ? null : original;
    }
    return copy.makePgn();
  }

  static bool _isQualityNag(int nag) => nag >= 1 && nag <= 6;
}
