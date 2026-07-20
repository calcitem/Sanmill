// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../../src/rust/api/mill_kernel.dart' as native;
import '../../../src/rust/api/simple.dart' as tgf;
import 'move_feedback.dart';

typedef MoveFeedbackExactScores = ({
  int bestScore,
  int playedScore,
  int? runnerUpScore,
  Set<String> bestMoves,
  bool allCandidatesLosing,
});

/// Returns exact WDL scores only when the database covers every legal move.
MoveFeedbackExactScores? moveFeedbackExactScores(
  tgf.MillAnalysisReport report, {
  required String playedMove,
  required int legalActionCount,
}) {
  if (report.moves.length != legalActionCount || legalActionCount == 0) {
    return null;
  }
  final Map<String, int> values = <String, int>{
    for (final tgf.MillMoveAnalysis move in report.moves) move.mv: move.value,
  };
  if (values.length != legalActionCount || !values.containsKey(playedMove)) {
    return null;
  }
  final List<int> ordered = values.values.toList(growable: false)
    ..sort((int a, int b) => b.compareTo(a));
  final int bestValue = ordered.first;
  return (
    bestScore: bestValue * MoveQualityThresholds.engineTerminalScore,
    playedScore:
        values[playedMove]! * MoveQualityThresholds.engineTerminalScore,
    runnerUpScore: ordered.length > 1
        ? ordered[1] * MoveQualityThresholds.engineTerminalScore
        : null,
    bestMoves: values.entries
        .where((MapEntry<String, int> entry) => entry.value == bestValue)
        .map((MapEntry<String, int> entry) => entry.key)
        .toSet(),
    allCandidatesLosing: bestValue < 0,
  );
}

/// Converts generated FRB DTOs into the pure Dart classifier model.
MoveFeedbackEvidence moveFeedbackEvidenceFromNative(
  native.MillFeedbackReport report,
) {
  final native.MillFeedbackEvidence facts = report.evidence;
  final native.MillMoveContextAssessment context = report.context;
  final native.MillRuleStrategyProfile profile = report.profile;
  return MoveFeedbackEvidence(
    forced: context.forced,
    equivalent: context.equivalent,
    routineGain: context.routineGain,
    createdOpportunity: context.createdOpportunity,
    missedOpportunity: context.missedOpportunity,
    deferredOpportunity: context.deferredOpportunity,
    replacedOpportunity: context.replacedOpportunity,
    compensatedConcession: context.compensatedConcession,
    initiativeSwing: context.initiativeSwing,
    mobilitySwing: context.mobilitySwing,
    phaseTransitionImpact: context.phaseTransitionImpact,
    drawResourceImpact: context.drawResourceImpact,
    formedMillWithReward: facts.formedMillWithReward,
    actualSpecialCapture: facts.actualSpecialCapture,
    selectedCaptureTarget: facts.selectedCaptureTarget,
    enteredFlying: facts.enteredFlying,
    opponentEnteredFlying: facts.opponentEnteredFlying,
    moverBoardLoss: facts.moverBoardLoss,
    opponentBoardLoss: facts.opponentBoardLoss,
    moverHandLoss: facts.moverHandLoss,
    opponentHandLoss: facts.opponentHandLoss,
    removalRightsCreated: facts.removalRightsCreated,
    legalRepliesAfter: facts.legalRepliesAfter,
    mobilityDelta: facts.mobilityDelta,
    outcomeReasonAfter: facts.outcomeReasonAfter,
    profile: MoveFeedbackRuleProfile(
      standardStrategyCompatible: profile.standardStrategyCompatible,
      reusableMills: profile.reusableMills,
      mayFly: profile.mayFly,
      perfectDatabaseCompatible: profile.perfectDatabaseCompatible,
      trapPatchCompatible: profile.trapPatchCompatible,
    ),
  );
}

Set<MoveFeedbackReason> moveFeedbackStrategicReasons(
  MoveFeedbackEvidence evidence,
) {
  final Set<MoveFeedbackReason> reasons = <MoveFeedbackReason>{};
  if (evidence.selectedCaptureTarget && evidence.createdOpportunity) {
    reasons.add(MoveFeedbackReason.selectsCriticalCaptureTarget);
  }
  if (evidence.initiativeSwing) {
    reasons.add(MoveFeedbackReason.forcesResponses);
  }
  if (evidence.mobilitySwing && evidence.mobilityDelta > 0) {
    reasons.add(MoveFeedbackReason.preservesMobility);
  }
  if (evidence.enteredFlying) {
    reasons.add(MoveFeedbackReason.usesFlyingTransition);
  }
  if (evidence.opponentEnteredFlying) {
    reasons.add(MoveFeedbackReason.avoidsPrematureFlyingTransition);
  }
  if (evidence.drawResourceImpact) {
    reasons.add(MoveFeedbackReason.preservesDrawCycle);
  }
  if (evidence.createdOpportunity && evidence.profile.reusableMills) {
    reasons.add(MoveFeedbackReason.createsReusableMill);
  }
  if (!evidence.profile.standardStrategyCompatible && reasons.isEmpty) {
    reasons.add(MoveFeedbackReason.ruleStrategyUnavailable);
  }
  return reasons;
}
