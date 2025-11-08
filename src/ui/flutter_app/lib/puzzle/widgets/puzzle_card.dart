// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_card.dart
//
// Widget representing a puzzle card in the list

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../models/puzzle_models.dart';

/// Card widget for displaying a puzzle in the list
class PuzzleCard extends StatelessWidget {
  const PuzzleCard({
    required this.puzzle,
    this.progress,
    this.onTap,
    super.key,
  });

  final PuzzleInfo puzzle;
  final PuzzleProgress? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool isCompleted = progress?.completed ?? false;
    final int stars = progress?.stars ?? 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: <Widget>[
              // Category icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getDifficultyColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  puzzle.category.icon,
                  color: _getDifficultyColor(),
                  size: 28,
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
                      ],
                    ),
                  ],
                ),
              ),

              // Progress indicator
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (isCompleted)
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 32,
                    )
                  else
                    Icon(
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
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
