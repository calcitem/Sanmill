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
    bool stable = true,
    bool coverage = true,
    bool allCandidatesLosing = false,
    bool hasCalmerEquivalent = false,
    int? playedTrapScore,
    int? calmTrapScore,
    int? opponentSafeReplies,
    int? naturalRepliesLosing,
    MoveFeedbackSource source = MoveFeedbackSource.engine,
    bool brilliantVerificationComplete = false,
    Set<MoveFeedbackReason> strategic = const <MoveFeedbackReason>{},
    MoveFeedbackEvidence evidence = const MoveFeedbackEvidence(
      profile: standard,
    ),
  }) => MoveFeedbackInput(
    bestScore: best,
    playedScore: best - loss,
    playedRank: playedRank,
    legalRootActionCount: 8,
    depth: 16,
    runnerUpScore: runnerUp,
    searchStable: stable,
    candidateCoverageComplete: coverage,
    allCandidatesLosing: allCandidatesLosing,
    hasCalmerEquivalent: hasCalmerEquivalent,
    playedTrapScore: playedTrapScore,
    calmTrapScore: calmTrapScore,
    opponentSafeReplies: opponentSafeReplies,
    naturalRepliesLosing: naturalRepliesLosing,
    source: source,
    brilliantVerificationComplete: brilliantVerificationComplete,
    evidence: evidence,
    strategicReasons: strategic,
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

    test('short engine searches absorb ordinary MultiPV score noise', () {
      for (final int loss in <int>[4, 8, 10]) {
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
            (loss: 14, symbol: MoveFeedbackSymbol.dubious),
            (loss: 18, symbol: MoveFeedbackSymbol.mistake),
            (loss: 25, symbol: MoveFeedbackSymbol.blunder),
          ]) {
        expect(
          MoveFeedbackClassifier.classify(input(loss: sample.loss)).symbol,
          sample.symbol,
        );
      }
    });

    test('unstable engine scores do not emit negative glyphs', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(loss: 25, stable: false),
      );
      expect(result.symbol, MoveFeedbackSymbol.none);
      expect(result.reasons, contains(MoveFeedbackReason.insufficientEvidence));
    });

    test('immediate-reward hints cannot grade a zero-loss move negatively', () {
      for (final MoveFeedbackEvidence evidence in <MoveFeedbackEvidence>[
        const MoveFeedbackEvidence(missedOpportunity: true, profile: standard),
        const MoveFeedbackEvidence(
          missedOpportunity: true,
          deferredOpportunity: true,
          profile: standard,
        ),
      ]) {
        expect(
          MoveFeedbackClassifier.classify(
            input(loss: 0, evidence: evidence),
          ).symbol,
          MoveFeedbackSymbol.none,
        );
      }
    });

    test('WDL drop has priority over tactical appearance', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          best: 80,
          loss: 80,
          playedRank: 1,
          runnerUp: -20,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.sacrificesMillForHigherOrderThreat,
          },
          evidence: const MoveFeedbackEvidence(
            compensatedConcession: true,
            profile: standard,
          ),
        ),
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

    test('already-lost positions need verified worsening for blunder', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          best: -80,
          loss: 18,
          allCandidatesLosing: true,
          evidence: const MoveFeedbackEvidence(profile: standard),
        ),
      );
      expect(result.symbol, MoveFeedbackSymbol.mistake);
    });
  });

  group('positive suppression and qualification', () {
    test('forced, equivalent, and routine moves get no positive glyph', () {
      for (final MoveFeedbackEvidence evidence in <MoveFeedbackEvidence>[
        const MoveFeedbackEvidence(forced: true, profile: standard),
        const MoveFeedbackEvidence(equivalent: true, profile: standard),
        const MoveFeedbackEvidence(routineGain: true, profile: standard),
      ]) {
        final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
          input(
            loss: 0,
            playedRank: 1,
            runnerUp: 0,
            strategic: const <MoveFeedbackReason>{
              MoveFeedbackReason.createsReusableMill,
            },
            evidence: evidence,
          ),
        );
        expect(result.symbol, MoveFeedbackSymbol.none);
      }
    });

    test('brilliant requires a stable top move and non-routine mechanism', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 2,
          brilliantVerificationComplete: true,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.sacrificesMillForHigherOrderThreat,
          },
          evidence: const MoveFeedbackEvidence(
            compensatedConcession: true,
            profile: standard,
          ),
        ),
      );
      expect(result.symbol, MoveFeedbackSymbol.brilliant);
    });

    test(
      'brilliant is withheld until the expensive verification completes',
      () {
        final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
          input(
            loss: 0,
            playedRank: 1,
            runnerUp: 2,
            strategic: const <MoveFeedbackReason>{
              MoveFeedbackReason.sacrificesMillForHigherOrderThreat,
            },
            evidence: const MoveFeedbackEvidence(
              compensatedConcession: true,
              profile: standard,
            ),
          ),
        );
        expect(result.symbol, MoveFeedbackSymbol.good);
      },
    );

    test('good requires a stable strategic contribution', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 6,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.createsHerdingNet,
          },
        ),
      );
      expect(result.symbol, MoveFeedbackSymbol.good);
    });

    test('cheap position flags do not qualify a move for a positive glyph', () {
      final List<MoveFeedbackInput> ordinaryMoves = <MoveFeedbackInput>[
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 0,
          evidence: const MoveFeedbackEvidence(
            initiativeSwing: true,
            profile: standard,
          ),
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 0,
          evidence: const MoveFeedbackEvidence(
            mobilitySwing: true,
            mobilityDelta: 3,
            profile: standard,
          ),
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 0,
          evidence: const MoveFeedbackEvidence(
            drawResourceImpact: true,
            profile: standard,
          ),
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 0,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.ruleStrategyUnavailable,
          },
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 0,
          evidence: const MoveFeedbackEvidence(
            initiativeSwing: true,
            mobilitySwing: true,
            mobilityDelta: 3,
            profile: standard,
          ),
        ),
      ];

      final List<MoveFeedbackSymbol> symbols = ordinaryMoves
          .map(MoveFeedbackClassifier.classify)
          .map((MoveFeedbackResult result) => result.symbol)
          .toList(growable: false);
      expect(symbols, everyElement(MoveFeedbackSymbol.none));
    });

    test('ordinary evidence samples keep no-symbol as the default', () {
      final List<MoveFeedbackInput> samples = <MoveFeedbackInput>[
        input(loss: 0, playedRank: 1, runnerUp: 7),
        input(loss: 2),
        input(loss: 4),
        input(loss: 8),
        input(loss: 10),
        input(
          loss: 0,
          evidence: const MoveFeedbackEvidence(
            missedOpportunity: true,
            profile: standard,
          ),
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 1,
          evidence: const MoveFeedbackEvidence(
            initiativeSwing: true,
            mobilitySwing: true,
            mobilityDelta: 2,
            profile: standard,
          ),
        ),
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 1,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.ruleStrategyUnavailable,
          },
        ),
      ];

      final int unannotated = samples
          .map(MoveFeedbackClassifier.classify)
          .where(
            (MoveFeedbackResult result) =>
                result.symbol == MoveFeedbackSymbol.none,
          )
          .length;
      expect(unannotated, samples.length);
    });

    test('interesting requires a sound practical-chances proof', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          loss: 2,
          hasCalmerEquivalent: true,
          playedTrapScore: 80,
          calmTrapScore: 46,
        ),
      );
      expect(result.symbol, MoveFeedbackSymbol.interesting);
      expect(
        result.reasons,
        contains(MoveFeedbackReason.createsPracticalChances),
      );
    });

    test('unstable search never emits a positive glyph', () {
      final MoveFeedbackResult result = MoveFeedbackClassifier.classify(
        input(
          loss: 0,
          playedRank: 1,
          runnerUp: 2,
          stable: false,
          strategic: const <MoveFeedbackReason>{
            MoveFeedbackReason.sacrificesMillForHigherOrderThreat,
          },
          evidence: const MoveFeedbackEvidence(
            compensatedConcession: true,
            profile: standard,
          ),
        ),
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

  test('native fact mapping does not invent advanced strategy reasons', () {
    final Set<MoveFeedbackReason> reasons = moveFeedbackStrategicReasons(
      const MoveFeedbackEvidence(
        createdOpportunity: true,
        selectedCaptureTarget: true,
        opponentEnteredFlying: true,
        profile: standard,
      ),
    );

    expect(
      reasons,
      isNot(contains(MoveFeedbackReason.selectsCriticalCaptureTarget)),
    );
    expect(reasons, isNot(contains(MoveFeedbackReason.createsReusableMill)));
    expect(
      reasons,
      isNot(contains(MoveFeedbackReason.avoidsPrematureFlyingTransition)),
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
}
