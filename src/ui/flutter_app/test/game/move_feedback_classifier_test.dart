// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback.dart';
import 'package:sanmill/game_page/services/analysis/move_feedback_native_adapter.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

void main() {
  const MoveFeedbackRuleProfile standard = MoveFeedbackRuleProfile(
    standardStrategyCompatible: true,
    reusableMills: true,
    mayFly: true,
    perfectDatabaseCompatible: true,
    trapPatchCompatible: true,
  );

  MoveFeedbackInput input({
    required int loss,
    int best = 10,
    int playedRank = 2,
    int? runnerUp,
    int depth = 16,
    bool stable = true,
    bool coverage = true,
    bool allCandidatesLosing = false,
    bool causalResultForfeited = false,
    MoveFeedbackSource source = MoveFeedbackSource.engine,
    MoveFeedbackEvidence evidence = const MoveFeedbackEvidence(
      profile: standard,
    ),
  }) => MoveFeedbackInput(
    bestScore: best,
    playedScore: best - loss,
    playedRank: playedRank,
    legalRootActionCount: 8,
    depth: depth,
    runnerUpScore: runnerUp,
    searchStable: stable,
    candidateCoverageComplete: coverage,
    allCandidatesLosing: allCandidatesLosing,
    causalResultForfeited: causalResultForfeited,
    source: source,
    evidence: evidence,
  );

  group('score thresholds', () {
    test('exact database scores map the normalized negative bands', () {
      expect(
        MoveFeedbackClassifier.classify(
          input(loss: 4, source: MoveFeedbackSource.perfectDatabase),
        ).symbol,
        MoveFeedbackSymbol.dubious,
      );
      expect(
        MoveFeedbackClassifier.classify(
          input(loss: 8, source: MoveFeedbackSource.perfectDatabase),
        ).symbol,
        MoveFeedbackSymbol.mistake,
      );
      expect(
        MoveFeedbackClassifier.classify(
          input(loss: 15, source: MoveFeedbackSource.perfectDatabase),
        ).symbol,
        MoveFeedbackSymbol.blunder,
      );
    });

    test('short engine searches absorb only tiny MultiPV jitter', () {
      for (final int loss in <int>[1, 2, 3]) {
        expect(
          MoveFeedbackClassifier.classify(input(loss: loss)).symbol,
          MoveFeedbackSymbol.none,
          reason: 'An engine loss of $loss is inside the noise allowance.',
        );
      }
    });

    test('stable engine losses cross widened negative bands', () {
      for (final ({int loss, MoveFeedbackSymbol symbol}) sample
          in <({int loss, MoveFeedbackSymbol symbol})>[
            (loss: 7, symbol: MoveFeedbackSymbol.dubious),
            (loss: 11, symbol: MoveFeedbackSymbol.mistake),
            (loss: 18, symbol: MoveFeedbackSymbol.blunder),
          ]) {
        expect(
          MoveFeedbackClassifier.classify(input(loss: sample.loss)).symbol,
          sample.symbol,
        );
      }
    });

    test('shallow engine scores do not emit negative glyphs', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(loss: 25, depth: 2),
      );
      expect(result.symbol, MoveFeedbackSymbol.none);
      expect(result.reasons, contains(MoveFeedbackReason.insufficientEvidence));
    });

    test('partial MultiPV coverage still grades clear engine losses', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(loss: 18, stable: false, coverage: false),
      );
      expect(result.symbol, MoveFeedbackSymbol.blunder);
    });

    test('causal root blame grades a forfeited result as a mistake', () {
      // Without attribution the same scores stay a soft `?!`: the raw loss
      // (5) crosses the dubious band but the noise-reduced loss (2) cannot
      // reach the mistake band.
      final MoveFeedbackResult unattributed = MoveFeedbackClassifier.classify(
        input(best: 2, loss: 5),
      );
      expect(unattributed.symbol, MoveFeedbackSymbol.dubious);

      // The causal binary search proved the parent was still saveable and
      // this move started the never-recovered stretch: result-level
      // evidence upgrades the grade to `?` and names the forfeited draw.
      final MoveFeedbackResult attributed = MoveFeedbackClassifier.classify(
        input(best: 2, loss: 5, causalResultForfeited: true),
      );
      expect(attributed.symbol, MoveFeedbackSymbol.mistake);
      expect(
        attributed.reasons,
        contains(MoveFeedbackReason.losesDrawingResult),
      );

      // A large same-sign loss on the attributed root also grades `?`.
      final MoveFeedbackResult sameSign = MoveFeedbackClassifier.classify(
        input(best: 9, loss: 8, causalResultForfeited: true),
      );
      expect(sameSign.symbol, MoveFeedbackSymbol.mistake);
      expect(
        sameSign.reasons,
        contains(MoveFeedbackReason.decisiveMaterialLoss),
      );

      // Attribution never marks a move that kept the parent's result.
      final MoveFeedbackResult harmless = MoveFeedbackClassifier.classify(
        input(best: 2, loss: 1, causalResultForfeited: true),
      );
      expect(harmless.symbol, MoveFeedbackSymbol.none);
    });

    test('spoiling a drawish score into the negative is marked', () {
      final MoveFeedbackResult dubious = MoveFeedbackClassifier.classify(
        input(best: 0, loss: 4),
      );
      expect(dubious.symbol, MoveFeedbackSymbol.dubious);
      expect(dubious.reasons, contains(MoveFeedbackReason.losesDrawingResult));

      final MoveFeedbackResult mistake = MoveFeedbackClassifier.classify(
        input(best: 2, loss: 12),
      );
      expect(mistake.symbol, MoveFeedbackSymbol.mistake);
      expect(mistake.reasons, contains(MoveFeedbackReason.losesDrawingResult));
    });

    test('immediate-reward hints cannot grade a zero-loss move negatively', () {
      expect(
        MoveFeedbackClassifier.classify(
          input(
            loss: 0,
            evidence: const MoveFeedbackEvidence(
              missedOpportunity: true,
              profile: standard,
            ),
          ),
        ).symbol,
        MoveFeedbackSymbol.none,
      );
    });

    test('WDL drop has priority over score appearance', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(best: 80, loss: 80, playedRank: 1, runnerUp: -20),
      );
      expect(result.symbol, MoveFeedbackSymbol.blunder);
      expect(result.reasons, contains(MoveFeedbackReason.losesWinningResult));
    });

    test('every unfavorable WDL transition is a blunder', () {
      for (final ({int best, int played}) scores in <({int best, int played})>[
        (best: 80, played: 0),
        (best: 80, played: -80),
        (best: 0, played: -80),
      ]) {
        expect(
          MoveFeedbackClassifier.classify(
            input(best: scores.best, loss: scores.best - scores.played),
          ).symbol,
          MoveFeedbackSymbol.blunder,
        );
      }
    });

    test('greedy self-trap out of rough equality is a blunder', () {
      // No perfect database: the engine best is inside the noise strip
      // (-1.6P, 0) while the played move crashes into the ±80 terminal
      // band. This is the common "greedy capture, then sealed in" case.
      final MoveFeedbackResult crash = MoveFeedbackClassifier.classify(
        input(best: -2, loss: 83),
      );
      expect(crash.symbol, MoveFeedbackSymbol.blunder);
      expect(crash.reasons, contains(MoveFeedbackReason.losesDrawingResult));

      final MoveFeedbackResult sealed = MoveFeedbackClassifier.classify(
        input(
          best: 0,
          loss: 5,
          evidence: const MoveFeedbackEvidence(
            outcomeReasonAfter: 'loseNoLegalMoves',
            profile: standard,
          ),
        ),
      );
      expect(sealed.symbol, MoveFeedbackSymbol.blunder);
      expect(sealed.reasons, contains(MoveFeedbackReason.terminalRuleLoss));
    });

    test('sliding into the terminal band from a lost parent is unmarked', () {
      // The parent best was already at or below the mistake band: reaching
      // -80 only accelerates a lost cause, so the causative mark belongs to
      // the earlier root ply found by review attribution.
      final MoveFeedbackResult slide = MoveFeedbackClassifier.classify(
        input(best: -10, loss: 75),
      );
      expect(slide.symbol, MoveFeedbackSymbol.none);
      expect(slide.reasons, contains(MoveFeedbackReason.noSavingAlternative));

      final MoveFeedbackResult trapped = MoveFeedbackClassifier.classify(
        input(
          best: -10,
          loss: 5,
          evidence: const MoveFeedbackEvidence(
            outcomeReasonAfter: 'loseNoLegalMoves',
            profile: standard,
          ),
        ),
      );
      expect(trapped.symbol, MoveFeedbackSymbol.none);
      expect(
        trapped.reasons,
        containsAll(<MoveFeedbackReason>[
          MoveFeedbackReason.noSavingAlternative,
          MoveFeedbackReason.terminalRuleLoss,
        ]),
      );
    });

    test('already-worse parents do not get score-band negatives', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          best: -80,
          loss: 18,
          allCandidatesLosing: true,
          evidence: const MoveFeedbackEvidence(profile: standard),
        ),
      );
      expect(result.symbol, MoveFeedbackSymbol.none);
      expect(result.reasons, contains(MoveFeedbackReason.noSavingAlternative));
    });

    test('missing a faster win while still winning is only dubious', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          best: 2147483646,
          loss: 2147483559,
          evidence: const MoveFeedbackEvidence(
            phaseTransitionImpact: true,
            profile: standard,
          ),
        ),
      );

      expect(result.symbol, MoveFeedbackSymbol.dubious);
      expect(result.reasons, contains(MoveFeedbackReason.preservesResult));
      expect(
        result.reasons,
        contains(MoveFeedbackReason.requiresPreciseFollowUp),
      );
      expect(
        result.reasons,
        isNot(contains(MoveFeedbackReason.decisiveMaterialLoss)),
      );
    });
  });

  group('phase 1: no automatic positive glyphs', () {
    test('forced, equivalent, and routine moves stay unannotated', () {
      for (final MoveFeedbackEvidence evidence in <MoveFeedbackEvidence>[
        const MoveFeedbackEvidence(forced: true, profile: standard),
        const MoveFeedbackEvidence(equivalent: true, profile: standard),
        const MoveFeedbackEvidence(
          routineGain: true,
          formedMillWithReward: true,
          profile: standard,
        ),
      ]) {
        final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
          input(loss: 0, playedRank: 1, runnerUp: 0, evidence: evidence),
        );
        expect(result.symbol, MoveFeedbackSymbol.none);
      }
    });

    test('top engine candidates never receive ! / !! / !?', () {
      final List<MoveFeedbackInput> samples = <MoveFeedbackInput>[
        input(loss: 0, playedRank: 1, runnerUp: 20),
        input(loss: 0, playedRank: 1, runnerUp: 2),
        input(loss: 2, playedRank: 1, runnerUp: 0),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 10,
          evidence: const MoveFeedbackEvidence(
            initiativeSwing: true,
            mobilitySwing: true,
            mobilityDelta: 8,
            compensatedConcession: true,
            profile: standard,
          ),
        ),
      ];

      for (final MoveFeedbackInput sample in samples) {
        final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
          sample,
        );
        expect(result.symbol.isPositive, isFalse);
      }
    });

    test('ordinary near-best samples stay unannotated', () {
      final List<MoveFeedbackInput> samples = <MoveFeedbackInput>[
        input(loss: 0, playedRank: 1, runnerUp: 7),
        input(loss: 2),
        input(loss: 3),
        input(
          loss: 0,
          evidence: const MoveFeedbackEvidence(
            missedOpportunity: true,
            profile: standard,
          ),
        ),
      ];

      expect(
        samples
            .map(MoveFeedbackClassifier.classify)
            .every(
              (MoveFeedbackResult result) =>
                  result.symbol == MoveFeedbackSymbol.none,
            ),
        isTrue,
      );
    });

    test(
      'descriptive reasons remain for unannotated best and forced moves',
      () {
        expect(
          MoveFeedbackClassifier.classify(
            input(loss: 0, playedRank: 1, runnerUp: 0),
          ).reasons,
          contains(MoveFeedbackReason.regularBest),
        );
        expect(
          MoveFeedbackClassifier.classify(
            input(
              loss: 0,
              evidence: const MoveFeedbackEvidence(
                forced: true,
                profile: standard,
              ),
            ),
          ).reasons,
          contains(MoveFeedbackReason.forcedMove),
        );
      },
    );

    test('shallow search never invents a grade', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(loss: 0, playedRank: 1, runnerUp: 20, depth: 2),
      );
      expect(result.symbol, MoveFeedbackSymbol.none);
      expect(result.reasons, contains(MoveFeedbackReason.insufficientEvidence));
    });
  });

  test('complete turn keeps the most severe negative atomic result', () {
    final MoveFeedbackResult dubious = MoveFeedbackClassifier.classify(
      input(loss: 4, source: MoveFeedbackSource.perfectDatabase),
    );
    final MoveFeedbackResult mistake = MoveFeedbackClassifier.classify(
      input(loss: 8, source: MoveFeedbackSource.perfectDatabase),
    );
    expect(
      MoveFeedbackClassifier.aggregateTurn(<MoveFeedbackResult>[
        dubious,
        mistake,
      ]).symbol,
      MoveFeedbackSymbol.mistake,
    );
  });

  test('perfect database scores require complete legal-move coverage', () {
    const tgf.MillAnalysisReport complete = tgf.MillAnalysisReport(
      moves: <tgf.MillMoveAnalysis>[
        tgf.MillMoveAnalysis(mv: 'a7', outcome: 'win', value: 1, steps: 3),
        tgf.MillMoveAnalysis(mv: 'd6', outcome: 'draw', value: 0, steps: 4),
      ],
      traps: <String>[],
    );
    final MoveFeedbackExactScores exact = moveFeedbackExactScores(
      complete,
      playedMove: 'd6',
      legalActionCount: 2,
    )!;
    expect(exact.bestScore, 80);
    expect(exact.playedScore, 0);
    expect(exact.bestMoves, <String>{'a7'});

    expect(
      moveFeedbackExactScores(complete, playedMove: 'd6', legalActionCount: 3),
      isNull,
    );
  });

  test('heuristic perfect-database fallback is not treated as exact WDL', () {
    const tgf.MillAnalysisReport fallback = tgf.MillAnalysisReport(
      moves: <tgf.MillMoveAnalysis>[
        tgf.MillMoveAnalysis(
          mv: 'a7',
          outcome: 'advantage',
          value: 3,
          steps: -1,
        ),
        tgf.MillMoveAnalysis(
          mv: 'd6',
          outcome: 'disadvantage',
          value: -2,
          steps: -1,
        ),
      ],
      traps: <String>[],
    );

    expect(
      moveFeedbackExactScores(fallback, playedMove: 'd6', legalActionCount: 2),
      isNull,
    );
  });
}
