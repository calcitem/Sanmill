// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_stats_page.dart
//
// Advanced statistics and analytics dashboard for puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/puzzle_models.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(s.puzzleStatistics)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Rating card
            _buildRatingCard(rating, s),
            const SizedBox(height: 16),

            // Performance overview
            _buildPerformanceCard(stats, s),
            const SizedBox(height: 16),

            // Success rate by difficulty
            _buildDifficultyStatsCard(s),
            const SizedBox(height: 16),

            // Success rate by category
            _buildCategoryStatsCard(s),
            const SizedBox(height: 16),

            // Recent activity
            _buildRecentActivityCard(s),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingCard(PuzzleRating rating, S s) {
    return Card(
      elevation: 4,
      color: Colors.blue.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: <Widget>[
            Text(
              s.puzzleStatsRating,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${rating.rating}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            if (rating.isProvisional) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      FluentIcons.warning_24_regular,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.puzzleStatsProvisional(
                        rating.provisionalGames - rating.gamesPlayed,
                      ),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _buildStatItem(
                  s.puzzleStatsGamesPlayed,
                  '${rating.gamesPlayed}',
                  FluentIcons.games_24_regular,
                ),
                Container(width: 1, height: 40, color: Colors.grey),
                _buildStatItem(
                  s.puzzleStatsDeviation,
                  '±${rating.ratingDeviation.round()}',
                  FluentIcons.chart_multiple_24_regular,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard(Map<String, dynamic> stats, S s) {
    final double successRate = stats['successRate'] as double;
    final int avgTime = stats['averageTime'] as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              s.puzzleStatsPerformance,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildPerformanceTile(
                    s.puzzleStatsSuccessRate,
                    '${successRate.toStringAsFixed(1)}%',
                    Colors.green,
                    FluentIcons.checkmark_circle_24_filled,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPerformanceTile(
                    s.puzzleStatsAvgTime,
                    _formatAvgTime(avgTime),
                    Colors.blue,
                    FluentIcons.timer_24_filled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildPerformanceTile(
                    s.puzzleStatsSolved,
                    '${stats['successCount']}',
                    Colors.green,
                    FluentIcons.checkmark_24_filled,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPerformanceTile(
                    s.puzzleStatsFailed,
                    '${stats['failCount']}',
                    Colors.red,
                    FluentIcons.dismiss_24_filled,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceTile(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildDifficultyStatsCard(S s) {
    // TODO: Calculate actual stats from history
    final List<MapEntry<PuzzleDifficulty, double>>
    difficultyStats = <MapEntry<PuzzleDifficulty, double>>[
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.beginner, 85.0),
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.easy, 75.0),
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.medium, 60.0),
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.hard, 45.0),
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.expert, 30.0),
      const MapEntry<PuzzleDifficulty, double>(PuzzleDifficulty.master, 15.0),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              s.puzzleStatsByDifficulty,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...difficultyStats.map((MapEntry<PuzzleDifficulty, double> entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildProgressBar(
                  entry.key.displayName(context),
                  entry.value,
                  _getDifficultyColor(entry.key),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryStatsCard(S s) {
    // TODO: Calculate actual stats from history
    final List<MapEntry<PuzzleCategory, double>> categoryStats =
        <MapEntry<PuzzleCategory, double>>[
          const MapEntry<PuzzleCategory, double>(PuzzleCategory.formMill, 70.0),
          const MapEntry<PuzzleCategory, double>(
            PuzzleCategory.capturePieces,
            65.0,
          ),
          const MapEntry<PuzzleCategory, double>(PuzzleCategory.winGame, 55.0),
          const MapEntry<PuzzleCategory, double>(PuzzleCategory.defend, 50.0),
        ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              s.puzzleStatsByCategory,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...categoryStats.map((MapEntry<PuzzleCategory, double> entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildProgressBar(
                  entry.key.displayName(context),
                  entry.value,
                  Colors.blue,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey[800],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  Widget _buildRecentActivityCard(S s) {
    final List<PuzzleAttemptResult> recentAttempts = _ratingService
        .getAttemptHistory(limit: 5);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              s.puzzleStatsRecentActivity,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recentAttempts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    s.puzzleStatsNoActivity,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ),
              )
            else
              ...recentAttempts.map((PuzzleAttemptResult attempt) {
                return _buildActivityItem(attempt);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(PuzzleAttemptResult attempt) {
    final bool success = attempt.success;
    final Color color = success ? Colors.green : Colors.red;
    final IconData icon = success
        ? FluentIcons.checkmark_circle_24_filled
        : FluentIcons.dismiss_circle_24_filled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _formatTimestamp(attempt.timestamp),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (attempt.ratingChange != null)
            Text(
              '${attempt.ratingChange! >= 0 ? '+' : ''}${attempt.ratingChange}',
              style: TextStyle(
                color: attempt.ratingChange! >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: <Widget>[
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
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

  String _formatTimestamp(DateTime timestamp) {
    final Duration diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Color _getDifficultyColor(PuzzleDifficulty difficulty) {
    switch (difficulty) {
      case PuzzleDifficulty.beginner:
        return Colors.green;
      case PuzzleDifficulty.easy:
        return Colors.lightGreen;
      case PuzzleDifficulty.medium:
        return Colors.orange;
      case PuzzleDifficulty.hard:
        return Colors.deepOrange;
      case PuzzleDifficulty.expert:
        return Colors.red;
      case PuzzleDifficulty.master:
        return Colors.purple;
    }
  }
}
