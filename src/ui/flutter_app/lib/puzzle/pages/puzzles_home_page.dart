// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzles_home_page.dart
//
// Main hub page for all puzzle modes and features

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
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
    final ThemeData theme = Theme.of(context);
    final bool useDarkSettingsUi = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: CustomDrawerIcon.of(context)?.drawerIcon,
        title: Text(s.puzzles),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildStatsCard(context, s, useDarkSettingsUi),
            const SizedBox(height: 12),
            _buildFeaturedCard(
              context,
              s,
              title: s.dailyPuzzle,
              subtitle: s.dailyPuzzleDesc,
              icon: FluentIcons.calendar_star_24_regular,
              color: theme.colorScheme.primary,
              onTap: () => _navigateTo(context, const DailyPuzzlePage()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const int crossAxisCount = 2;
                  const int rowCount = 3;
                  const double spacing = 12.0;

                  final double availableHeight = constraints.maxHeight;
                  final double availableWidth = constraints.maxWidth;
                  final double itemHeight =
                      (availableHeight - ((rowCount - 1) * spacing)) / rowCount;
                  final double itemWidth =
                      (availableWidth - ((crossAxisCount - 1) * spacing)) /
                      crossAxisCount;
                  assert(
                    itemHeight > 0,
                    'Puzzle tile height must be positive.',
                  );
                  assert(itemWidth > 0, 'Puzzle tile width must be positive.');
                  final double childAspectRatio = itemWidth / itemHeight;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: childAspectRatio,
                    physics: const NeverScrollableScrollPhysics(),
                    children: <Widget>[
                      _buildModeCard(
                        context,
                        s,
                        title: s.allPuzzles,
                        description: s.allPuzzlesDesc,
                        icon: FluentIcons.puzzle_piece_24_regular,
                        color: theme.colorScheme.primary,
                        onTap: () =>
                            _navigateTo(context, const PuzzleListPage()),
                      ),
                      _buildModeCard(
                        context,
                        s,
                        title: s.puzzleRush,
                        description: s.puzzleRushDesc,
                        icon: FluentIcons.flash_24_regular,
                        color: Colors.deepOrange,
                        onTap: () =>
                            _navigateTo(context, const PuzzleRushPage()),
                      ),
                      _buildModeCard(
                        context,
                        s,
                        title: s.puzzleStreak,
                        description: s.puzzleStreakDesc,
                        icon: FluentIcons.flash_24_filled,
                        color: theme.colorScheme.primaryContainer,
                        onTap: () =>
                            _navigateTo(context, const PuzzleStreakPage()),
                      ),
                      _buildModeCard(
                        context,
                        s,
                        title: s.customPuzzles,
                        description: s.customPuzzlesDesc,
                        icon: FluentIcons.edit_24_regular,
                        color: Colors.lightGreen,
                        onTap: () =>
                            _navigateTo(context, const CustomPuzzlesPage()),
                      ),
                      _buildModeCard(
                        context,
                        s,
                        title: s.puzzleHistory,
                        description: s.puzzleHistoryDesc,
                        icon: FluentIcons.history_24_regular,
                        color: Colors.teal,
                        onTap: () =>
                            _navigateTo(context, const PuzzleHistoryPage()),
                      ),
                      _buildModeCard(
                        context,
                        s,
                        title: s.puzzleStatistics,
                        description: s.puzzleStatisticsDesc,
                        icon: FluentIcons.chart_multiple_24_regular,
                        color: Colors.blueGrey,
                        onTap: () =>
                            _navigateTo(context, const PuzzleStatsPage()),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build overall statistics card (compact version)
  Widget _buildStatsCard(BuildContext context, S s, bool useDarkSettingsUi) {
    return ValueListenableBuilder<PuzzleSettings>(
      valueListenable: _puzzleManager.settingsNotifier,
      builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
        final Map<String, dynamic> stats = _puzzleManager.getStatistics();

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0), // Reduced from 16 to 12
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.yourProgress,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ), // Changed from titleLarge to titleMedium
                ),
                const SizedBox(height: 12), // Reduced from 16 to 12
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _buildStatItem(
                      s.totalPuzzles,
                      stats['totalPuzzles'].toString(),
                      FluentIcons.puzzle_piece_24_regular,
                      Theme.of(
                        context,
                      ).colorScheme.primary, // Use primary green
                      useDarkSettingsUi,
                    ),
                    _buildStatItem(
                      s.completed,
                      stats['completedPuzzles'].toString(),
                      FluentIcons.checkmark_circle_24_regular,
                      Colors.lightGreen, // Lighter green for completed
                      useDarkSettingsUi,
                    ),
                    _buildStatItem(
                      s.totalStars,
                      stats['totalStars'].toString(),
                      FluentIcons.star_24_regular,
                      Colors.amber, // Keep amber for stars
                      useDarkSettingsUi,
                    ),
                  ],
                ),
                const SizedBox(height: 8), // Reduced from 12 to 8
                LinearProgressIndicator(
                  value:
                      ((stats['completionPercentage'] as num?)?.toDouble() ??
                          0.0) /
                      100,
                  backgroundColor: useDarkSettingsUi
                      ? Colors.grey[800]
                      : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary, // Use primary green
                  ),
                ),
                const SizedBox(height: 6), // Reduced from 8 to 6
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

  /// Build a single stat item (compact version)
  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
    bool useDarkSettingsUi,
  ) {
    return Flexible(
      // Wrap in Flexible to prevent overflow in Row
      child: Column(
        children: <Widget>[
          Icon(icon, color: color, size: 28), // Reduced from 32 to 28
          const SizedBox(height: 6), // Reduced from 8 to 6
          Text(
            value,
            style: TextStyle(
              fontSize: 20, // Reduced from 24 to 20
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12, // Increased from 11 to 12 for better readability
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build featured daily puzzle card (compact version)
  /// Use white background for better text readability in light mode
  Widget _buildFeaturedCard(
    BuildContext context,
    S s, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0), // Reduced from 20 to 14
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12), // Reduced from 16 to 12
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ), // Reduced from 40 to 32
              ),
              const SizedBox(width: 12), // Reduced from 16 to 12
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        // Changed from titleLarge to titleMedium
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2), // Reduced from 4 to 2
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall, // Changed from bodyMedium to bodySmall
                      maxLines: 1, // Limit to 1 line for compactness
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                color: color,
                size: 20,
              ), // Added size: 20
            ],
          ),
        ),
      ),
    );
  }

  /// Build puzzle mode card (compact version)
  Widget _buildModeCard(
    BuildContext context,
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
          padding: const EdgeInsets.all(10.0), // Reduced from 12 to 10
          child: Column(
            mainAxisSize: MainAxisSize.min, // Use min size to prevent overflow
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Icon container
              Container(
                padding: const EdgeInsets.all(8), // Reduced from 10 to 8
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ), // Reduced from 32 to 28
              ),
              const SizedBox(height: 6), // Reduced from 8 to 6
              // Title text with flexible sizing
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ), // Changed from titleMedium to titleSmall
                  textAlign: TextAlign.center,
                  maxLines: 2, // Allow wrapping for long titles
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 3), // Reduced from 4 to 3
              // Description text with flexible sizing
              Flexible(
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize:
                        12, // Increased from 11 to 12 for better readability
                  ),
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
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }
}
