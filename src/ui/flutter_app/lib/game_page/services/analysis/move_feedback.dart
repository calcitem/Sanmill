// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Conventional PGN move-quality glyphs plus an unannotated result.
///
/// Phase 1 automatic classification emits only [none], [dubious], [mistake],
/// and [blunder]. Positive glyphs remain for manual annotations and older
/// persisted reports; the classifier never invents them.
enum MoveFeedbackSymbol {
  none(null, ''),
  brilliant(3, '!!'),
  good(1, '!'),
  interesting(5, '!?'),
  dubious(6, '?!'),
  mistake(2, '?'),
  blunder(4, '??');

  const MoveFeedbackSymbol(this.nag, this.glyph);

  final int? nag;
  final String glyph;

  bool get isNegative => switch (this) {
    MoveFeedbackSymbol.dubious ||
    MoveFeedbackSymbol.mistake ||
    MoveFeedbackSymbol.blunder => true,
    _ => false,
  };

  bool get isPositive => switch (this) {
    MoveFeedbackSymbol.brilliant ||
    MoveFeedbackSymbol.good ||
    MoveFeedbackSymbol.interesting => true,
    _ => false,
  };
}

/// Stable, persistence-safe reasons. UI code owns localization.
///
/// Phase 1 only *produces* a small factual subset. Legacy strategic values
/// remain so older review reports continue to deserialize and display.
enum MoveFeedbackReason {
  regularBest,
  forcedMove,
  onlyCorrectMove,
  equivalentChoice,
  insufficientEvidence,
  engineEstimate,
  perfectDatabase,
  preservesResult,
  losesWinningResult,
  losesDrawingResult,
  decisiveMaterialLoss,
  missesImmediateRuleReward,
  directRuleReward,
  routineConversion,
  naturalConversion,
  selectsCriticalCaptureTarget,
  allowsOpponentRuleReward,
  selfBlock,
  preservesInitiative,
  forcesResponses,
  avoidsDeadPlacement,
  improvesTopologyControl,
  preservesMobility,
  createsHerdingNet,
  escapesHerding,
  createsReusableMill,
  createsEntwinedMills,
  createsIndependentMills,
  createsFeeder,
  nullifiesOpponentMill,
  recognizesRedundantMill,
  allowsConstrainedMill,
  abandonsMillForMobility,
  sacrificesMillForHigherOrderThreat,
  avoidsPrematureFlyingTransition,
  usesFlyingTransition,
  createsZugzwang,
  preservesDrawCycle,
  breaksOpponentDrawResource,
  createsPracticalChances,
  requiresPreciseFollowUp,
  mobilityLoss,
  phaseTransitionLoss,
  terminalRuleLoss,
  compensatedConcession,
  defersOpportunity,
  replacesOpportunity,
  ruleStrategyUnavailable,
  noSavingAlternative,
}

enum MoveFeedbackSource { engine, perfectDatabase }

enum MoveFeedbackConfidence { low, medium, high }

/// Shared score bands for review and on-demand feedback.
abstract final class MoveQualityThresholds {
  static const int defaultPieceValue = 5;
  static const int engineTerminalScore = 80;

  static int bestMaximum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 0.2).round();

  static int acceptableMaximum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 0.6).round();

  static int dubiousMinimum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 0.8).ceil();

  static int dubiousMaximum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 1.4).floor();

  static int mistakeMinimum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 1.6).ceil();

  static int mistakeMaximum([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 2.8).floor();

  static int blunderMinimum([int pieceValue = defaultPieceValue]) =>
      pieceValue * 3;

  /// Minimum completed search depth before engine MultiPV scores may grade.
  static const int minimumGradingDepth = 4;

  /// Allowance for short, time-bounded engine MultiPV jitter.
  ///
  /// Kept near one-third of a piece so equality-to-worse swings around a
  /// drawish score remain visible, while tiny 1–2 cp noise stays silent.
  /// Exact database scores continue to use the normalized bands directly.
  static int engineNoiseAllowance([int pieceValue = defaultPieceValue]) =>
      (pieceValue * 0.6).ceil();
}

enum MoveFeedbackWdl { loss, draw, win }

