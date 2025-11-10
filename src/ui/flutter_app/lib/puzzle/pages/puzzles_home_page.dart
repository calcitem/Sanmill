// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzles_home_page.dart
//
// Main hub page for all puzzle modes and features

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';
import 'custom_puzzles_page.dart';
import 'daily_puzzle_page.dart';
import 'puzzle_history_page.dart';
import 'puzzle_list_page.dart';
import 'puzzle_rush_page.dart';
import 'puzzle_stats_page.dart';
import 'puzzle_streak_page.dart';

/// Main hub page for all puzzle-related features
class PuzzlesHomePage extends StatefulWidget {
  const PuzzlesHomePage({super.key});

  @override
  State<PuzzlesHomePage> createState() => _PuzzlesHomePageState();
}

class _PuzzlesHomePageState extends State<PuzzlesHomePage> {
  final PuzzleManager _puzzleManager = PuzzleManager();

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.puzzles, style: AppTheme.appBarTheme.titleTextStyle),
        actions: <Widget>[
          // Statistics overview
          IconButton(
            icon: const Icon(FluentIcons.chart_multiple_24_regular),
            onPressed: _showStatistics,
            tooltip: s.puzzleStatistics,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header with overall stats
            _buildStatsCard(s),
            const SizedBox(height: 24),

            // Daily Puzzle - Featured
            _buildFeaturedCard(
              s,
              title: s.dailyPuzzle,
              subtitle: s.dailyPuzzleDesc,
              icon: FluentIcons.calendar_star_24_regular,
              color: Theme.of(context).colorScheme.primary, // Use primary color
              onTap: () => _navigateTo(const DailyPuzzlePage()),
            ),
            const SizedBox(height: 16),

            // Grid of puzzle modes
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.95, // Adjusted to provide more vertical space
              children: <Widget>[
                // All Puzzles
                _buildModeCard(
                  s,
                  title: s.allPuzzles,
                  description: s.allPuzzlesDesc,
                  icon: FluentIcons.puzzle_piece_24_regular,
                  color: Theme.of(context).colorScheme.primary, // Use primary green
                  onTap: () => _navigateTo(const PuzzleListPage()),
                ),
                // Puzzle Rush
                _buildModeCard(
                  s,
                  title: s.puzzleRush,
                  description: s.puzzleRushDesc,
                  icon: FluentIcons.flash_24_regular,
                  color: Colors.deepOrange, // Keep energetic orange for "rush" mode
                  onTap: () => _navigateTo(const PuzzleRushPage()),
                ),
                // Puzzle Streak
                _buildModeCard(
                  s,
                  title: s.puzzleStreak,
                  description: s.puzzleStreakDesc,
                  icon: FluentIcons.flash_24_filled,
                  color: Theme.of(context).colorScheme.primaryContainer, // Darker green shade
                  onTap: () => _navigateTo(const PuzzleStreakPage()),
                ),
                // Custom Puzzles
                _buildModeCard(
                  s,
                  title: s.customPuzzles,
                  description: s.customPuzzlesDesc,
                  icon: FluentIcons.edit_24_regular,
                  color: Colors.lightGreen, // Lighter green variant
                  onTap: () => _navigateTo(const CustomPuzzlesPage()),
                ),
                // History
                _buildModeCard(
                  s,
                  title: s.puzzleHistory,
                  description: s.puzzleHistoryDesc,
                  icon: FluentIcons.history_24_regular,
                  color: Colors.teal, // Teal stays as complementary color
                  onTap: () => _navigateTo(const PuzzleHistoryPage()),
                ),
                // Statistics
                _buildModeCard(
                  s,
                  title: s.puzzleStatistics,
                  description: s.puzzleStatisticsDesc,
                  icon: FluentIcons.chart_multiple_24_regular,
                  color: Colors.blueGrey, // Neutral grey-blue for stats
                  onTap: () => _navigateTo(const PuzzleStatsPage()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build overall statistics card
  Widget _buildStatsCard(S s) {
    return ValueListenableBuilder<PuzzleSettings>(
      valueListenable: _puzzleManager.settingsNotifier,
      builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
        final Map<String, dynamic> stats = _puzzleManager.getStatistics();

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.yourProgress,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _buildStatItem(
                      s.totalPuzzles,
                      stats['totalPuzzles'].toString(),
                      FluentIcons.puzzle_piece_24_regular,
                      Theme.of(context).colorScheme.primary, // Use primary green
                    ),
                    _buildStatItem(
                      s.completed,
                      stats['completedPuzzles'].toString(),
                      FluentIcons.checkmark_circle_24_regular,
                      Colors.lightGreen, // Lighter green for completed
                    ),
                    _buildStatItem(
                      s.totalStars,
                      stats['totalStars'].toString(),
                      FluentIcons.star_24_regular,
                      Colors.amber, // Keep amber for stars
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      ((stats['completionPercentage'] as num?)?.toDouble() ??
                          0.0) /
                      100,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary, // Use primary green
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(stats['completionPercentage'] as num? ?? 0.0).toStringAsFixed(1)}% ${s.completed}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build a single stat item
  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: <Widget>[
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Build featured daily puzzle card
  Widget _buildFeaturedCard(
    S s, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      color: color.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(FluentIcons.chevron_right_24_regular, color: color),
            ],
          ),
        ),
      ),
    );
  }

  /// Build puzzle mode card
  Widget _buildModeCard(
    S s, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0), // Reduced padding from 16 to 12
          child: Column(
            mainAxisSize: MainAxisSize.min, // Use min size to prevent overflow
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Icon container
              Container(
                padding: const EdgeInsets.all(10), // Reduced from 12
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color), // Reduced from 36
              ),
              const SizedBox(height: 8), // Reduced from 12
              // Title text with flexible sizing
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2, // Allow wrapping for long titles
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              // Description text with flexible sizing
              Flexible(
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navigate to a page
  void _navigateTo(Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  /// Show statistics dialog
  void _showStatistics() {
    final S s = S.of(context);
    final Map<String, dynamic> stats = _puzzleManager.getStatistics();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(s.puzzleStatistics),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildStatRow(
                s.totalPuzzles,
                (stats['totalPuzzles'] as int? ?? 0).toString(),
              ),
              _buildStatRow(
                s.completed,
                (stats['completedPuzzles'] as int? ?? 0).toString(),
              ),
              _buildStatRow(
                s.totalStars,
                (stats['totalStars'] as int? ?? 0).toString(),
              ),
              _buildStatRow(
                s.completionPercentage,
                '${(stats['completionPercentage'] as num? ?? 0.0).toStringAsFixed(1)}%',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
