// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/analysis/move_feedback.dart';
import '../models/review_models.dart';

/// Two-phase causal attribution helpers for game review.
///
/// 1. Shallow scores locate where a side first looks clearly worse.
/// 2. Deep / perfect-database probes binary-search the last still-saveable
///    position, then walk earlier while the candidate is only a forced delay.
/// 3. After a root blame is marked, later same-side negatives in the already-
///    decided stretch are suppressed until the side recovers.
abstract final class ReviewCausalAttribution {
  /// Shallow disadvantage: best alternative already looks clearly worse.
  static int disadvantageThreshold([
    int pieceValue = MoveQualityThresholds.defaultPieceValue,
  ]) => -MoveQualityThresholds.mistakeMinimum(pieceValue);

  /// First atomic index on [side] at or after [fromAtomicIndex] whose shallow
  /// [bestScore] is at or below [threshold].
  static int? firstDisadvantageAnchor(
    List<ReviewActionEvaluation> actions,
    ReviewSide side, {
    int fromAtomicIndex = 0,
    int? threshold,
  }) {
    final int cut = threshold ?? disadvantageThreshold();
    for (final ReviewActionEvaluation action in actions) {
      if (action.side != side || action.atomicIndex < fromAtomicIndex) {
        continue;
      }
      if (action.bestScore <= cut) {
        return action.atomicIndex;
      }
    }
    return null;
  }

  /// Same-side atomic indices from [fromAtomicIndex] through [collapseInclusive].
  static List<int> sideIndicesThrough(
    List<ReviewActionEvaluation> actions,
    ReviewSide side,
    int collapseInclusive, {
    int fromAtomicIndex = 0,
  }) {
    return actions
        .where(
          (ReviewActionEvaluation action) =>
              action.side == side &&
              action.atomicIndex >= fromAtomicIndex &&
              action.atomicIndex <= collapseInclusive,
        )
        .map((ReviewActionEvaluation action) => action.atomicIndex)
        .toList(growable: false);
  }

