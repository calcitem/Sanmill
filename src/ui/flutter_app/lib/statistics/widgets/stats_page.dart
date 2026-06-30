// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// statistics_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../statistics/model/stats_settings.dart';
import '../services/stats_service.dart';

/// A widget to display game statistics and ratings
class StatisticsPage extends StatelessWidget {
  /// Creates a statistics page
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return BlockSemantics(
      key: const Key('statistics_page_block_semantics'),
      child: Scaffold(
        key: const Key('statistics_page_scaffold'),
        appBar: AppBar(
          key: const Key('statistics_page_app_bar'),
          title: Text(
            S.of(context).statistics,
            key: const Key('statistics_page_app_bar_title'),
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        body: ValueListenableBuilder<dynamic>(
          key: const Key('statistics_page_value_listenable_builder'),
          valueListenable: DB().listenStatsSettings,
          builder: (BuildContext context, _, _) {
            // ignore: unnecessary_underscores
            final StatsSettings settings = DB().statsSettings;
            return SettingsList(
              key: const Key('statistics_page_settings_list'),
              children: <Widget>[
                _buildHumanStatsCard(context, settings.humanStats),
                _buildAiDifficultyStatsCard(context, settings),
                _buildStatsSettingsCard(context, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsSettingsCard(BuildContext context, StatsSettings settings) {
    final S l10n = S.of(context);

    return SettingsCard(
      key: const Key('statistics_page_settings_card'),
      title: Text(
        l10n.settings,
        key: const Key('statistics_page_settings_card_title'),
      ),
      children: <Widget>[
        SettingsListTile.switchTile(
          key: const Key('statistics_page_enable_statistics_switch'),
          value: settings.isStatsEnabled,
          onChanged: (bool value) {
            DB().statsSettings = settings.copyWith(isStatsEnabled: value);
          },
          titleString: S.of(context).enableStatistics,
          subtitleString: S.of(context).enableStatistics_Detail,
        ),

        // Reset statistics button
        ListTile(
          key: const Key('statistics_page_reset_statistics'),
          title: Text(
            S.of(context).resetStatistics,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          trailing: Icon(
            Icons.refresh,
            color: Theme.of(context).colorScheme.error,
          ),
          onTap: () => _showResetStatsConfirmationDialog(context),
        ),
      ],
    );
  }

  // Show confirmation dialog before resetting statistics
  void _showResetStatsConfirmationDialog(BuildContext context) {
    final S l10n = S.of(context);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(context).resetStatistics),
          content: Text(S.of(context).thisWillResetAllGameStatistics),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                _resetStats();
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(S.of(context).ok),
            ),
          ],
        );
      },
    );
  }

  // Reset all game statistics while preserving ratings
  void _resetStats() {
    final StatsSettings statsSettings = DB().statsSettings;

    // Reset human player statistics
    final PlayerStats resetHumanStats = PlayerStats(
      lastUpdated: DateTime.now(),
      // All statistics are reset to 0
    );

    // Create new settings with reset human rating
    final StatsSettings newStatsSettings = statsSettings.copyWith(
      humanStats: resetHumanStats,
      // Create a new empty map for AI ratings
      aiDifficultyStatsMap: <int, PlayerStats>{},
    );

    // Update the database
    DB().statsSettings = newStatsSettings;
  }

  Widget _buildHumanStatsCard(BuildContext context, PlayerStats humanStats) {
    final S l10n = S.of(context);
    final DateFormat dateFormat = DateFormat.yMd().add_Hm();
    final String lastUpdated = humanStats.lastUpdated != null
        ? dateFormat.format(humanStats.lastUpdated!)
        : "-";

    return SettingsCard(
      key: const Key('statistics_page_human_rating_card'),
      title: Text(
        l10n.myRating,
        key: const Key('statistics_page_human_rating_card_title'),
      ),
      children: <Widget>[
        _RatingSummary(
          rating: humanStats.rating,
          ratingColor: _getRatingColor(context, humanStats.rating),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _ResultMetric(
                  label: l10n.wins,
                  value: humanStats.wins.toString(),
                  detail: _formatRate(humanStats.wins, humanStats.gamesPlayed),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResultMetric(
                  label: l10n.draws,
                  value: humanStats.draws.toString(),
                  detail: _formatRate(humanStats.draws, humanStats.gamesPlayed),
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResultMetric(
                  label: l10n.losses,
                  value: humanStats.losses.toString(),
                  detail: _formatRate(
                    humanStats.losses,
                    humanStats.gamesPlayed,
                  ),
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        ListTile(
          key: const Key('statistics_page_games_played_row'),
          title: Text(l10n.gamesPlayed),
          trailing: _StatTrailingText(humanStats.gamesPlayed.toString()),
        ),
        ListTile(
          key: const Key('statistics_page_last_updated_row'),
          title: Text(l10n.lastUpdated),
          trailing: _StatTrailingText(lastUpdated),
        ),
      ],
    );
  }

  Widget _buildAiDifficultyStatsCard(
    BuildContext context,
    StatsSettings settings,
  ) {
    final S l10n = S.of(context);

    return SettingsCard(
      key: const Key('statistics_page_ai_statistics_card'),
      title: Text(
        l10n.aiStatistics,
        key: const Key('statistics_page_ai_statistics_card_title'),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            '${l10n.format} W/D/L (${l10n.wins}/${l10n.draws}/${l10n.losses})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (int level = 1; level <= 30; level++)
          _AiDifficultyStatsTile(
            key: Key('statistics_page_ai_level_$level'),
            level: level,
            rating: EloRatingService.getFixedAiEloRating(level),
            stats: settings.getAiDifficultyStats(level),
            ratingColor: _getRatingColor(
              context,
              EloRatingService.getFixedAiEloRating(level),
            ),
          ),
      ],
    );
  }

  String _formatRate(int count, int total) {
    assert(count >= 0, 'Statistics count must not be negative.');
    assert(total >= 0, 'Statistics total must not be negative.');
    return total > 0 ? '${(count / total * 100).toStringAsFixed(1)}%' : '0.0%';
  }

  Color _getRatingColor(BuildContext context, int rating) {
    if (rating >= 2000) {
      return Colors.purple; // Master
    } else if (rating >= 1800) {
      return Colors.blue; // Expert
    } else if (rating >= 1600) {
      return Colors.green; // Advanced
    } else if (rating >= 1400) {
      return Colors.amber; // Intermediate
    } else if (rating >= 1200) {
      return Colors.orange; // Average
    } else {
      return Colors.red; // Beginner
    }
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.rating, required this.ratingColor});

  final int rating;
  final Color ratingColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: Column(
        children: <Widget>[
          Text(
            rating.toString(),
            style: theme.textTheme.displaySmall?.copyWith(
              color: ratingColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            S.of(context).myRating,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiDifficultyStatsTile extends StatelessWidget {
  const _AiDifficultyStatsTile({
    super.key,
    required this.level,
    required this.rating,
    required this.stats,
    required this.ratingColor,
  });

  final int level;
  final int rating;
  final PlayerStats stats;
  final Color ratingColor;

  @override
  Widget build(BuildContext context) {
    assert(level >= 1 && level <= 30, 'AI difficulty level must be 1-30.');
    final S l10n = S.of(context);
    final TextStyle? monoStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );

    return ListTile(
      title: Text('${l10n.difficulty} $level'),
      subtitle: Text(
        '${l10n.totalGames}: ${_score(stats.losses, stats.draws, stats.wins)}\n'
        '${l10n.white}: ${_score(stats.blackLosses, stats.blackDraws, stats.blackWins)} · '
        '${l10n.black}: ${_score(stats.whiteLosses, stats.whiteDraws, stats.whiteWins)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: monoStyle,
      ),
      trailing: _StatTrailingText(rating.toString(), color: ratingColor),
    );
  }

  String _score(int wins, int draws, int losses) {
    assert(wins >= 0, 'Wins must not be negative.');
    assert(draws >= 0, 'Draws must not be negative.');
    assert(losses >= 0, 'Losses must not be negative.');
    return '$wins/$draws/$losses';
  }
}

class _StatTrailingText extends StatelessWidget {
  const _StatTrailingText(this.value, {this.color});

  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
