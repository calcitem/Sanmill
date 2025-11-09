// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_category.dart

part of 'puzzle_models.dart';

/// Represents the category/type of a puzzle
enum PuzzleCategory {
  /// Form a mill in N moves
  formMill,

  /// Capture N pieces
  capturePieces,

  /// Win the game in N moves
  winGame,

  /// Defend against opponent's threats
  defend,

  /// Find the best move in a complex position
  findBestMove,

  /// Endgame puzzles
  endgame,

  /// Opening phase tactics
  opening,

  /// Mixed/combined tactics
  mixed;

  /// Returns a localized display name for the category
  String getDisplayName(S Function(BuildContext) getS, BuildContext context) {
    final S s = getS(context);
    switch (this) {
      case PuzzleCategory.formMill:
        return s.puzzleCategoryFormMill;
      case PuzzleCategory.capturePieces:
        return s.puzzleCategoryCapturePieces;
      case PuzzleCategory.winGame:
        return s.puzzleCategoryWinGame;
      case PuzzleCategory.defend:
        return s.puzzleCategoryDefend;
      case PuzzleCategory.findBestMove:
        return s.puzzleCategoryFindBestMove;
      case PuzzleCategory.endgame:
        return s.puzzleCategoryEndgame;
      case PuzzleCategory.opening:
        return s.puzzleCategoryOpening;
      case PuzzleCategory.mixed:
        return s.puzzleCategoryMixed;
    }
  }

  /// Returns a localized display name using context (convenience method)
  String displayName(BuildContext context) {
    return getDisplayName(S.of, context);
  }

  /// Returns an icon for this category
  IconData get icon {
    switch (this) {
      case PuzzleCategory.formMill:
        return FluentIcons.target_24_filled;
      case PuzzleCategory.capturePieces:
        return FluentIcons.delete_24_filled;
      case PuzzleCategory.winGame:
        return FluentIcons.trophy_24_filled;
      case PuzzleCategory.defend:
        return FluentIcons.shield_24_filled;
      case PuzzleCategory.findBestMove:
        return FluentIcons.search_24_filled;
      case PuzzleCategory.endgame:
        return FluentIcons.board_24_filled;
      case PuzzleCategory.opening:
        return FluentIcons.book_24_filled;
      case PuzzleCategory.mixed:
        return FluentIcons.grid_24_filled;
    }
  }
}
