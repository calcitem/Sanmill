// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_difficulty.dart

part of 'puzzle_models.dart';

/// Represents the difficulty level of a puzzle
enum PuzzleDifficulty {
  /// Beginner level - easy puzzles for learning basics
  beginner,

  /// Easy level - simple tactical patterns
  easy,

  /// Medium level - requires some experience
  medium,

  /// Hard level - challenging puzzles
  hard,

  /// Expert level - very difficult puzzles
  expert,

  /// Master level - extremely challenging puzzles
  master;

  /// Returns a localized display name for the difficulty
  String getDisplayName(S Function(BuildContext) getS, BuildContext context) {
    final S s = getS(context);
    switch (this) {
      case PuzzleDifficulty.beginner:
        return s.puzzleDifficultyBeginner;
      case PuzzleDifficulty.easy:
        return s.puzzleDifficultyEasy;
      case PuzzleDifficulty.medium:
        return s.puzzleDifficultyMedium;
      case PuzzleDifficulty.hard:
        return s.puzzleDifficultyHard;
      case PuzzleDifficulty.expert:
        return s.puzzleDifficultyExpert;
      case PuzzleDifficulty.master:
        return s.puzzleDifficultyMaster;
    }
  }

  /// Returns a localized display name using context (convenience method)
  String displayName(BuildContext context) {
    return getDisplayName(S.of, context);
  }

  /// Returns an icon for this difficulty
  IconData get icon {
    switch (this) {
      case PuzzleDifficulty.beginner:
      case PuzzleDifficulty.easy:
      case PuzzleDifficulty.medium:
      case PuzzleDifficulty.hard:
      case PuzzleDifficulty.expert:
      case PuzzleDifficulty.master:
        return FluentIcons.star_24_regular;
    }
  }

  /// Returns the star rating threshold for this difficulty
  /// (moves over optimal to still get 3 stars)
  int get starThreshold {
    switch (this) {
      case PuzzleDifficulty.beginner:
        return 3;
      case PuzzleDifficulty.easy:
        return 2;
      case PuzzleDifficulty.medium:
      case PuzzleDifficulty.hard:
        return 1;
      case PuzzleDifficulty.expert:
      case PuzzleDifficulty.master:
        return 0;
    }
  }
}