@immutable
class MoveFeedbackRuleProfile {
  const MoveFeedbackRuleProfile({
    required this.standardStrategyCompatible,
    required this.reusableMills,
    required this.mayFly,
    required this.perfectDatabaseCompatible,
    required this.trapPatchCompatible,
  });

  const MoveFeedbackRuleProfile.unknown()
    : standardStrategyCompatible = false,
      reusableMills = false,
      mayFly = false,
      perfectDatabaseCompatible = false,
      trapPatchCompatible = false;

  final bool standardStrategyCompatible;
  final bool reusableMills;
  final bool mayFly;
  final bool perfectDatabaseCompatible;
  final bool trapPatchCompatible;
}

/// Rule facts only; no glyph or localized prose is stored here.
@immutable
class MoveFeedbackEvidence {
  const MoveFeedbackEvidence({
    this.forced = false,
    this.equivalent = false,
    this.routineGain = false,
    this.createdOpportunity = false,
    this.missedOpportunity = false,
    this.deferredOpportunity = false,
    this.replacedOpportunity = false,
    this.compensatedConcession = false,
    this.initiativeSwing = false,
    this.mobilitySwing = false,
    this.phaseTransitionImpact = false,
    this.drawResourceImpact = false,
    this.formedMillWithReward = false,
    this.actualSpecialCapture = false,
    this.selectedCaptureTarget = false,
    this.enteredFlying = false,
    this.opponentEnteredFlying = false,
    this.moverBoardLoss = 0,
    this.opponentBoardLoss = 0,
    this.moverHandLoss = 0,
    this.opponentHandLoss = 0,
    this.removalRightsCreated = 0,
    this.legalRepliesAfter = 0,
    this.mobilityDelta = 0,
    this.outcomeReasonAfter = 'ongoing',
    this.profile = const MoveFeedbackRuleProfile.unknown(),
  });

  final bool forced;
  final bool equivalent;
  final bool routineGain;
  final bool createdOpportunity;
  final bool missedOpportunity;
  final bool deferredOpportunity;
  final bool replacedOpportunity;
  final bool compensatedConcession;
  final bool initiativeSwing;
  final bool mobilitySwing;
  final bool phaseTransitionImpact;
  final bool drawResourceImpact;
  final bool formedMillWithReward;
  final bool actualSpecialCapture;
  final bool selectedCaptureTarget;
  final bool enteredFlying;
  final bool opponentEnteredFlying;
  final int moverBoardLoss;
  final int opponentBoardLoss;
  final int moverHandLoss;
  final int opponentHandLoss;
  final int removalRightsCreated;
  final int legalRepliesAfter;
  final int mobilityDelta;
  final String outcomeReasonAfter;
  final MoveFeedbackRuleProfile profile;
}

@immutable
class MoveFeedbackInput {
  const MoveFeedbackInput({
    required this.bestScore,
    required this.playedScore,
    required this.playedRank,
    required this.legalRootActionCount,
    required this.depth,
    required this.evidence,
    this.runnerUpScore,
    this.source = MoveFeedbackSource.engine,
    this.searchStable = true,
    this.candidateCoverageComplete = true,
    this.allCandidatesLosing = false,
    this.causalResultForfeited = false,
    this.pieceValue = MoveQualityThresholds.defaultPieceValue,
  });

  final int bestScore;
  final int playedScore;
  final int playedRank;
  final int legalRootActionCount;
  final int depth;
  final int? runnerUpScore;
  final MoveFeedbackSource source;
  final bool searchStable;
  final bool candidateCoverageComplete;
  final bool allCandidatesLosing;

  /// Set by review causal attribution when a deep binary search proved the
  /// parent still had a saving alternative and this move started the losing
  /// stretch. Result forfeiture outranks per-move score bands.
  final bool causalResultForfeited;
  final int pieceValue;
  final MoveFeedbackEvidence evidence;

  int get loss {
    final int difference = bestScore - playedScore;
    return difference > 0 ? difference : 0;
  }
}

@immutable
class MoveFeedbackResult {
  const MoveFeedbackResult({
    required this.symbol,
    required this.reasons,
    required this.bestScore,
    required this.playedScore,
    required this.depth,
    required this.source,
    required this.confidence,
    this.bestMove,
    this.principalVariation = const <String>[],
  });

