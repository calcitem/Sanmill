// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_card.dart
//
// Widget representing a puzzle card in the list

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
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
    super.key,
  });

  final PuzzleInfo puzzle;
  final PuzzleProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool? isSelected;
  final bool showCustomBadge;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool isCompleted = progress?.completed ?? false;
    final int stars = progress?.stars ?? 0;
    final bool showSelection = isSelected != null;
    final bool selected = isSelected ?? false;

    return Card(
      elevation: selected ? 8 : 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: selected ? Colors.blue.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Title
                        Text(
                          puzzle.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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

            // Edit button for custom puzzles (bottom-left corner to avoid overlap)
            if (onEdit != null && !showSelection)
              Positioned(
                bottom: 8,
                left: 8,
                child: Material(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        FluentIcons.edit_24_regular,
                        size: 20,
                        color: Colors.blue[300],
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
