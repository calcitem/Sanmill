// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// The six conventional PGN move-quality glyphs plus an unannotated result.
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
}

enum MoveFeedbackSource { engine, perfectDatabase }

enum MoveFeedbackConfidence { low, medium, high }

/// A single source for score thresholds used by review and on-demand feedback.
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
    this.hasCalmerEquivalent = false,
    this.opponentSafeReplies,
    this.naturalRepliesLosing,
    this.playedTrapScore,
    this.calmTrapScore,
    this.strategicReasons = const <MoveFeedbackReason>{},
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
  final bool hasCalmerEquivalent;
  final int? opponentSafeReplies;
  final int? naturalRepliesLosing;
  final int? playedTrapScore;
  final int? calmTrapScore;
  final Set<MoveFeedbackReason> strategicReasons;
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

abstract final class MoveFeedbackClassifier {
  static MoveFeedbackResult classify(MoveFeedbackInput input) {
    final int loss = input.loss;
    final MoveFeedbackWdl bestWdl = _wdl(input.bestScore, input.source);
    final MoveFeedbackWdl playedWdl = _wdl(input.playedScore, input.source);
    final bool resultDrop = playedWdl.index < bestWdl.index;
    final List<MoveFeedbackReason> facts = <MoveFeedbackReason>[];

    if (resultDrop) {
      facts.add(
        bestWdl == MoveFeedbackWdl.win
            ? MoveFeedbackReason.losesWinningResult
            : MoveFeedbackReason.losesDrawingResult,
      );
    }

    // Fixed negative priority: WDL drop, ??, ?, then ?!.
    if (resultDrop || _isBlunder(input, loss)) {
      if (input.evidence.phaseTransitionImpact) {
        facts.add(MoveFeedbackReason.phaseTransitionLoss);
      }
      if (input.evidence.outcomeReasonAfter != 'ongoing') {
        facts.add(MoveFeedbackReason.terminalRuleLoss);
      }
      if (loss >= MoveQualityThresholds.blunderMinimum(input.pieceValue)) {
        facts.add(MoveFeedbackReason.decisiveMaterialLoss);
      }
      return _result(input, MoveFeedbackSymbol.blunder, facts);
    }

    if (_isMistake(input, loss)) {
      facts.add(
        input.evidence.missedOpportunity
            ? MoveFeedbackReason.missesImmediateRuleReward
            : input.evidence.mobilityDelta < 0
            ? MoveFeedbackReason.mobilityLoss
            : MoveFeedbackReason.decisiveMaterialLoss,
      );
      return _result(input, MoveFeedbackSymbol.mistake, facts);
    }

    if (_isDubious(input, loss)) {
      facts.add(
        input.evidence.deferredOpportunity
            ? MoveFeedbackReason.defersOpportunity
            : MoveFeedbackReason.requiresPreciseFollowUp,
      );
      return _result(input, MoveFeedbackSymbol.dubious, facts);
    }

    final bool positiveEvidenceStable =
        input.searchStable &&
        input.candidateCoverageComplete &&
        !input.evidence.forced &&
        !input.evidence.equivalent &&
        !input.evidence.routineGain;
    final bool topCandidate =
        input.playedRank == 1 &&
        loss <= MoveQualityThresholds.bestMaximum(input.pieceValue);
    final int? runnerUpScore = input.runnerUpScore;
    final int alternativeGap = runnerUpScore == null
        ? 0
        : input.playedScore - runnerUpScore;

    if (positiveEvidenceStable &&
        topCandidate &&
        alternativeGap >=
            MoveQualityThresholds.mistakeMinimum(input.pieceValue) &&
        _hasBrilliantMechanism(input)) {
      facts.addAll(_positiveReasons(input));
      return _result(input, MoveFeedbackSymbol.brilliant, facts);
    }

    if (positiveEvidenceStable &&
        topCandidate &&
        alternativeGap >=
            MoveQualityThresholds.dubiousMinimum(input.pieceValue) &&
        _hasGoodMechanism(input)) {
      facts.addAll(_positiveReasons(input));
      return _result(input, MoveFeedbackSymbol.good, facts);
    }

    if (_isInteresting(input, bestWdl, playedWdl)) {
      facts.add(MoveFeedbackReason.createsPracticalChances);
      return _result(input, MoveFeedbackSymbol.interesting, facts);
    }

    if (!input.searchStable || !input.candidateCoverageComplete) {
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

    // A routine capture cannot make a complete turn brilliant. A genuinely
    // critical capture target may still earn `!` from its own action.
    final Iterable<MoveFeedbackResult> positives = actions.where(
      (MoveFeedbackResult result) => result.symbol.isPositive,
    );
    if (positives.isNotEmpty) {
      final MoveFeedbackResult strongest = positives.reduce(
        (MoveFeedbackResult a, MoveFeedbackResult b) =>
            _positivePriority(a.symbol) >= _positivePriority(b.symbol) ? a : b,
      );
      final bool containsRoutineCapture = actions.any(
        (MoveFeedbackResult result) =>
            result.reasons.contains(MoveFeedbackReason.directRuleReward) ||
            result.reasons.contains(MoveFeedbackReason.naturalConversion),
      );
      if (containsRoutineCapture &&
          strongest.symbol == MoveFeedbackSymbol.brilliant) {
        return MoveFeedbackResult(
          symbol: MoveFeedbackSymbol.good,
          reasons: strongest.reasons,
          bestScore: strongest.bestScore,
          playedScore: strongest.playedScore,
          depth: strongest.depth,
          source: strongest.source,
          confidence: strongest.confidence,
          bestMove: strongest.bestMove,
          principalVariation: strongest.principalVariation,
        );
      }
      return strongest;
    }
    return actions.first;
  }

  static bool _isBlunder(MoveFeedbackInput input, int loss) {
    if (loss >= MoveQualityThresholds.blunderMinimum(input.pieceValue)) {
      if (input.allCandidatesLosing) {
        return input.evidence.moverBoardLoss >= 2 ||
            input.evidence.outcomeReasonAfter != 'ongoing';
      }
      return true;
    }
    return input.evidence.outcomeReasonAfter == 'loseNoLegalMoves' ||
        input.evidence.outcomeReasonAfter == 'loseFullBoard';
  }

  static bool _isMistake(MoveFeedbackInput input, int loss) {
    if (loss >= MoveQualityThresholds.mistakeMinimum(input.pieceValue)) {
      return true;
    }
    return input.evidence.missedOpportunity &&
        !input.evidence.deferredOpportunity &&
        !input.evidence.replacedOpportunity &&
        !input.evidence.compensatedConcession;
  }

  static bool _isDubious(MoveFeedbackInput input, int loss) {
    return loss >= MoveQualityThresholds.dubiousMinimum(input.pieceValue) ||
        input.evidence.deferredOpportunity;
  }

  static bool _hasBrilliantMechanism(MoveFeedbackInput input) {
    final MoveFeedbackEvidence evidence = input.evidence;
    return evidence.compensatedConcession ||
        evidence.replacedOpportunity ||
        evidence.initiativeSwing && evidence.mobilitySwing ||
        evidence.drawResourceImpact &&
            input.strategicReasons.contains(
              MoveFeedbackReason.preservesDrawCycle,
            ) ||
        input.strategicReasons.contains(
          MoveFeedbackReason.sacrificesMillForHigherOrderThreat,
        ) ||
        input.strategicReasons.contains(MoveFeedbackReason.createsZugzwang) ||
        evidence.profile.reusableMills &&
            input.strategicReasons.contains(
              MoveFeedbackReason.createsReusableMill,
            );
  }

  static bool _hasGoodMechanism(MoveFeedbackInput input) {
    return input.strategicReasons.isNotEmpty ||
        input.evidence.selectedCaptureTarget &&
            input.evidence.createdOpportunity ||
        input.evidence.initiativeSwing ||
        input.evidence.mobilitySwing ||
        input.evidence.phaseTransitionImpact ||
        input.evidence.drawResourceImpact;
  }

  static bool _isInteresting(
    MoveFeedbackInput input,
    MoveFeedbackWdl bestWdl,
    MoveFeedbackWdl playedWdl,
  ) {
    if (!input.searchStable ||
        !input.candidateCoverageComplete ||
        input.evidence.forced ||
        bestWdl != playedWdl ||
        input.loss >
            MoveQualityThresholds.acceptableMaximum(input.pieceValue) ||
        !input.hasCalmerEquivalent) {
      return false;
    }
    final bool trapLibraryProof =
        input.evidence.profile.trapPatchCompatible &&
        input.playedTrapScore != null &&
        input.calmTrapScore != null &&
        input.playedTrapScore! - input.calmTrapScore! >= 34;
    final int safeReplies = input.opponentSafeReplies ?? 1 << 30;
    final int naturalLosing = input.naturalRepliesLosing ?? 0;
    final bool replyProof =
        input.evidence.legalRepliesAfter >= 4 &&
        safeReplies <= 2 &&
        naturalLosing * 2 >= input.evidence.legalRepliesAfter;
    return trapLibraryProof || replyProof;
  }

  static List<MoveFeedbackReason> _positiveReasons(MoveFeedbackInput input) {
    final List<MoveFeedbackReason> reasons = input.strategicReasons.toList();
    if (input.evidence.compensatedConcession) {
      reasons.add(MoveFeedbackReason.compensatedConcession);
    }
    if (input.evidence.replacedOpportunity) {
      reasons.add(MoveFeedbackReason.replacesOpportunity);
    }
    if (input.evidence.initiativeSwing) {
      reasons.add(MoveFeedbackReason.preservesInitiative);
    }
    if (input.evidence.mobilitySwing && input.evidence.mobilityDelta > 0) {
      reasons.add(MoveFeedbackReason.preservesMobility);
    }
    if (reasons.isEmpty) {
      reasons.add(MoveFeedbackReason.preservesResult);
    }
    return reasons.toSet().toList(growable: false);
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
        : input.searchStable && input.candidateCoverageComplete
        ? MoveFeedbackConfidence.high
        : input.depth >= 8
        ? MoveFeedbackConfidence.medium
        : MoveFeedbackConfidence.low,
  );

  static MoveFeedbackWdl _wdl(int score, MoveFeedbackSource source) {
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

  static int _negativePriority(MoveFeedbackSymbol symbol) => switch (symbol) {
    MoveFeedbackSymbol.blunder => 3,
    MoveFeedbackSymbol.mistake => 2,
    MoveFeedbackSymbol.dubious => 1,
    _ => 0,
  };

  static int _positivePriority(MoveFeedbackSymbol symbol) => switch (symbol) {
    MoveFeedbackSymbol.brilliant => 3,
    MoveFeedbackSymbol.good => 2,
    MoveFeedbackSymbol.interesting => 1,
    _ => 0,
  };
}