  final MoveFeedbackSymbol symbol;
  final List<MoveFeedbackReason> reasons;
  final int bestScore;
  final int playedScore;
  final int depth;
  final MoveFeedbackSource source;
  final MoveFeedbackConfidence confidence;
  final String? bestMove;
  final List<String> principalVariation;

  int get loss => (bestScore - playedScore).clamp(0, 1 << 30);

  MoveFeedbackResult copyWith({
    String? bestMove,
    List<String>? principalVariation,
  }) => MoveFeedbackResult(
    symbol: symbol,
    reasons: reasons,
    bestScore: bestScore,
    playedScore: playedScore,
    depth: depth,
    source: source,
    confidence: confidence,
    bestMove: bestMove ?? this.bestMove,
    principalVariation: principalVariation ?? this.principalVariation,
  );
}

/// Phase 1 score-and-result classifier with causal severity limits.
///
/// Automatic NAGs require that the played move uniquely worsens the result
/// or spoils a still-saveable parent. Choosing among already-worse moves is
/// not marked — full-game review attributes those to an earlier causative ply.
/// Never invents `!` / `!!` / `!?`.
abstract final class MoveFeedbackClassifier {
  static MoveFeedbackResult classify(MoveFeedbackInput input) {
    final int classifiedLoss = _classifiedLoss(input);
    final MoveFeedbackWdl bestWdl = _wdl(input.bestScore);
    final MoveFeedbackWdl playedWdl = _wdl(input.playedScore);
    final bool scoreEvidenceReliable = _scoreEvidenceReliable(input);
    final bool resultDrop =
        scoreEvidenceReliable && playedWdl.index < bestWdl.index;
    final bool preservesDeterminedWin =
        scoreEvidenceReliable &&
        bestWdl == MoveFeedbackWdl.win &&
        playedWdl == MoveFeedbackWdl.win;
    // A non-negative best alternative means the parent was still saveable /
    // equal; score-band marks are only meaningful in that case.
    final bool hasNonNegativeAlternative =
        scoreEvidenceReliable && input.bestScore >= 0;
    final bool topCandidate =
        input.playedRank == 1 &&
        input.loss <= MoveQualityThresholds.bestMaximum(input.pieceValue);
    // A parent that was already clearly worse (best at or below the mistake
    // band) cannot host the causative mistake: sliding from -20 into the ±80
    // terminal band, or walking into a forced self-trap there, only
    // accelerates a lost cause. Attribution points at the earlier root ply.
    // The (-1.6P, 0) noise strip stays markable so a greedy capture that
    // self-traps out of rough equality is still a blunder without any
    // perfect database.
    final bool parentAlreadyLosing =
        scoreEvidenceReliable &&
        !input.causalResultForfeited &&
        input.bestScore <=
            -MoveQualityThresholds.mistakeMinimum(input.pieceValue);
    final bool terminalSelfLoss =
        input.evidence.outcomeReasonAfter == 'loseNoLegalMoves' ||
        input.evidence.outcomeReasonAfter == 'loseFullBoard';
    final List<MoveFeedbackReason> facts = <MoveFeedbackReason>[];

    // ?? from a result drop vs alternatives, a terminal self-loss, or the
    // blunder score band — unless the parent was already clearly lost.
    if (resultDrop ||
        terminalSelfLoss ||
        (hasNonNegativeAlternative &&
            !preservesDeterminedWin &&
            _isBlunder(input, classifiedLoss))) {
      if (parentAlreadyLosing) {
        facts.add(MoveFeedbackReason.noSavingAlternative);
        if (terminalSelfLoss) {
          facts.add(MoveFeedbackReason.terminalRuleLoss);
        }
        return _result(input, MoveFeedbackSymbol.none, facts);
      }
      if (resultDrop) {
        facts.add(
          bestWdl == MoveFeedbackWdl.win
              ? MoveFeedbackReason.losesWinningResult
              : MoveFeedbackReason.losesDrawingResult,
        );
      }
      if (input.evidence.phaseTransitionImpact) {
        facts.add(MoveFeedbackReason.phaseTransitionLoss);
      }
      if (input.evidence.outcomeReasonAfter != 'ongoing') {
        facts.add(MoveFeedbackReason.terminalRuleLoss);
      }
      if (classifiedLoss >=
          MoveQualityThresholds.blunderMinimum(input.pieceValue)) {
        facts.add(MoveFeedbackReason.decisiveMaterialLoss);
      }
      return _result(input, MoveFeedbackSymbol.blunder, facts);
    }

    // Causally attributed root mistake: the deep probe proved the parent
    // still had a saving alternative and this move started the stretch that
    // was never recovered. That is result-level evidence, so it must not be
    // diluted by the per-move noise allowance or capped at `?!`. Exact WDL
    // drops already earned `??` above; engine evidence grades `?`.
    if (input.causalResultForfeited && hasNonNegativeAlternative) {
      final bool signFlip = input.playedScore < 0;
      if (signFlip ||
          input.loss >=
              MoveQualityThresholds.mistakeMinimum(input.pieceValue)) {
        facts.add(
          signFlip
              ? (bestWdl == MoveFeedbackWdl.win
                    ? MoveFeedbackReason.losesWinningResult
                    : MoveFeedbackReason.losesDrawingResult)
              : MoveFeedbackReason.decisiveMaterialLoss,
        );
        return _result(input, MoveFeedbackSymbol.mistake, facts);
      }
    }

    // Same determined win with a large distance/search spread is not a
    // material blunder; cap at dubious so mates-in-N noise stays honest.
    if (preservesDeterminedWin &&
        classifiedLoss >=
            MoveQualityThresholds.dubiousMinimum(input.pieceValue)) {
      facts.add(MoveFeedbackReason.preservesResult);
      if (input.evidence.phaseTransitionImpact) {
        facts.add(MoveFeedbackReason.phaseTransitionLoss);
      }
      facts.add(MoveFeedbackReason.requiresPreciseFollowUp);
      return _result(input, MoveFeedbackSymbol.dubious, facts);
    }

    // Already choosing among worse moves: do not invent a causative mark.
    if (scoreEvidenceReliable && !hasNonNegativeAlternative && !resultDrop) {
      facts.add(MoveFeedbackReason.noSavingAlternative);
      return _result(input, MoveFeedbackSymbol.none, facts);
    }

    // Soft equality spoil: best stayed non-negative while the played move
    // went negative. ±80 terminal bands alone miss this common case. Use the
    // raw loss so the engine noise floor cannot hide a clear sign flip.
    final bool spoiledEquality =
        hasNonNegativeAlternative &&
        input.playedScore < 0 &&
        input.loss >= MoveQualityThresholds.dubiousMinimum(input.pieceValue);

    if (hasNonNegativeAlternative &&
        classifiedLoss >=
            MoveQualityThresholds.mistakeMinimum(input.pieceValue)) {
      if (spoiledEquality) {
        facts.add(MoveFeedbackReason.losesDrawingResult);
      }
      facts.add(
        input.evidence.missedOpportunity
            ? MoveFeedbackReason.missesImmediateRuleReward
            : input.evidence.mobilityDelta < 0
            ? MoveFeedbackReason.mobilityLoss
            : MoveFeedbackReason.decisiveMaterialLoss,
      );
      return _result(input, MoveFeedbackSymbol.mistake, facts);
    }

    if (hasNonNegativeAlternative &&
        (classifiedLoss >=
                MoveQualityThresholds.dubiousMinimum(input.pieceValue) ||
            spoiledEquality)) {
      if (spoiledEquality) {
        facts.add(MoveFeedbackReason.losesDrawingResult);
      }
      facts.add(MoveFeedbackReason.requiresPreciseFollowUp);
      return _result(input, MoveFeedbackSymbol.dubious, facts);
    }

    // Phase 1: no automatic positive glyphs.
    if (!_scoreEvidenceReliable(input)) {
      facts.add(MoveFeedbackReason.insufficientEvidence);
    } else if (input.evidence.forced || input.legalRootActionCount == 1) {
      facts.add(MoveFeedbackReason.forcedMove);
    } else if (input.evidence.equivalent) {
      facts.add(MoveFeedbackReason.equivalentChoice);
    } else if (input.evidence.routineGain) {
      facts.add(
        input.evidence.formedMillWithReward
            ? MoveFeedbackReason.directRuleReward
            : MoveFeedbackReason.naturalConversion,
      );
    } else if (topCandidate) {
      facts.add(MoveFeedbackReason.regularBest);
    } else if (bestWdl == playedWdl) {
      facts.add(MoveFeedbackReason.preservesResult);
    } else {
      facts.add(MoveFeedbackReason.engineEstimate);
    }
    return _result(input, MoveFeedbackSymbol.none, facts);
  }

