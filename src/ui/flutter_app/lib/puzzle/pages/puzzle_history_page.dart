// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_history_page.dart
//
// Page showing history of all attempted puzzles

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/lichess_list_section.dart';
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
  static const String _filterAll = 'all';
  static const String _filterSuccess = 'success';
  static const String _filterFailed = 'failed';

  final PuzzleRatingService _ratingService = PuzzleRatingService();
  final PuzzleManager _puzzleManager = PuzzleManager();

  bool _showSuccessOnly = false;
  bool _showFailedOnly = false;

  @override
  Widget build(BuildContext context) {
    assert(
      !(_showSuccessOnly && _showFailedOnly),
      'Puzzle history cannot filter by success and failure simultaneously.',
    );

    final S s = S.of(context);
    final ThemeData theme = Theme.of(context);
    final List<PuzzleAttemptResult> filteredHistory = _filteredHistory(
      _ratingService.getAttemptHistory(),
    );

    return Scaffold(
      key: const Key('puzzle_history_page_scaffold'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(s.puzzleHistory),
        actions: <Widget>[_buildFilterMenu(context, s)],
      ),
      body: filteredHistory.isEmpty
          ? _buildEmptyState(context, s)
          : ListTileTheme.merge(
              iconColor: theme.colorScheme.primary,
              child: ListView(
                key: const Key('puzzle_history_page_list'),
                padding: const EdgeInsets.only(top: 16, bottom: 24),
                children: <Widget>[
                  LichessListSection(
                    header: Text(_currentFilterLabel(s)),
                    cardKey: const Key('puzzle_history_entries_section'),
                    children: List<Widget>.generate(filteredHistory.length, (
                      int index,
                    ) {
                      final PuzzleAttemptResult attempt =
                          filteredHistory[index];
                      final PuzzleInfo? puzzle = _puzzleManager.getPuzzleById(
                        attempt.puzzleId,
                      );
                      return _buildHistoryTile(context, attempt, puzzle, s);
                    }, growable: false),
                  ),
                ],
              ),
            ),
    );
  }

  List<PuzzleAttemptResult> _filteredHistory(
    List<PuzzleAttemptResult> history,
  ) {
    if (_showSuccessOnly) {
      return history.where((PuzzleAttemptResult r) => r.success).toList();
    }
    if (_showFailedOnly) {
      return history.where((PuzzleAttemptResult r) => !r.success).toList();
    }
    return history;
  }

  Widget _buildFilterMenu(BuildContext context, S s) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;

    return PopupMenuButton<String>(
      key: const Key('puzzle_history_filter_button'),
      icon: const Icon(FluentIcons.filter_24_regular),
      initialValue: _currentFilterValue,
      onSelected: _selectFilter,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        _buildFilterItem(
          value: _filterAll,
          icon: FluentIcons.apps_list_24_regular,
          label: s.all,
          color: colorScheme.primary,
        ),
        _buildFilterItem(
          value: _filterSuccess,
          icon: FluentIcons.checkmark_circle_24_regular,
          label: s.puzzleHistorySuccess,
          color: customColors.good,
        ),
        _buildFilterItem(
          value: _filterFailed,
          icon: FluentIcons.dismiss_circle_24_regular,
          label: s.puzzleHistoryFailed,
          color: colorScheme.error,
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildFilterItem({
    required String value,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String get _currentFilterValue {
    if (_showSuccessOnly) {
      return _filterSuccess;
    }
    if (_showFailedOnly) {
      return _filterFailed;
    }
    return _filterAll;
  }

  String _currentFilterLabel(S s) {
    if (_showSuccessOnly) {
      return s.puzzleHistorySuccess;
    }
    if (_showFailedOnly) {
      return s.puzzleHistoryFailed;
    }
    return s.all;
  }

  void _selectFilter(String value) {
    assert(
      value == _filterAll || value == _filterSuccess || value == _filterFailed,
      'Unsupported puzzle history filter: $value',
    );

    setState(() {
      _showSuccessOnly = value == _filterSuccess;
      _showFailedOnly = value == _filterFailed;
    });
  }

  Widget _buildEmptyState(BuildContext context, S s) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Center(
      key: const Key('puzzle_history_empty_state'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              FluentIcons.history_24_regular,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              s.puzzleHistoryEmpty,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s.puzzleHistoryEmptyHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(
    BuildContext context,
    PuzzleAttemptResult attempt,
    PuzzleInfo? puzzle,
    S s,
  ) {
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool success = attempt.success;
    final Color resultColor = success ? customColors.good : colorScheme.error;
    final IconData resultIcon = success
        ? FluentIcons.checkmark_circle_24_filled
        : FluentIcons.dismiss_circle_24_filled;
    final int? ratingChange = attempt.ratingChange;

    return ListTile(
      leading: Icon(resultIcon, color: resultColor),
      title: Text(
        puzzle?.title ?? s.puzzleHistoryUnknown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _buildDetailChips(context, attempt, puzzle, s),
            ),
            const SizedBox(height: 6),
            Text(
              _formatTimestamp(context, attempt.timestamp, s),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      trailing: ratingChange == null
          ? null
          : _PuzzleHistoryRatingDelta(value: ratingChange),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  List<Widget> _buildDetailChips(
    BuildContext context,
    PuzzleAttemptResult attempt,
    PuzzleInfo? puzzle,
    S s,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return <Widget>[
      _PuzzleHistoryDetailChip(
        icon: FluentIcons.timer_24_regular,
        label: _formatDuration(attempt.timeSpent),
        color: colorScheme.primary,
      ),
      if (attempt.hintsUsed > 0)
        _PuzzleHistoryDetailChip(
          icon: FluentIcons.lightbulb_24_regular,
          label: '${attempt.hintsUsed} ${s.puzzleHistoryHints}',
          color: colorScheme.tertiary,
        ),
      if (puzzle != null)
        _PuzzleHistoryDetailChip(
          icon: puzzle.difficulty.icon,
          label: puzzle.difficulty.displayName(context),
          color: _getDifficultyColor(context, puzzle.difficulty),
        ),
    ];
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

  Color _getDifficultyColor(BuildContext context, PuzzleDifficulty difficulty) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;

    switch (difficulty) {
      case PuzzleDifficulty.beginner:
      case PuzzleDifficulty.easy:
        return customColors.good;
      case PuzzleDifficulty.medium:
        return colorScheme.tertiary;
      case PuzzleDifficulty.hard:
      case PuzzleDifficulty.expert:
        return colorScheme.error;
      case PuzzleDifficulty.master:
        return colorScheme.secondary;
    }
  }
}

class _PuzzleHistoryDetailChip extends StatelessWidget {
  const _PuzzleHistoryDetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 168),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
      ),
    );
  }
}

class _PuzzleHistoryRatingDelta extends StatelessWidget {
  const _PuzzleHistoryRatingDelta({required this.value});

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
