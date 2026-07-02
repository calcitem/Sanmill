// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_card.dart
//
// Widget representing a puzzle card in the list

import 'package:flutter/material.dart';

import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../models/puzzle_models.dart';

/// Card widget for displaying a puzzle in the list
class PuzzleCard extends StatelessWidget {
  const PuzzleCard({
    required this.puzzle,
    this.progress,
    this.onTap,
    this.onLongPress,
    this.isSelected,
    this.showCustomBadge = false,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final PuzzleInfo puzzle;
  final PuzzleProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool? isSelected;
  final bool showCustomBadge;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Check if puzzle rules match current settings
  bool _isRuleMismatch() {
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    return puzzle.ruleVariantId != currentVariant.id;
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool isCompleted = progress?.completed ?? false;
    final int stars = progress?.stars ?? 0;
    final bool showSelection = isSelected != null;
    final bool selected = isSelected ?? false;

    // If both edit and delete callbacks are provided, wrap in Dismissible for swipe actions
    if (onEdit != null && onDelete != null && !showSelection) {
      final ColorScheme colorScheme = Theme.of(context).colorScheme;
      return Dismissible(
        key: Key(puzzle.id),
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20.0),
          color: colorScheme.primary,
          child: Icon(Icons.edit, color: colorScheme.onPrimary, size: 30),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20.0),
          color: colorScheme.error,
          child: Icon(Icons.delete, color: colorScheme.onError, size: 30),
        ),
        confirmDismiss: (DismissDirection direction) async {
          if (direction == DismissDirection.endToStart) {
            // Swipe left shows delete - need confirmation
            return showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text(s.confirm),
                  content: Text(s.puzzleDeleteConfirm(1)),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(s.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        s.delete,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ],
                );
              },
            );
          } else if (direction == DismissDirection.startToEnd) {
            // Swipe right triggers edit - don't dismiss, just execute callback
            onEdit?.call();
            return false; // Don't dismiss the card
          }
          return false;
        },
        onDismissed: (DismissDirection direction) {
          // Only delete callback should reach here (after confirmation)
          if (direction == DismissDirection.endToStart) {
            onDelete?.call();
          }
        },
        child: _buildCard(
          context,
          s,
          isCompleted,
          stars,
          showSelection,
          selected,
        ),
      );
    }

    // No swipe actions - return card directly
    return _buildCard(context, s, isCompleted, stars, showSelection, selected);
  }

  /// Build the card content
  Widget _buildCard(
    BuildContext context,
    S s,
    bool isCompleted,
    int stars,
    bool showSelection,
    bool selected,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppCustomColors customColors = theme.extension<AppCustomColors>()!;
    final Color cardColor = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.56)
        : colorScheme.surfaceContainer;
    final Color borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.28);

    return Card(
      key: Key('puzzle_card_${puzzle.id}'),
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showSelection) ...<Widget>[
                Checkbox(value: selected, onChanged: (_) => onTap?.call()),
                const SizedBox(width: 8),
              ],
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: MiniBoard(
                      boardLayout: _extractBoardLayout(puzzle.initialPosition),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      puzzle.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      puzzle.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _buildBadge(
                          context,
                          puzzle.difficulty.getDisplayName(S.of, context),
                          _getDifficultyColor(context),
                        ),
                        _buildBadge(
                          context,
                          puzzle.category.getDisplayName(S.of, context),
                          colorScheme.primary,
                        ),
                        if (showCustomBadge)
                          _buildBadge(
                            context,
                            s.puzzleCustom,
                            colorScheme.secondary,
                          ),
                        if (_isRuleMismatch())
                          _buildBadge(
                            context,
                            s.puzzleRuleMismatch,
                            colorScheme.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!showSelection)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (isCompleted)
                      Icon(
                        Icons.check_circle,
                        color: customColors.good,
                        size: 32,
                      ),
                    const SizedBox(height: 4),
                    _buildStars(context, stars),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Extract board layout from FEN string
  /// FEN format: "boardLayout activeColor phase action counts..."
  /// Example: "OO******/********/******** w p p 2 7 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes"
  /// Returns just the board layout part: "OO******/********/********"
  String _extractBoardLayout(String fen) {
    final String trimmedFen = fen.trim();
    assert(trimmedFen.isNotEmpty, 'Puzzle initial position must not be empty.');
    final List<String> parts = trimmedFen.split(' ');
    assert(
      parts.first.isNotEmpty,
      'Puzzle initial position must have a board.',
    );
    return parts[0];
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStars(BuildContext context, int count) {
    final Color color = Theme.of(context).colorScheme.tertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(
        3,
        (int index) => Icon(
          index < count ? Icons.star : Icons.star_border,
          color: color,
          size: 16,
        ),
      ),
    );
  }

  Color _getDifficultyColor(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppCustomColors customColors = Theme.of(
      context,
    ).extension<AppCustomColors>()!;

    switch (puzzle.difficulty) {
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
