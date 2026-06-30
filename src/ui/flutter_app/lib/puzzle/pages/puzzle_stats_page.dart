// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_stats_page.dart
//
// Advanced statistics and analytics dashboard for puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/lichess_list_section.dart';
import '../services/puzzle_rating_service.dart';

/// Advanced statistics page for puzzles
class PuzzleStatsPage extends StatefulWidget {
  const PuzzleStatsPage({super.key});

  @override
  State<PuzzleStatsPage> createState() => _PuzzleStatsPageState();
}

class _PuzzleStatsPageState extends State<PuzzleStatsPage> {
  final PuzzleRatingService _ratingService = PuzzleRatingService();

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final Map<String, dynamic> stats = _ratingService.getStatistics();
    final PuzzleRating rating = _ratingService.getUserRating();
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      key: const Key('puzzle_stats_page_scaffold'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(s.puzzleStatistics)),
      body: ListTileTheme.merge(
        iconColor: theme.colorScheme.primary,
        child: ListView(
          key: const Key('puzzle_stats_page_list'),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: <Widget>[
            _buildRatingSection(context, rating, s),
            _buildPerformanceSection(context, stats, s),
            _buildRecentActivitySection(context, s),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection(BuildContext context, PuzzleRating rating, S s) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;

    return LichessListSection(
      header: Text(s.puzzleStatsRating),
      cardKey: const Key('puzzle_stats_rating_section'),
      children: <Widget>[
        _PuzzleRatingSummary(
          key: const Key('puzzle_stats_rating_summary'),
          rating: rating,
          label: s.puzzleStatsRating,
          color: colorScheme.primary,
          provisionalLabel: rating.isProvisional
              ? s.puzzleStatsProvisional(
                  rating.provisionalGames - rating.gamesPlayed,
                )
              : null,
          provisionalColor: colorScheme.tertiary,
        ),
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_games_played_tile'),
          icon: FluentIcons.games_24_regular,
          label: s.puzzleStatsGamesPlayed,
          value: '${rating.gamesPlayed}',
          color: customColors.good,
        ),
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_deviation_tile'),
          icon: FluentIcons.chart_multiple_24_regular,
          label: s.puzzleStatsDeviation,
          value: '±${rating.ratingDeviation.round()}',
          color: colorScheme.secondary,
        ),
      ],
    );
  }

  Widget _buildPerformanceSection(
    BuildContext context,
    Map<String, dynamic> stats,
    S s,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;
    final double successRate = stats['successRate'] as double;
    final int avgTime = stats['averageTime'] as int;

    return LichessListSection(
      header: Text(s.puzzleStatsPerformance),
      cardKey: const Key('puzzle_stats_performance_section'),
      children: <Widget>[
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_success_rate_tile'),
          icon: FluentIcons.checkmark_circle_24_filled,
          label: s.puzzleStatsSuccessRate,
          value: '${successRate.toStringAsFixed(1)}%',
          color: customColors.good,
        ),
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_average_time_tile'),
          icon: FluentIcons.timer_24_filled,
          label: s.puzzleStatsAvgTime,
          value: _formatAvgTime(avgTime),
          color: colorScheme.primary,
        ),
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_solved_tile'),
          icon: FluentIcons.checkmark_24_filled,
          label: s.puzzleStatsSolved,
          value: '${stats['successCount']}',
          color: customColors.good,
        ),
        _PuzzleStatsMetricTile(
          key: const Key('puzzle_stats_failed_tile'),
          icon: FluentIcons.dismiss_24_filled,
          label: s.puzzleStatsFailed,
          value: '${stats['failCount']}',
          color: colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection(BuildContext context, S s) {
    final List<PuzzleAttemptResult> recentAttempts = _ratingService
        .getAttemptHistory(limit: 5);

    return LichessListSection(
      header: Text(s.puzzleStatsRecentActivity),
      cardKey: const Key('puzzle_stats_activity_section'),
      hasLeading: recentAttempts.isNotEmpty,
      children: recentAttempts.isEmpty
          ? <Widget>[
              ListTile(
                key: const Key('puzzle_stats_no_activity_tile'),
                leading: const Icon(FluentIcons.history_24_regular),
                title: Text(s.puzzleStatsNoActivity),
              ),
            ]
          : recentAttempts
                .map(
                  (PuzzleAttemptResult attempt) => _PuzzleStatsActivityTile(
                    attempt: attempt,
                    timestampLabel: _formatTimestamp(
                      context,
                      attempt.timestamp,
                    ),
                  ),
                )
                .toList(growable: false),
    );
  }

  String _formatAvgTime(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    final int minutes = seconds ~/ 60;
    final int secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final S s = S.of(context);
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) {
      return s.daysAgo(diff.inDays);
    } else if (diff.inHours > 0) {
      return s.hoursAgo(diff.inHours);
    } else if (diff.inMinutes > 0) {
      return s.minutesAgo(diff.inMinutes);
    } else {
      return s.justNow;
    }
  }
}

class _PuzzleRatingSummary extends StatelessWidget {
  const _PuzzleRatingSummary({
    super.key,
    required this.rating,
    required this.label,
    required this.color,
    required this.provisionalColor,
    this.provisionalLabel,
  });

  final PuzzleRating rating;
  final String label;
  final Color color;
  final Color provisionalColor;
  final String? provisionalLabel;

  @override
  Widget build(BuildContext context) {
    final String? provisionalLabel = this.provisionalLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        children: <Widget>[
          Text(
            '${rating.rating}',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (provisionalLabel != null) ...<Widget>[
            const SizedBox(height: 10),
            _PuzzleStatsStatusBadge(
              icon: FluentIcons.warning_24_regular,
              label: provisionalLabel,
              color: provisionalColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _PuzzleStatsMetricTile extends StatelessWidget {
  const _PuzzleStatsMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PuzzleStatsActivityTile extends StatelessWidget {
  const _PuzzleStatsActivityTile({
    required this.attempt,
    required this.timestampLabel,
  });

  final PuzzleAttemptResult attempt;
  final String timestampLabel;

  @override
  Widget build(BuildContext context) {
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;
    final bool success = attempt.success;
    final Color color = success
        ? customColors.good
        : Theme.of(context).colorScheme.error;
    final IconData icon = success
        ? FluentIcons.checkmark_circle_24_filled
        : FluentIcons.dismiss_circle_24_filled;
    final int? ratingChange = attempt.ratingChange;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(timestampLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ratingChange == null
          ? null
          : _PuzzleStatsRatingDelta(value: ratingChange),
    );
  }
}

class _PuzzleStatsRatingDelta extends StatelessWidget {
  const _PuzzleStatsRatingDelta({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;
    final Color color = value >= 0
        ? customColors.good
        : Theme.of(context).colorScheme.error;

    return Text(
      '${value >= 0 ? '+' : ''}$value',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PuzzleStatsStatusBadge extends StatelessWidget {
  const _PuzzleStatsStatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
