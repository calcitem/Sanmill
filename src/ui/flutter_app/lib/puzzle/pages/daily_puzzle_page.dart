// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// daily_puzzle_page.dart
//
// Daily puzzle page with rotating puzzles and lightweight progress

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/widgets/lichess_list_section.dart';
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
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      key: const Key('daily_puzzle_page_scaffold'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text(s.dailyPuzzle)),
      body: puzzle == null
          ? Center(
              key: const Key('daily_puzzle_empty_state'),
              child: Text(s.noPuzzlesAvailable),
            )
          : _DailyPuzzleContent(
              dailyInfo: dailyInfo,
              puzzle: puzzle,
              progress: _puzzleManager.getProgress(puzzle.id),
              formatDate: _formatDate,
              difficultyColorFor: (PuzzleDifficulty difficulty) =>
                  _getDifficultyColor(context, difficulty),
              onStartPuzzle: _startPuzzle,
            ),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    assert(
      date.month >= DateTime.january && date.month <= DateTime.december,
      'Daily puzzle date must have a valid month.',
    );
    final S s = S.of(context);
    final List<String> months = <String>[
      s.monthJanuary,
      s.monthFebruary,
      s.monthMarch,
      s.monthApril,
      s.monthMay,
      s.monthJune,
      s.monthJuly,
      s.monthAugust,
      s.monthSeptember,
      s.monthOctober,
      s.monthNovember,
      s.monthDecember,
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Get color for difficulty level
  Color _getDifficultyColor(BuildContext context, PuzzleDifficulty difficulty) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    switch (difficulty) {
      case PuzzleDifficulty.beginner:
        return colorScheme.primary;
      case PuzzleDifficulty.easy:
        return colorScheme.primary;
      case PuzzleDifficulty.medium:
        return colorScheme.tertiary;
      case PuzzleDifficulty.hard:
        return colorScheme.error;
      case PuzzleDifficulty.expert:
        return colorScheme.error;
      case PuzzleDifficulty.master:
        return colorScheme.secondary;
    }
  }

  /// Start the puzzle
  void _startPuzzle(PuzzleInfo puzzle) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => PuzzlePage(
              puzzle: puzzle,
              onSolved: _recordDailyCompletion,
              showSolvedDialogAfterCallback: true,
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() {});
          }
        });
  }

  void _recordDailyCompletion() {
    unawaited(
      _dailyPuzzleService.recordCompletion().then((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    );
  }
}

class _DailyPuzzleContent extends StatelessWidget {
  const _DailyPuzzleContent({
    required this.dailyInfo,
    required this.puzzle,
    required this.progress,
    required this.formatDate,
    required this.difficultyColorFor,
    required this.onStartPuzzle,
  });

  final DailyPuzzleInfo dailyInfo;
  final PuzzleInfo puzzle;
  final PuzzleProgress? progress;
  final String Function(DateTime date) formatDate;
  final Color Function(PuzzleDifficulty difficulty) difficultyColorFor;
  final ValueChanged<PuzzleInfo> onStartPuzzle;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool isCompleted = dailyInfo.completedToday;
    final int stars = progress?.stars ?? 0;

    return ListView(
      key: const Key('daily_puzzle_list'),
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: <Widget>[
        _buildPuzzleSection(context, s, isCompleted, stars),
        _buildDailyInfoSection(context, s),
      ],
    );
  }

  Widget _buildPuzzleSection(
    BuildContext context,
    S s,
    bool isCompleted,
    int stars,
  ) {
    final ThemeData theme = Theme.of(context);
    final Color difficultyColor = difficultyColorFor(puzzle.difficulty);

    return LichessListSection(
      header: Text(s.dailyPuzzle),
      cardKey: const Key('daily_puzzle_card'),
      children: <Widget>[
        ListTile(
          key: const Key('daily_puzzle_summary_tile'),
          leading: Icon(puzzle.category.icon, color: difficultyColor),
          title: Text(
            puzzle.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${puzzle.difficulty.displayName(context)}\n${puzzle.description}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isCompleted
              ? _DailyPuzzleCompletionBadge(stars: stars)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            key: const Key('daily_puzzle_start_button'),
            onPressed: () => onStartPuzzle(puzzle),
            icon: const Icon(FluentIcons.play_24_regular),
            label: Text(isCompleted ? s.tryAgain : s.dailyPuzzleStart),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              textStyle: theme.textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyInfoSection(BuildContext context, S s) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LichessListSection(
      header: Text(formatDate(dailyInfo.date)),
      cardKey: const Key('daily_puzzle_progress_section'),
      children: <Widget>[
        ListTile(
          key: const Key('daily_puzzle_today_tile'),
          leading: Icon(
            FluentIcons.calendar_star_24_regular,
            color: colorScheme.primary,
          ),
          title: Text(s.todayProgress),
          subtitle: Text(s.dailyPuzzleNumber(dailyInfo.dayNumber)),
          trailing: Text(
            dailyInfo.completedToday ? s.completed : s.dailyPuzzleNotCompleted,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: dailyInfo.completedToday
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ListTile(
          key: const Key('daily_puzzle_total_tile'),
          leading: Icon(
            FluentIcons.checkmark_circle_24_regular,
            color: colorScheme.primary,
          ),
          title: Text(s.dailyPuzzleTotalCompleted),
          trailing: Text(
            dailyInfo.totalCompleted.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyPuzzleCompletionBadge extends StatelessWidget {
  const _DailyPuzzleCompletionBadge({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          FluentIcons.checkmark_circle_24_regular,
          color: colorScheme.primary,
          size: 28,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(
            3,
            (int index) => Icon(
              index < stars
                  ? FluentIcons.star_24_filled
                  : FluentIcons.star_24_regular,
              color: colorScheme.tertiary,
              size: 14,
            ),
          ),
        ),
      ],
    );
  }
}
