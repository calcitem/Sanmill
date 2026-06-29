// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzles_home_page.dart
//
// Main hub page for all puzzle modes and features

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/widgets/lichess_list_section.dart';
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(s.puzzles)),
      body: ListTileTheme.merge(
        iconColor: theme.colorScheme.primary,
        child: ListView(
          key: const Key('puzzles_home_list'),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: <Widget>[
            _buildStatsSection(context, s),
            _buildPuzzleSection(context, s),
          ],
        ),
      ),
    );
  }

  /// Build overall statistics section.
  Widget _buildStatsSection(BuildContext context, S s) {
    return ValueListenableBuilder<PuzzleSettings>(
      valueListenable: _puzzleManager.settingsNotifier,
      builder: (BuildContext context, PuzzleSettings settings, Widget? child) {
        final Map<String, dynamic> stats = _puzzleManager.getStatistics();

        return LichessListSection(
          header: Text(s.yourProgress),
          cardKey: const Key('puzzles_home_progress_section'),
          hasLeading: false,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      _buildStatItem(
                        context,
                        s.totalPuzzles,
                        stats['totalPuzzles'].toString(),
                        FluentIcons.puzzle_piece_24_regular,
                        Theme.of(context).colorScheme.primary,
                      ),
                      _buildStatItem(
                        context,
                        s.completed,
                        stats['completedPuzzles'].toString(),
                        FluentIcons.checkmark_circle_24_regular,
                        Theme.of(context).colorScheme.tertiary,
                      ),
                      _buildStatItem(
                        context,
                        s.totalStars,
                        stats['totalStars'].toString(),
                        FluentIcons.star_24_regular,
                        Theme.of(context).colorScheme.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value:
                        ((stats['completionPercentage'] as num?)?.toDouble() ??
                            0.0) /
                        100,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
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
          ],
        );
      },
    );
  }

  Widget _buildPuzzleSection(BuildContext context, S s) {
    return LichessListSection(
      header: Text(s.puzzles),
      cardKey: const Key('puzzles_home_modes_section'),
      children: <Widget>[
        _PuzzleHomeTile(
          key: const Key('puzzles_home_daily'),
          icon: FluentIcons.calendar_star_24_regular,
          title: s.dailyPuzzle,
          subtitle: s.dailyPuzzleDesc,
          onTap: () => _navigateTo(context, const DailyPuzzlePage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_all'),
          icon: FluentIcons.puzzle_piece_24_regular,
          title: s.allPuzzles,
          subtitle: s.allPuzzlesDesc,
          onTap: () => _navigateTo(context, const PuzzleListPage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_rush'),
          icon: FluentIcons.flash_24_regular,
          title: s.puzzleRush,
          subtitle: s.puzzleRushDesc,
          onTap: () => _navigateTo(context, const PuzzleRushPage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_streak'),
          icon: FluentIcons.flash_24_filled,
          title: s.puzzleStreak,
          subtitle: s.puzzleStreakDesc,
          onTap: () => _navigateTo(context, const PuzzleStreakPage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_custom'),
          icon: FluentIcons.edit_24_regular,
          title: s.customPuzzles,
          subtitle: s.customPuzzlesDesc,
          onTap: () => _navigateTo(context, const CustomPuzzlesPage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_history'),
          icon: FluentIcons.history_24_regular,
          title: s.puzzleHistory,
          subtitle: s.puzzleHistoryDesc,
          onTap: () => _navigateTo(context, const PuzzleHistoryPage()),
        ),
        _PuzzleHomeTile(
          key: const Key('puzzles_home_stats'),
          icon: FluentIcons.chart_multiple_24_regular,
          title: s.puzzleStatistics,
          subtitle: s.puzzleStatisticsDesc,
          onTap: () => _navigateTo(context, const PuzzleStatsPage()),
        ),
      ],
    );
  }

  /// Build a single stat item.
  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Flexible(
      child: Column(
        children: <Widget>[
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
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

  /// Navigate to a page
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }
}

class _PuzzleHomeTile extends StatelessWidget {
  const _PuzzleHomeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Theme.of(context).platform == TargetPlatform.iOS
          ? const Icon(FluentIcons.chevron_right_24_regular)
          : null,
      onTap: onTap,
    );
  }
}
