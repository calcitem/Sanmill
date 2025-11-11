// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// daily_puzzle_page.dart
//
// Daily puzzle challenge page with rotating puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/daily_puzzle_service.dart';
import '../services/puzzle_manager.dart';
import 'puzzle_page.dart';

/// Page displaying the daily puzzle challenge
class DailyPuzzlePage extends StatefulWidget {
  const DailyPuzzlePage({super.key});

  @override
  State<DailyPuzzlePage> createState() => _DailyPuzzlePageState();
}

class _DailyPuzzlePageState extends State<DailyPuzzlePage> {
  final DailyPuzzleService _dailyPuzzleService = DailyPuzzleService();
  final PuzzleManager _puzzleManager = PuzzleManager();

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final DailyPuzzleInfo dailyInfo = _dailyPuzzleService.getTodaysPuzzle();
    final PuzzleInfo? puzzle = _puzzleManager.getPuzzleById(dailyInfo.puzzleId);

    if (puzzle == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            s.dailyPuzzle,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: Center(child: Text(s.noPuzzlesAvailable)),
      );
    }

    final PuzzleProgress? progress = _puzzleManager.getProgress(puzzle.id);
    final bool isCompleted = progress?.completed ?? false;
    final int stars = progress?.stars ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.dailyPuzzle,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
        actions: <Widget>[
          // Streak info
          IconButton(
            icon: const Icon(FluentIcons.trophy_24_regular),
            onPressed: () => _showStreakInfo(dailyInfo),
            tooltip: s.dailyPuzzleStreak,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Date and streak card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _formatDate(dailyInfo.date),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              s.dailyPuzzleNumber(dailyInfo.dayNumber),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(
                                  FluentIcons.fire_24_regular,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${dailyInfo.currentStreak}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              s.dailyPuzzleDayStreak,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (dailyInfo.longestStreak >
                        dailyInfo.currentStreak) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        s.dailyPuzzleBestStreak(dailyInfo.longestStreak),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Puzzle info card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          puzzle.category.icon,
                          color: _getDifficultyColor(puzzle.difficulty),
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                puzzle.title,
                                style: Theme.of(context).textTheme.titleLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                puzzle.difficulty.displayName(context),
                                style: TextStyle(
                                  color: _getDifficultyColor(puzzle.difficulty),
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isCompleted) ...<Widget>[
                          Column(
                            children: <Widget>[
                              const Icon(
                                FluentIcons.checkmark_circle_24_regular,
                                color: Colors.green,
                                size: 32,
                              ),
                              Row(
                                children: List<Widget>.generate(
                                  3,
                                  (int index) => Icon(
                                    index < stars
                                        ? FluentIcons.star_24_filled
                                        : FluentIcons.star_24_regular,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      puzzle.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Start button
            ElevatedButton.icon(
              onPressed: () => _startPuzzle(puzzle),
              icon: Icon(
                isCompleted
                    ? FluentIcons.arrow_clockwise_24_regular
                    : FluentIcons.play_24_regular,
              ),
              label: Text(
                isCompleted ? s.tryAgain : s.dailyPuzzleStart,
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: isCompleted ? Colors.blue : Colors.green,
              ),
            ),

            const SizedBox(height: 16),

            // Hint: How to improve streak
            if (!isCompleted)
              Card(
                color: Colors.blue.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        FluentIcons.lightbulb_24_regular,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.dailyPuzzleStreakHint,
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    final List<String> months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Get color for difficulty level
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

  /// Start the puzzle
  void _startPuzzle(PuzzleInfo puzzle) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => PuzzlePage(puzzle: puzzle),
          ),
        )
        .then((_) {
          // Refresh the page when returning
          setState(() {});
        });
  }

  /// Show streak information dialog
  void _showStreakInfo(DailyPuzzleInfo dailyInfo) {
    final S s = S.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: <Widget>[
              const Icon(FluentIcons.trophy_24_regular, color: Colors.orange),
              const SizedBox(width: 8),
              // Wrap text in Expanded to prevent overflow on small screens
              Expanded(
                child: Text(
                  s.dailyPuzzleStreak,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildStreakRow(
                s.dailyPuzzleCurrentStreak,
                '${dailyInfo.currentStreak} ${s.dailyPuzzleDays}',
                FluentIcons.fire_24_regular,
                Colors.orange,
              ),
              const SizedBox(height: 8),
              _buildStreakRow(
                s.dailyPuzzleLongestStreak,
                '${dailyInfo.longestStreak} ${s.dailyPuzzleDays}',
                FluentIcons.trophy_24_regular,
                Colors.amber,
              ),
              const SizedBox(height: 8),
              _buildStreakRow(
                s.dailyPuzzleTotalCompleted,
                dailyInfo.totalCompleted.toString(),
                FluentIcons.checkmark_circle_24_regular,
                Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                s.dailyPuzzleStreakInfo,
                style: Theme.of(context).textTheme.bodySmall,
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

  Widget _buildStreakRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
