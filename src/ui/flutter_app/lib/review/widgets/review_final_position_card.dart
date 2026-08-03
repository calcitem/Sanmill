// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../generated/intl/l10n.dart';
import '../models/review_models.dart';

/// Presents the recorded result, natural board state, analytical verdict, and
/// optional historical Human Database evidence as distinct information layers.
class ReviewFinalPositionCard extends StatelessWidget {
  const ReviewFinalPositionCard({
    super.key,
    required this.recordedResult,
    required this.assessment,
    required this.assessing,
    required this.hasError,
    required this.retryEnabled,
    required this.configuringHumanDatabase,
    required this.onRetry,
    required this.onConfigureHumanDatabase,
  }) : assert(assessment != null || assessing || hasError);

  final String recordedResult;
  final ReviewPositionAssessment? assessment;
  final bool assessing;
  final bool hasError;
  final bool retryEnabled;
  final bool configuringHumanDatabase;
  final VoidCallback onRetry;
  final VoidCallback onConfigureHumanDatabase;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool showRetry =
        hasError ||
        assessment?.source == ReviewPositionAssessmentSource.unavailable;
    return Card(
      key: const Key('review_final_position_assessment'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.assessment_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.reviewFinalPosition,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (assessing)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (assessing && assessment == null) ...<Widget>[
              const SizedBox(height: 12),
              Text(strings.reviewAssessingFinalPosition),
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ] else if (assessment != null) ...<Widget>[
              const SizedBox(height: 14),
              _buildStatusLine(
                icon: Icons.history_rounded,
                text: strings.reviewRecordedResult(
                  _recordedResultLabel(strings),
                ),
              ),
              const SizedBox(height: 8),
              _buildStatusLine(
                key: const Key('review_final_board_status'),
                icon: assessment!.isBoardTerminal
                    ? Icons.flag_outlined
                    : Icons.schedule_rounded,
                text: _finalBoardStatusLabel(strings, assessment!),
              ),
              const SizedBox(height: 14),
              _buildPositionVerdict(context, assessment!),
              if (assessment!.humanDatabase.state !=
                  ReviewHumanDatabaseState.notApplicable) ...<Widget>[
                const Divider(height: 30),
                _buildHumanDatabaseEvidence(context, assessment!.humanDatabase),
              ],
              if (assessing) ...<Widget>[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
            ],
            if (showRetry && !assessing) ...<Widget>[
              const SizedBox(height: 12),
              if (hasError) ...<Widget>[
                Text(
                  strings.reviewAssessmentUnavailable,
                  style: TextStyle(color: colors.error),
                ),
                const SizedBox(height: 8),
              ],
              TextButton.icon(
                key: const Key('review_retry_final_assessment'),
                onPressed: retryEnabled ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLine({
    Key? key,
    required IconData icon,
    required String text,
  }) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }

  Widget _buildPositionVerdict(
    BuildContext context,
    ReviewPositionAssessment assessment,
  ) {
    final S strings = S.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool heuristic =
        assessment.source == ReviewPositionAssessmentSource.engine;
    final IconData icon = switch (assessment.source) {
      ReviewPositionAssessmentSource.board => Icons.flag_outlined,
      ReviewPositionAssessmentSource.perfectDatabase => Icons.verified_outlined,
      ReviewPositionAssessmentSource.engine => Icons.memory_rounded,
      ReviewPositionAssessmentSource.unavailable => Icons.help_outline_rounded,
    };
    final String verdict =
        assessment.source == ReviewPositionAssessmentSource.board
        ? _naturalBoardOutcomeLabel(strings, assessment.boardOutcome)
        : _positionVerdictLabel(strings, assessment.verdict);
    final String headline = switch (assessment.source) {
      ReviewPositionAssessmentSource.board => strings.reviewNaturalBoardVerdict(
        verdict,
      ),
      ReviewPositionAssessmentSource.perfectDatabase =>
        strings.reviewPerfectDatabaseVerdict(verdict),
      ReviewPositionAssessmentSource.engine => strings.reviewQuickEngineVerdict(
        verdict,
      ),
      ReviewPositionAssessmentSource.unavailable =>
        strings.reviewAssessmentUnavailable,
    };
    return Semantics(
      key: const Key('review_final_position_verdict'),
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colors.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    if (heuristic) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        strings.reviewHeuristicDisclaimer,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHumanDatabaseEvidence(
    BuildContext context,
    ReviewHumanDatabaseEvidence evidence,
  ) {
    final S strings = S.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleSmall;
    if (evidence.state == ReviewHumanDatabaseState.available) {
      assert(evidence.total > 0);
      final int winPercent = (evidence.wins * 100 / evidence.total).round();
      final int drawPercent = (evidence.draws * 100 / evidence.total).round();
      final int lossPercent = (evidence.losses * 100 / evidence.total).round();
      final String total = NumberFormat.decimalPattern(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(evidence.total);
      final String side = _reviewSideLabel(strings, evidence.perspective!);
      return Column(
        key: const Key('review_human_database_evidence'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.groups_2_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(strings.reviewHumanEvidence, style: titleStyle),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(strings.reviewHumanEvidenceSummary(side, total)),
          const SizedBox(height: 12),
          Semantics(
            label: strings.humanGameDatabaseResultsSemantics(
              winPercent,
              drawPercent,
              lossPercent,
              total,
            ),
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                key: const Key('review_human_database_result_bar'),
                height: 12,
                child: Row(
                  children: <Widget>[
                    if (evidence.wins > 0)
                      Expanded(
                        flex: evidence.wins,
                        child: ColoredBox(color: colors.primary),
                      ),
                    if (evidence.draws > 0)
                      Expanded(
                        flex: evidence.draws,
                        child: ColoredBox(color: colors.outlineVariant),
                      ),
                    if (evidence.losses > 0)
                      Expanded(
                        flex: evidence.losses,
                        child: ColoredBox(color: colors.error),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ReviewResultPill(
                color: colors.primary,
                label: '${strings.wins} $winPercent%',
              ),
              _ReviewResultPill(
                color: colors.outline,
                label: '${strings.draws} $drawPercent%',
              ),
              _ReviewResultPill(
                color: colors.error,
                label: '${strings.losses} $lossPercent%',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.reviewHistoricalResultsDisclaimer,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
    }

    final String status = switch (evidence.state) {
      ReviewHumanDatabaseState.disabled => strings.humanDatabaseDisabled,
      ReviewHumanDatabaseState.notConfigured =>
        strings.humanDatabaseNotSelected,
      ReviewHumanDatabaseState.rulesUnsupported =>
        strings.humanDatabaseRulesUnsupported,
      ReviewHumanDatabaseState.unavailable => strings.humanDatabaseUnavailable,
      ReviewHumanDatabaseState.noRecords =>
        strings.humanDatabaseNoPositionRecords,
      ReviewHumanDatabaseState.capturePending =>
        strings.humanDatabaseCaptureStepUnavailable,
      ReviewHumanDatabaseState.available ||
      ReviewHumanDatabaseState.notApplicable => throw StateError(
        'Human Database state must be handled before empty evidence.',
      ),
    };
    final String detail = switch (evidence.state) {
      ReviewHumanDatabaseState.disabled ||
      ReviewHumanDatabaseState.notConfigured =>
        strings.reviewHumanDatabaseOptional,
      ReviewHumanDatabaseState.rulesUnsupported =>
        strings.reviewHumanRulesUnsupportedDetail,
      ReviewHumanDatabaseState.unavailable =>
        strings.reviewHumanUnavailableDetail,
      ReviewHumanDatabaseState.noRecords => strings.reviewHumanNoRecordsDetail,
      ReviewHumanDatabaseState.capturePending =>
        strings.humanDatabaseCaptureStepUnavailableHint,
      ReviewHumanDatabaseState.available ||
      ReviewHumanDatabaseState.notApplicable => throw StateError(
        'Human Database state must be handled before empty evidence.',
      ),
    };
    final bool showAction =
        evidence.state == ReviewHumanDatabaseState.disabled ||
        evidence.state == ReviewHumanDatabaseState.notConfigured ||
        evidence.state == ReviewHumanDatabaseState.unavailable;
    final String actionLabel = switch (evidence.state) {
      ReviewHumanDatabaseState.disabled => strings.reviewEnableHumanDatabase,
      ReviewHumanDatabaseState.unavailable => strings.reviewRepairHumanDatabase,
      _ => strings.reviewSetUpHumanDatabase,
    };
    return Column(
      key: const Key('review_human_database_guidance'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.groups_2_outlined, size: 20, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(strings.reviewHumanEvidence, style: titleStyle),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(status, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (showAction) ...<Widget>[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('review_configure_human_database'),
            onPressed: configuringHumanDatabase
                ? null
                : onConfigureHumanDatabase,
            icon: configuringHumanDatabase
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    evidence.state == ReviewHumanDatabaseState.disabled
                        ? Icons.power_settings_new_rounded
                        : Icons.download_rounded,
                  ),
            label: Text(actionLabel),
          ),
        ],
      ],
    );
  }

  String _recordedResultLabel(S strings) => switch (recordedResult) {
    '1-0' => strings.reviewRecordedWhiteWin,
    '0-1' => strings.reviewRecordedBlackWin,
    '1/2-1/2' => strings.reviewRecordedDraw,
    '*' || '' => strings.unfinishedGame,
    final String value => value,
  };

  static String _finalBoardStatusLabel(
    S strings,
    ReviewPositionAssessment assessment,
  ) => switch (assessment.boardOutcome) {
    ReviewBoardOutcome.ongoing => strings.reviewFinalBoardOngoing(
      _reviewSideLabel(strings, assessment.sideToMove!),
    ),
    ReviewBoardOutcome.whiteWin ||
    ReviewBoardOutcome.blackWin ||
    ReviewBoardOutcome.draw ||
    ReviewBoardOutcome.abandoned => strings.gameOver,
  };

  static String _naturalBoardOutcomeLabel(
    S strings,
    ReviewBoardOutcome outcome,
  ) => switch (outcome) {
    ReviewBoardOutcome.whiteWin => strings.reviewWhiteWon,
    ReviewBoardOutcome.blackWin => strings.reviewBlackWon,
    ReviewBoardOutcome.draw => strings.draw,
    ReviewBoardOutcome.abandoned => strings.unfinishedGame,
    ReviewBoardOutcome.ongoing => throw StateError(
      'An ongoing board does not have a natural result.',
    ),
  };

  static String _positionVerdictLabel(
    S strings,
    ReviewPositionVerdict verdict,
  ) => switch (verdict) {
    ReviewPositionVerdict.whiteForcedWin => strings.reviewWhiteForcedWin,
    ReviewPositionVerdict.draw => strings.reviewPerfectPlayDraw,
    ReviewPositionVerdict.blackForcedWin => strings.reviewBlackForcedWin,
    ReviewPositionVerdict.whiteFavored => strings.reviewWhiteFavored,
    ReviewPositionVerdict.roughlyEqual => strings.reviewRoughlyEqual,
    ReviewPositionVerdict.blackFavored => strings.reviewBlackFavored,
    ReviewPositionVerdict.unavailable => strings.reviewAssessmentUnavailable,
  };

  static String _reviewSideLabel(S strings, ReviewSide side) => switch (side) {
    ReviewSide.white => strings.reviewWhiteSide,
    ReviewSide.black => strings.reviewBlackSide,
  };
}

class _ReviewResultPill extends StatelessWidget {
  const _ReviewResultPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