  /// Merge atomic action feedback into the single PGN turn annotation.
  static MoveFeedbackResult aggregateTurn(List<MoveFeedbackResult> actions) {
    assert(actions.isNotEmpty, 'A complete turn must contain an action.');
    final Iterable<MoveFeedbackResult> negatives = actions.where(
      (MoveFeedbackResult result) => result.symbol.isNegative,
    );
    if (negatives.isNotEmpty) {
      return negatives.reduce(
        (MoveFeedbackResult a, MoveFeedbackResult b) =>
            _negativePriority(a.symbol) >= _negativePriority(b.symbol) ? a : b,
      );
    }
    return actions.first;
  }

  // Note: an all-candidates-losing parent (best <= -terminal) is always
  // intercepted earlier by the parent-already-losing suppression.
  static bool _isBlunder(MoveFeedbackInput input, int loss) {
    return loss >= MoveQualityThresholds.blunderMinimum(input.pieceValue) &&
        _scoreEvidenceReliable(input);
  }

  static MoveFeedbackResult _result(
    MoveFeedbackInput input,
    MoveFeedbackSymbol symbol,
    List<MoveFeedbackReason> reasons,
  ) => MoveFeedbackResult(
    symbol: symbol,
    reasons: <MoveFeedbackReason>{
      ...reasons,
      if (input.source == MoveFeedbackSource.perfectDatabase)
        MoveFeedbackReason.perfectDatabase,
    }.toList(growable: false),
    bestScore: input.bestScore,
    playedScore: input.playedScore,
    depth: input.depth,
    source: input.source,
    confidence: input.source == MoveFeedbackSource.perfectDatabase
        ? MoveFeedbackConfidence.high
        : input.searchStable &&
              input.candidateCoverageComplete &&
              input.depth >= MoveQualityThresholds.minimumGradingDepth
        ? MoveFeedbackConfidence.high
        : input.depth >= MoveQualityThresholds.minimumGradingDepth
        ? MoveFeedbackConfidence.medium
        : MoveFeedbackConfidence.low,
  );

