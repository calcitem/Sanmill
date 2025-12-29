// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_history_page.dart
//
// Page showing history of all attempted puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../appearance_settings/models/color_settings.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_manager.dart';
import '../services/puzzle_rating_service.dart';

/// Page displaying puzzle attempt history
class PuzzleHistoryPage extends StatefulWidget {
  const PuzzleHistoryPage({super.key});

  @override
  State<PuzzleHistoryPage> createState() => _PuzzleHistoryPageState();
}

class _PuzzleHistoryPageState extends State<PuzzleHistoryPage> {
  final PuzzleRatingService _ratingService = PuzzleRatingService();
  final PuzzleManager _puzzleManager = PuzzleManager();

  // Filter options
  bool _showSuccessOnly = false;
  bool _showFailedOnly = false;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final List<PuzzleAttemptResult> history = _ratingService
        .getAttemptHistory();

    // Apply filters
    List<PuzzleAttemptResult> filteredHistory = history;
    if (_showSuccessOnly) {
      filteredHistory = history
          .where((PuzzleAttemptResult r) => r.success)
          .toList();
    } else if (_showFailedOnly) {
      filteredHistory = history
          .where((PuzzleAttemptResult r) => !r.success)
          .toList();
    }

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
                  title: Text(
                    s.puzzleHistory,
                    style: useDarkSettingsUi
                        ? null
                        : AppTheme.appBarTheme.titleTextStyle,
                  ),
                  actions: <Widget>[
                    // Filter menu
                    PopupMenuButton<String>(
                      icon: const Icon(FluentIcons.filter_24_regular),
                      onSelected: (String value) {
                        setState(() {
                          if (value == 'all') {
                            _showSuccessOnly = false;
                            _showFailedOnly = false;
                          } else if (value == 'success') {
                            _showSuccessOnly = true;
                            _showFailedOnly = false;
                          } else if (value == 'failed') {
                            _showSuccessOnly = false;
                            _showFailedOnly = true;
                          }
                        });
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'all',
                              child: Row(
                                children: <Widget>[
                                  const Icon(FluentIcons.apps_list_24_regular),
                                  const SizedBox(width: 12),
                                  Text(s.all),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'success',
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    FluentIcons.checkmark_circle_24_regular,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(s.puzzleHistorySuccess),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'failed',
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    FluentIcons.dismiss_circle_24_regular,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(s.puzzleHistoryFailed),
                                ],
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
                body: filteredHistory.isEmpty
                    ? _buildEmptyState(s)
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: filteredHistory.length,
                        itemBuilder: (BuildContext context, int index) {
                          final PuzzleAttemptResult attempt =
                              filteredHistory[index];
                          final PuzzleInfo? puzzle = _puzzleManager
                              .getPuzzleById(attempt.puzzleId);
                          return _buildHistoryCard(attempt, puzzle, s);
                        },
                      ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(S s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            FluentIcons.history_24_regular,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            s.puzzleHistoryEmpty,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            s.puzzleHistoryEmptyHint,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    PuzzleAttemptResult attempt,
    PuzzleInfo? puzzle,
    S s,
  ) {
    final bool success = attempt.success;
    final Color resultColor = success ? Colors.green : Colors.red;
    final IconData resultIcon = success
        ? FluentIcons.checkmark_circle_24_filled
        : FluentIcons.dismiss_circle_24_filled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header row
            Row(
              children: <Widget>[
                Icon(resultIcon, color: resultColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    puzzle?.title ?? s.puzzleHistoryUnknown,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (attempt.ratingChange != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (attempt.ratingChange! >= 0
                                  ? Colors.green
                                  : Colors.red)
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${attempt.ratingChange! >= 0 ? '+' : ''}${attempt.ratingChange}',
                      style: TextStyle(
                        color: attempt.ratingChange! >= 0
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Details row - Use Row with Flexible instead of Wrap to prevent overflow
            Row(
              children: <Widget>[
                Flexible(
                  child: _buildDetailChip(
                    FluentIcons.timer_24_regular,
                    _formatDuration(attempt.timeSpent),
                    Colors.blue,
                  ),
                ),
                if (attempt.hintsUsed > 0) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildDetailChip(
                      FluentIcons.lightbulb_24_regular,
                      '${attempt.hintsUsed} ${s.puzzleHistoryHints}',
                      Colors.orange,
                    ),
                  ),
                ],
                if (puzzle != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Flexible(
                    child: _buildDetailChip(
                      puzzle.difficulty.icon,
                      puzzle.difficulty.displayName(context),
                      _getDifficultyColor(puzzle.difficulty),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Timestamp
            Text(
              _formatTimestamp(context, attempt.timestamp, s),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp, S s) {
    final Duration diff = DateTime.now().difference(timestamp);

    if (diff.inDays > 30) {
      return MaterialLocalizations.of(context).formatShortDate(timestamp);
    } else if (diff.inDays > 0) {
      return s.daysAgo(diff.inDays);
    } else if (diff.inHours > 0) {
      return s.hoursAgo(diff.inHours);
    } else if (diff.inMinutes > 0) {
      return s.minutesAgo(diff.inMinutes);
    } else {
      return s.justNow;
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