  /// Binary-search the last index in sorted [indices] where [isSaveable] is
  /// true. [isSaveable] must be monotonic: once false, later indices stay false.
  static Future<int?> lastSaveableIndex({
    required List<int> indices,
    required Future<bool> Function(int atomicIndex) isSaveable,
  }) async {
    if (indices.isEmpty) {
      return null;
    }
    final bool lastOk = await isSaveable(indices.last);
    if (lastOk) {
      return null;
    }
    final bool firstOk = await isSaveable(indices.first);
    if (!firstOk) {
      return null;
    }

    int lo = 0; // known saveable
    int hi = indices.length - 1; // known lost
    while (hi - lo > 1) {
      final int mid = (lo + hi) >> 1;
      if (await isSaveable(indices[mid])) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return indices[lo];
  }

  /// Walk earlier with binary search until the candidate is a true root:
  /// a still-saveable parent where the played move uniquely rejected a real
  /// escape. Forced best moves and delay-only alternatives are not roots.
  static Future<int?> findRootBlameIndex({
    required List<int> indices,
    required Future<bool> Function(int atomicIndex) isSaveable,
    required Future<BlameProbe> Function(int atomicIndex) probe,
  }) async {
    int end = indices.length;
    while (end >= 1) {
      final List<int> slice = indices.sublist(0, end);
      if (slice.length == 1) {
        final int only = slice.first;
        if (!await isSaveable(only)) {
          return null;
        }
        final BlameProbe snapshot = await probe(only);
        return isTrueRootBlame(snapshot) ? only : null;
      }
      final int? candidate = await lastSaveableIndex(
        indices: slice,
        isSaveable: isSaveable,
      );
      if (candidate == null) {
        return null;
      }
      final BlameProbe snapshot = await probe(candidate);
      if (isTrueRootBlame(snapshot)) {
        return candidate;
      }
      final int position = slice.indexOf(candidate);
      if (position <= 0) {
        return null;
      }
      // Candidate was forced / delay-only: keep searching strictly earlier.
      end = position;
    }
    return null;
  }

  /// A real escape must be non-negative. A merely less-negative best score only
  /// delays the same disadvantage and is not a root save.
  static bool positionIsSaveable({
    required int bestScore,
    required MoveFeedbackSource source,
  }) {
    assert(
      source == MoveFeedbackSource.engine ||
          source == MoveFeedbackSource.perfectDatabase,
    );
    return bestScore >= 0;
  }

  /// True root: saveable parent, played move not forced-best, uniquely worse.
  static bool isTrueRootBlame(BlameProbe probe) {
    if (!positionIsSaveable(bestScore: probe.bestScore, source: probe.source)) {
      return false;
    }
    // Playing the engine/DB best cannot be the causative mistake.
    if (probe.playedRank <= 1) {
      return false;
    }
    return playedSpoilsSaveableParent(
      bestScore: probe.bestScore,
      playedScore: probe.playedScore,
      pieceValue: probe.pieceValue,
    );
  }

  static bool playedSpoilsSaveableParent({
    required int bestScore,
    required int playedScore,
    required int pieceValue,
  }) {
    if (bestScore < 0) {
      return false;
    }
    final int loss = bestScore > playedScore ? bestScore - playedScore : 0;
    if (playedScore < 0 &&
        loss >= MoveQualityThresholds.dubiousMinimum(pieceValue)) {
      return true;
    }
    return loss >= MoveQualityThresholds.mistakeMinimum(pieceValue);
  }

  /// Clear automatic negative marks at the given atomic indices.
  static List<ReviewActionEvaluation> clearNegativesAt(
    List<ReviewActionEvaluation> actions,
    Iterable<int> atomicIndices,
  ) {
    final Set<int> targets = atomicIndices.toSet();
    return actions
        .map((ReviewActionEvaluation action) {
          if (!targets.contains(action.atomicIndex) ||
              !_isNegativeNag(action.automaticNag)) {
            return action;
          }
          return _withClearedAutomaticMark(action);
        })
        .toList(growable: false);
  }

  /// After a root blame, drop later same-side negative NAGs until the side's
  /// shallow best score recovers above zero (new episode may be marked again).
  static List<ReviewActionEvaluation> suppressSubsequentNegatives({
    required List<ReviewActionEvaluation> actions,
    required ReviewSide side,
    required int blameAtomicIndex,
  }) {
    final List<ReviewActionEvaluation> updated =
        List<ReviewActionEvaluation>.from(actions);
    bool pastBlame = false;
    for (int i = 0; i < updated.length; i++) {
      final ReviewActionEvaluation action = updated[i];
      if (action.side != side) {
        continue;
      }
      if (action.atomicIndex == blameAtomicIndex) {
        pastBlame = true;
        continue;
      }
      if (!pastBlame || action.atomicIndex < blameAtomicIndex) {
        continue;
      }
      if (action.bestScore >= 0) {
        // Recovered equality/advantage: later independent mistakes may mark.
        break;
      }
      if (!_isNegativeNag(action.automaticNag)) {
        if (action.feedbackReasons.contains(
          MoveFeedbackReason.noSavingAlternative,
        )) {
          continue;
        }
        updated[i] = _withClearedAutomaticMark(action);
        continue;
      }
      updated[i] = _withClearedAutomaticMark(action);
    }
    return updated;
  }

  /// Final sweep: keep only the first negative automatic NAG per side.
  static List<ReviewActionEvaluation> suppressTrailingNegativesAfterFirstBlame(
    List<ReviewActionEvaluation> actions,
  ) {
    List<ReviewActionEvaluation> updated = actions;
    for (final ReviewSide side in ReviewSide.values) {
      final int blameIndex = updated.indexWhere(
        (ReviewActionEvaluation action) =>
            action.side == side && _isNegativeNag(action.automaticNag),
      );
      if (blameIndex < 0) {
        continue;
      }
      updated = suppressSubsequentNegatives(
        actions: updated,
        side: side,
        blameAtomicIndex: updated[blameIndex].atomicIndex,
      );
    }
    return updated;
  }

  static bool _isNegativeNag(int? nag) => switch (nag) {
    2 || 4 || 6 => true, // ? / ?? / ?!
    _ => false,
  };

  static ReviewActionEvaluation _withClearedAutomaticMark(
    ReviewActionEvaluation action,
  ) {
    return ReviewActionEvaluation(
      atomicIndex: action.atomicIndex,
      groupIndex: action.groupIndex,
      move: action.move,
      side: action.side,
      isHumanMove: action.isHumanMove,
      legalRootActionCount: action.legalRootActionCount,
      bestScore: action.bestScore,
      playedScore: action.playedScore,
      loss: action.loss,
      grade: action.loss <= MoveQualityThresholds.bestMaximum()
          ? ReviewGrade.best
          : ReviewGrade.good,
      profile: action.profile,
      candidates: action.candidates,
      automaticNag: null,
      feedbackReasons: const <MoveFeedbackReason>[
        MoveFeedbackReason.noSavingAlternative,
      ],
    );
  }
}

/// Compact probe facts needed for root-blame decisions.
class BlameProbe {
  const BlameProbe({
    required this.bestScore,
    required this.playedScore,
    required this.playedRank,
    required this.source,
    this.pieceValue = MoveQualityThresholds.defaultPieceValue,
  });

  final int bestScore;
  final int playedScore;
  final int playedRank;
  final MoveFeedbackSource source;
  final int pieceValue;
}