  static MoveFeedbackWdl _wdl(int score) {
    // Database values arrive on the same signed scale but are exact. Engine
    // estimates only claim a determined result at the established ±80 band.
    const int terminal = MoveQualityThresholds.engineTerminalScore;
    if (score >= terminal) {
      return MoveFeedbackWdl.win;
    }
    if (score <= -terminal) {
      return MoveFeedbackWdl.loss;
    }
    return MoveFeedbackWdl.draw;
  }

  static bool _scoreEvidenceReliable(MoveFeedbackInput input) {
    if (input.source == MoveFeedbackSource.perfectDatabase) {
      return true;
    }
    // Time-bounded MultiPV rarely finishes every legal root at equal depth.
    // Partial coverage underestimates loss (best-among-returned ≤ true best),
    // so negative grades stay conservative. Do not require full coverage or
    // identical depths — that silenced almost all on-demand / quick-review
    // annotations under a 200 ms budget.
    return input.depth >= MoveQualityThresholds.minimumGradingDepth;
  }

  static int _classifiedLoss(MoveFeedbackInput input) {
    if (input.source == MoveFeedbackSource.perfectDatabase) {
      return input.loss;
    }
    return (input.loss -
            MoveQualityThresholds.engineNoiseAllowance(input.pieceValue))
        .clamp(0, 1 << 30);
  }

  static int _negativePriority(MoveFeedbackSymbol symbol) => switch (symbol) {
    MoveFeedbackSymbol.blunder => 3,
    MoveFeedbackSymbol.mistake => 2,
    MoveFeedbackSymbol.dubious => 1,
    _ => 0,
  };
}
