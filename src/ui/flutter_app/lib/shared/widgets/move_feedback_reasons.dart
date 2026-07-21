// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/analysis/move_feedback.dart';
import '../../generated/intl/l10n.dart';

String moveFeedbackReasonLabel(S strings, MoveFeedbackReason reason) {
  return switch (reason) {
    MoveFeedbackReason.regularBest => strings.moveFeedbackRegularBest,
    MoveFeedbackReason.forcedMove => strings.moveFeedbackForcedMove,
    MoveFeedbackReason.onlyCorrectMove => strings.moveFeedbackOnlyCorrect,
    MoveFeedbackReason.equivalentChoice => strings.moveFeedbackEquivalentChoice,
    MoveFeedbackReason.insufficientEvidence =>
      strings.moveFeedbackInsufficientEvidence,
    MoveFeedbackReason.engineEstimate => strings.moveFeedbackEngineEstimate,
    MoveFeedbackReason.perfectDatabase => strings.moveFeedbackPerfectDatabase,
    MoveFeedbackReason.preservesResult => strings.moveFeedbackPreservesResult,
    MoveFeedbackReason.losesWinningResult =>
      strings.moveFeedbackLosesWinningResult,
    MoveFeedbackReason.losesDrawingResult =>
      strings.moveFeedbackLosesDrawingResult,
    MoveFeedbackReason.decisiveMaterialLoss =>
      strings.moveFeedbackDecisiveMaterialLoss,
    MoveFeedbackReason.missesImmediateRuleReward =>
      strings.moveFeedbackMissesImmediateReward,
    MoveFeedbackReason.directRuleReward => strings.moveFeedbackDirectRuleReward,
    MoveFeedbackReason.routineConversion =>
      strings.moveFeedbackRoutineConversion,
    MoveFeedbackReason.naturalConversion =>
      strings.moveFeedbackNaturalConversion,
    MoveFeedbackReason.selectsCriticalCaptureTarget =>
      strings.moveFeedbackCriticalCapture,
    MoveFeedbackReason.allowsOpponentRuleReward =>
      strings.moveFeedbackAllowsOpponentReward,
    MoveFeedbackReason.selfBlock => strings.moveFeedbackSelfBlock,
    MoveFeedbackReason.preservesInitiative =>
      strings.moveFeedbackPreservesInitiative,
    MoveFeedbackReason.forcesResponses => strings.moveFeedbackForcesResponses,
    MoveFeedbackReason.avoidsDeadPlacement =>
      strings.moveFeedbackAvoidsDeadPlacement,
    MoveFeedbackReason.improvesTopologyControl =>
      strings.moveFeedbackImprovesTopologyControl,
    MoveFeedbackReason.preservesMobility =>
      strings.moveFeedbackPreservesMobility,
    MoveFeedbackReason.createsHerdingNet =>
      strings.moveFeedbackCreatesHerdingNet,
    MoveFeedbackReason.escapesHerding => strings.moveFeedbackEscapesHerding,
    MoveFeedbackReason.createsReusableMill =>
      strings.moveFeedbackCreatesReusableMill,
    MoveFeedbackReason.createsEntwinedMills =>
      strings.moveFeedbackCreatesEntwinedMills,
    MoveFeedbackReason.createsIndependentMills =>
      strings.moveFeedbackCreatesIndependentMills,
    MoveFeedbackReason.createsFeeder => strings.moveFeedbackCreatesFeeder,
    MoveFeedbackReason.nullifiesOpponentMill =>
      strings.moveFeedbackNullifiesOpponentMill,
    MoveFeedbackReason.recognizesRedundantMill =>
      strings.moveFeedbackRecognizesRedundantMill,
    MoveFeedbackReason.allowsConstrainedMill =>
      strings.moveFeedbackAllowsConstrainedMill,
    MoveFeedbackReason.abandonsMillForMobility =>
      strings.moveFeedbackAbandonsMillForMobility,
    MoveFeedbackReason.sacrificesMillForHigherOrderThreat =>
      strings.moveFeedbackSacrificesMill,
    MoveFeedbackReason.avoidsPrematureFlyingTransition =>
      strings.moveFeedbackAvoidsPrematureFlying,
    MoveFeedbackReason.usesFlyingTransition => strings.moveFeedbackUsesFlying,
    MoveFeedbackReason.createsZugzwang => strings.moveFeedbackCreatesZugzwang,
    MoveFeedbackReason.preservesDrawCycle =>
      strings.moveFeedbackPreservesDrawCycle,
    MoveFeedbackReason.breaksOpponentDrawResource =>
      strings.moveFeedbackBreaksDrawResource,
    MoveFeedbackReason.createsPracticalChances =>
      strings.moveFeedbackPracticalChances,
    MoveFeedbackReason.requiresPreciseFollowUp =>
      strings.moveFeedbackPreciseFollowUp,
    MoveFeedbackReason.mobilityLoss => strings.moveFeedbackMobilityLoss,
    MoveFeedbackReason.phaseTransitionLoss =>
      strings.moveFeedbackPhaseTransitionLoss,
    MoveFeedbackReason.terminalRuleLoss => strings.moveFeedbackTerminalRuleLoss,
    MoveFeedbackReason.compensatedConcession =>
      strings.moveFeedbackCompensatedConcession,
    MoveFeedbackReason.defersOpportunity =>
      strings.moveFeedbackDefersOpportunity,
    MoveFeedbackReason.replacesOpportunity =>
      strings.moveFeedbackReplacesOpportunity,
    MoveFeedbackReason.ruleStrategyUnavailable =>
      strings.moveFeedbackRuleStrategyUnavailable,
    MoveFeedbackReason.noSavingAlternative =>
      strings.moveFeedbackNoSavingAlternative,
  };
}

Future<void> showMoveFeedbackReasonsDialog({
  required BuildContext context,
  required String heading,
  required List<MoveFeedbackReason> reasons,
  required String reasonKeyPrefix,
}) {
  assert(reasons.isNotEmpty, 'A feedback reason dialog needs a reason.');
  final S strings = S.of(context);
  final List<String> labels = reasons
      .map(
        (MoveFeedbackReason reason) => moveFeedbackReasonLabel(strings, reason),
      )
      .toList(growable: false);
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(strings.moveFeedbackReasonsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(heading, style: Theme.of(dialogContext).textTheme.titleSmall),
            const SizedBox(height: 12),
            for (int index = 0; index < reasons.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle_outline, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        labels[index],
                        key: Key('$reasonKeyPrefix${reasons[index].name}'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.close),
        ),
      ],
    ),
  );
}
