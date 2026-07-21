// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_causal_attribution.dart';

void main() {
  ReviewActionEvaluation action({
    required int atomicIndex,
    required ReviewSide side,
    required int bestScore,
    required int playedScore,
    int? automaticNag,
    List<MoveFeedbackReason> reasons = const <MoveFeedbackReason>[],
  }) {
    final int loss = bestScore > playedScore ? bestScore - playedScore : 0;
    return ReviewActionEvaluation(
      atomicIndex: atomicIndex,
      groupIndex: atomicIndex,
      move: 'm$atomicIndex',
      side: side,
      isHumanMove: true,
      legalRootActionCount: 8,
      bestScore: bestScore,
      playedScore: playedScore,
      loss: loss,
      grade: ReviewGrade.good,
      profile: ReviewProfile.quick,
      candidates: const <ReviewCandidate>[],
      automaticNag: automaticNag,
      feedbackReasons: reasons,
    );
  }

  test(
    'binary search finds the last saveable index in O(log n) probes',
    () async {
      final List<int> indices = <int>[0, 2, 4, 6, 8, 10];
      final Set<int> saveable = <int>{0, 2, 4};
      int probes = 0;
      final int? last = await ReviewCausalAttribution.lastSaveableIndex(
        indices: indices,
        isSaveable: (int index) async {
          probes++;
          return saveable.contains(index);
        },
      );
      expect(last, 4);
      expect(probes, lessThan(indices.length));
    },
  );

  test('root search keeps walking earlier past forced best moves', () async {
    final List<int> indices = <int>[0, 2, 4, 6];
    // 0 saveable + spoiling rank-2 move (true root)
    // 2 saveable but played rank-1 (forced best, not root)
    // 4/6 lost
    final Map<int, BlameProbe> probes = <int, BlameProbe>{
      0: const BlameProbe(
        bestScore: 4,
        playedScore: -6,
        playedRank: 3,
        source: MoveFeedbackSource.engine,
      ),
      2: const BlameProbe(
        bestScore: 1,
        playedScore: 1,
        playedRank: 1,
        source: MoveFeedbackSource.engine,
      ),
      4: const BlameProbe(
        bestScore: -10,
        playedScore: -12,
        playedRank: 2,
        source: MoveFeedbackSource.engine,
      ),
      6: const BlameProbe(
        bestScore: -15,
        playedScore: -15,
        playedRank: 1,
        source: MoveFeedbackSource.engine,
      ),
    };

    final int? root = await ReviewCausalAttribution.findRootBlameIndex(
      indices: indices,
      isSaveable: (int index) async => probes[index]!.bestScore >= 0,
      probe: (int index) async => probes[index]!,
    );
    expect(root, 0);
  });

  test('subsequent negatives after a blame are suppressed until recovery', () {
    final List<ReviewActionEvaluation> actions = <ReviewActionEvaluation>[
      action(
        atomicIndex: 0,
        side: ReviewSide.white,
        bestScore: 4,
        playedScore: -8,
        automaticNag: MoveFeedbackSymbol.mistake.nag,
      ),
      action(
        atomicIndex: 1,
        side: ReviewSide.black,
        bestScore: 6,
        playedScore: 6,
      ),
      action(
        atomicIndex: 2,
        side: ReviewSide.white,
        bestScore: -10,
        playedScore: -12,
        automaticNag: MoveFeedbackSymbol.blunder.nag,
      ),
      action(
        atomicIndex: 3,
        side: ReviewSide.white,
        bestScore: -14,
        playedScore: -14,
        automaticNag: MoveFeedbackSymbol.dubious.nag,
      ),
      action(
        atomicIndex: 4,
        side: ReviewSide.white,
        bestScore: 2,
        playedScore: 0,
        automaticNag: MoveFeedbackSymbol.dubious.nag,
      ),
    ];

    final List<ReviewActionEvaluation> suppressed =
        ReviewCausalAttribution.suppressSubsequentNegatives(
          actions: actions,
          side: ReviewSide.white,
          blameAtomicIndex: 0,
        );

    expect(suppressed[0].automaticNag, MoveFeedbackSymbol.mistake.nag);
    expect(suppressed[2].automaticNag, isNull);
    expect(
      suppressed[2].feedbackReasons,
      contains(MoveFeedbackReason.noSavingAlternative),
    );
    expect(suppressed[3].automaticNag, isNull);
    // Recovered bestScore >= 0 stops suppression; later mark remains.
    expect(suppressed[4].automaticNag, MoveFeedbackSymbol.dubious.nag);
  });

  test('trailing sweep keeps only the first negative nag per side', () {
    final List<ReviewActionEvaluation> actions = <ReviewActionEvaluation>[
      action(
        atomicIndex: 0,
        side: ReviewSide.white,
        bestScore: -9,
        playedScore: -12,
        automaticNag: MoveFeedbackSymbol.mistake.nag,
      ),
      action(
        atomicIndex: 1,
        side: ReviewSide.white,
        bestScore: -11,
        playedScore: -14,
        automaticNag: MoveFeedbackSymbol.blunder.nag,
      ),
    ];
    final List<ReviewActionEvaluation> suppressed =
        ReviewCausalAttribution.suppressTrailingNegativesAfterFirstBlame(
          actions,
        );
    expect(suppressed[0].automaticNag, MoveFeedbackSymbol.mistake.nag);
    expect(suppressed[1].automaticNag, isNull);
  });
}
