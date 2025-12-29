// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_card.dart
//
// Widget representing a puzzle card in the list

import 'package:flutter/material.dart';

import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
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
      return Dismissible(
        key: Key(puzzle.id),
        // Background for swipe right (edit) - shows on the left
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20.0),
          color: Colors.blue,
          child: const Icon(Icons.edit, color: Colors.white, size: 30),
        ),
        // Secondary background for swipe left (delete) - shows on the right
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20.0),
          color: Colors.red,
          child: const Icon(Icons.delete, color: Colors.white, size: 30),
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
                        style: const TextStyle(color: Colors.red),
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
    return Card(
      elevation: selected ? 8 : 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: selected ? Colors.blue.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Selection indicator (if in multi-select mode)
              if (showSelection) ...<Widget>[
                Checkbox(value: selected, onChanged: (_) => onTap?.call()),
                const SizedBox(width: 8),
              ],
              // Mini board showing puzzle position
              SizedBox(
                width: 64,
                height: 64,
                child: MiniBoard(
                  boardLayout: _extractBoardLayout(puzzle.initialPosition),
                ),
              ),
              const SizedBox(width: 12),

              // Puzzle info
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Title
                    Text(
                      puzzle.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Description
                    Text(
                      puzzle.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Difficulty and category badges
                    Wrap(
                      spacing: 4,
                      children: <Widget>[
                        _buildBadge(
                          puzzle.difficulty.getDisplayName(S.of, context),
                          _getDifficultyColor(),
                        ),
                        _buildBadge(
                          puzzle.category.getDisplayName(S.of, context),
                          Colors.blue,
                        ),
                        if (showCustomBadge)
                          _buildBadge(s.puzzleCustom, Colors.purple),
                        if (_isRuleMismatch())
                          _buildBadge(s.puzzleRuleMismatch, Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),

              // Progress indicator
              if (!showSelection)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (isCompleted)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 32,
                      )
                    else
                      const Icon(
                        Icons.radio_button_unchecked,
                        color: Colors.grey,
                        size: 32,
                      ),
                    const SizedBox(height: 4),

                    // Stars
                    if (isCompleted) _buildStars(stars),
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
  /// Example: "OO******/********/******** w p p 2 7 0 9 0 0 0 0 0 0 0 0 1"
  /// Returns just the board layout part: "OO******/********/********"
  String _extractBoardLayout(String fen) {
    final List<String> parts = fen.split(' ');
    if (parts.isEmpty) {
      // Return empty board if FEN is invalid
      return '********/********/********';
    }
    return parts[0];
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStars(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(
        3,
        (int index) => Icon(
          index < count ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 16,
        ),
      ),
    );
  }

  Color _getDifficultyColor() {
    switch (puzzle.difficulty) {
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
