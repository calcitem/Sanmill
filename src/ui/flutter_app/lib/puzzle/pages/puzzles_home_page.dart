// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzles_home_page.dart
//
// Main hub page for all puzzle modes and features

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../custom_drawer/custom_drawer.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
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

    return ValueListenableBuilder<Box<ColorSettings>>(
      valueListenable: DB().listenColorSettings,
      builder: (BuildContext context, Box<ColorSettings> box, Widget? child) {
        final ColorSettings colors = box.get(
          DB.colorSettingsKey,
          defaultValue: const ColorSettings(),
        )!;
        final bool useDarkSettingsUi = AppTheme.shouldUseDarkSettingsUi(colors);
        final ThemeData settingsTheme = useDarkSettingsUi
            ? AppTheme.buildAccessibleSettingsDarkTheme(colors)
            : Theme.of(context);

        // Use Builder to ensure the context has the correct theme
        return Theme(
          data: settingsTheme,
          child: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                backgroundColor: useDarkSettingsUi
                    ? settingsTheme.scaffoldBackgroundColor
                    : AppTheme.lightBackgroundColor,
                appBar: AppBar(
                  leading: CustomDrawerIcon.of(context)?.drawerIcon,
                  title: Text(
                    s.puzzles,
                    style: useDarkSettingsUi
                        ? null
                        : AppTheme.appBarTheme.titleTextStyle,
                  ),
                  actions: <Widget>[
                    // Statistics overview
                    IconButton(
                      icon: const Icon(FluentIcons.chart_multiple_24_regular),
                      onPressed: () => _showStatistics(context),
                      tooltip: s.puzzleStatistics,
                    ),
                  ],
                ),
                body: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Header with overall stats
                      _buildStatsCard(context, s, useDarkSettingsUi),
                      const SizedBox(height: 12),
                      // Daily Puzzle - Featured
                      _buildFeaturedCard(
                        context,
                        s,
                        title: s.dailyPuzzle,
                        subtitle: s.dailyPuzzleDesc,
                        icon: FluentIcons.calendar_star_24_regular,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary, // Use primary color
                        onTap: () => _navigateTo(context, const DailyPuzzlePage()),
                      ),
                      const SizedBox(height: 12),
                      // Grid of puzzle modes
                      Expanded(
                        child: LayoutBuilder(
                          builder: (
                            BuildContext context,
                            BoxConstraints constraints,
                          ) {
                            // Calculate child aspect ratio to fit all items in the available space
                            // We have 6 items in 2 columns = 3 rows
                            const int crossAxisCount = 2;
                            const int rowCount = 3;
                            const double spacing = 12.0;

                            final double availableHeight = constraints.maxHeight;
                            final double availableWidth = constraints.maxWidth;

                            // Calculate height available for each item
                            // Total height = (rowCount * itemHeight) + ((rowCount - 1) * spacing)
                            // itemHeight = (Total height - ((rowCount - 1) * spacing)) / rowCount
                            final double itemHeight =
                                (availableHeight - ((rowCount - 1) * spacing)) /
                                rowCount;

                            // itemWidth = (Total width - ((crossAxisCount - 1) * spacing)) / crossAxisCount
                            final double itemWidth =
                                (availableWidth -
                                    ((crossAxisCount - 1) * spacing)) /
                                crossAxisCount;

                            // Prevent division by zero or negative values
                            final double childAspectRatio =
                                (itemHeight > 0 && itemWidth > 0)
                                    ? itemWidth / itemHeight
                                    : 1.5; // Default fallback

                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: spacing,
                              crossAxisSpacing: spacing,
                              childAspectRatio: childAspectRatio,
                              physics: const NeverScrollableScrollPhysics(),
                              children: <Widget>[
                          // All Puzzles
                          _buildModeCard(
                            context,
                            s,
                            title: s.allPuzzles,
                            description: s.allPuzzlesDesc,
                            icon: FluentIcons.puzzle_piece_24_regular,
                            color: Theme.of(
                              context,
                            ).colorScheme.primary, // Use primary green
                            onTap: () => _navigateTo(context, const PuzzleListPage()),
                          ),
                          // Puzzle Rush
                          _buildModeCard(
                            context,
                            s,
                            title: s.puzzleRush,
                            description: s.puzzleRushDesc,
                            icon: FluentIcons.flash_24_regular,
                            color: Colors
                                .deepOrange, // Keep energetic orange for "rush" mode
                            onTap: () => _navigateTo(context, const PuzzleRushPage()),
                          ),
                          // Puzzle Streak
                          _buildModeCard(
                            context,
                            s,
                            title: s.puzzleStreak,
                            description: s.puzzleStreakDesc,
                            icon: FluentIcons.flash_24_filled,
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer, // Darker green shade
                            onTap: () => _navigateTo(context, const PuzzleStreakPage()),
                          ),
                          // Custom Puzzles
                          _buildModeCard(
                            context,
                            s,
                            title: s.customPuzzles,
                            description: s.customPuzzlesDesc,
                            icon: FluentIcons.edit_24_regular,
                            color: Colors.lightGreen, // Lighter green variant
                            onTap: () => _navigateTo(context, const CustomPuzzlesPage()),
                          ),
                          // History
                          _buildModeCard(
                            context,
                            s,
                            title: s.puzzleHistory,
                            description: s.puzzleHistoryDesc,
                            icon: FluentIcons.history_24_regular,
                            color: Colors.teal, // Teal stays as complementary color
                            onTap: () => _navigateTo(context, const PuzzleHistoryPage()),
                          ),
                          // Statistics
                          _buildModeCard(
                            context,
                            s,
                            title: s.puzzleStatistics,
                            description: s.puzzleStatisticsDesc,
                            icon: FluentIcons.chart_multiple_24_regular,
                            color: Colors.blueGrey, // Neutral grey-blue for stats
                            onTap: () => _navigateTo(context, const PuzzleStatsPage()),
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
            },
          ),
        );
      },
    );
  }

  /// Build overall statistics card (compact version)
  Widget _buildStatsCard(
    BuildContext context,
    S s,
    bool useDarkSettingsUi,
  ) {
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
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ), // Reduced from 12 to 11
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
                    fontSize: 11,
                  ), // Reduced font size
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

  /// Show statistics dialog
  void _showStatistics(BuildContext context) {
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
