// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzles_home_page.dart
//
// Main hub page for all puzzle modes and features

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../services/puzzle_manager.dart';
import 'custom_puzzles_page.dart';
import 'daily_puzzle_page.dart';
import 'puzzle_battle_page.dart';
import 'puzzle_list_page.dart';
import 'puzzle_rush_page.dart';

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
        title: Text(s.puzzles),
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
              color: Colors.orange,
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
              childAspectRatio: 1.1,
              children: <Widget>[
                // All Puzzles
                _buildModeCard(
                  s,
                  title: s.allPuzzles,
                  description: s.allPuzzlesDesc,
                  icon: FluentIcons.puzzle_piece_24_regular,
                  color: Colors.blue,
                  onTap: () => _navigateTo(const PuzzleListPage()),
                ),
                // Puzzle Rush
                _buildModeCard(
                  s,
                  title: s.puzzleRush,
                  description: s.puzzleRushDesc,
                  icon: FluentIcons.flash_24_regular,
                  color: Colors.red,
                  onTap: () => _navigateTo(const PuzzleRushPage()),
                ),
                // Puzzle Battle
                _buildModeCard(
                  s,
                  title: s.puzzleBattle,
                  description: s.puzzleBattleDesc,
                  icon: FluentIcons.people_24_regular,
                  color: Colors.purple,
                  onTap: () => _navigateTo(const PuzzleBattlePage()),
                ),
                // Custom Puzzles
                _buildModeCard(
                  s,
                  title: s.customPuzzles,
                  description: s.customPuzzlesDesc,
                  icon: FluentIcons.edit_24_regular,
                  color: Colors.green,
                  onTap: () => _navigateTo(const CustomPuzzlesPage()),
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _buildStatItem(
                      s.totalPuzzles,
                      stats['totalPuzzles'].toString(),
                      FluentIcons.puzzle_piece_24_regular,
                      Colors.blue,
                    ),
                    _buildStatItem(
                      s.completed,
                      stats['completedPuzzles'].toString(),
                      FluentIcons.checkmark_circle_24_regular,
                      Colors.green,
                    ),
                    _buildStatItem(
                      s.totalStars,
                      stats['totalStars'].toString(),
                      FluentIcons.star_24_regular,
                      Colors.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: stats['completionPercentage'] / 100,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 8),
                Text(
                  '${stats['completionPercentage'].toStringAsFixed(1)}% ${s.completed}',
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
  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
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
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
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
      color: color.withOpacity(0.1),
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
                  color: color.withOpacity(0.2),
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
      MaterialPageRoute<void>(
        builder: (BuildContext context) => page,
      ),
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
                stats['totalPuzzles'].toString(),
              ),
              _buildStatRow(
                s.completed,
                stats['completedPuzzles'].toString(),
              ),
              _buildStatRow(
                s.totalStars,
                stats['totalStars'].toString(),
              ),
              _buildStatRow(
                s.completionPercentage,
                '${stats['completionPercentage'].toStringAsFixed(1)}%',
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
