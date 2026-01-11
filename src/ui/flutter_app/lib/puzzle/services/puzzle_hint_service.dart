// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_hint_service.dart
//
// Provides hints for puzzle solving

import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';

/// Types of hints available
enum HintType {
  /// Textual hint describing the strategy
  textual,

  /// Show the next move
  nextMove,

  /// Highlight pieces involved in the solution
  highlight,

  /// Show the entire solution
  showSolution,
}

/// A hint for solving a puzzle
class PuzzleHint {
  const PuzzleHint({
    required this.type,
    required this.content,
    this.moveIndex,
    this.highlightSquares,
  });

  final HintType type;
  final String content;
  final int? moveIndex;
  final List<int>? highlightSquares;
}

/// Service for managing puzzle hints
class PuzzleHintService {
  PuzzleHintService({required this.puzzle});

  static const String _tag = "[PuzzleHintService]";

  final PuzzleInfo puzzle;
  int _hintsGiven = 0;
  int _currentHintLevel = 0;

  /// Get the next hint
  /// Hints are progressive: textual -> next move -> show solution
  PuzzleHint? getNextHint(int currentPlayerMoveIndex) {
    logger.i(
      "$_tag Getting hint (level $_currentHintLevel) for puzzle ${puzzle.id}",
    );

    if (_currentHintLevel == 0) {
      // First hint: provide textual hint if available
      _currentHintLevel++;
      _hintsGiven++;
      if (puzzle.hint != null && puzzle.hint!.isNotEmpty) {
        return PuzzleHint(type: HintType.textual, content: puzzle.hint!);
      }
      // If no textual hint, fall through to next level
    }

    if (_currentHintLevel == 1) {
      // Second hint: show the next move
      _currentHintLevel++;
      _hintsGiven++;
      final String? nextMove = _getNextPlayerMove(currentPlayerMoveIndex);
      if (nextMove != null) {
        return PuzzleHint(
          type: HintType.nextMove,
          // Store raw move notation; UI layer formats with localization.
          content: nextMove,
          moveIndex: currentPlayerMoveIndex,
        );
      }
    }

    if (_currentHintLevel == 2) {
      // Third hint: show all remaining moves
      _currentHintLevel++;
      _hintsGiven++;
      final String solution = _getFullSolution();
      return PuzzleHint(
        type: HintType.showSolution,
        // Store raw solution string; UI layer formats with localization.
        content: solution,
      );
    }

    // No more hints available
    return null;
  }

  /// Get a specific hint type
  PuzzleHint? getHintOfType(HintType type, int currentPlayerMoveIndex) {
    logger.i("$_tag Getting hint of type $type for puzzle ${puzzle.id}");
    _hintsGiven++;

    switch (type) {
      case HintType.textual:
        if (puzzle.hint != null && puzzle.hint!.isNotEmpty) {
          return PuzzleHint(type: HintType.textual, content: puzzle.hint!);
        }
        return null;

      case HintType.nextMove:
        final String? nextMove = _getNextPlayerMove(currentPlayerMoveIndex);
        if (nextMove != null) {
          return PuzzleHint(
            type: HintType.nextMove,
            // Store raw move notation; UI layer formats with localization.
            content: nextMove,
            moveIndex: currentPlayerMoveIndex,
          );
        }
        return null;

      case HintType.highlight:
        final List<int>? squares = _getHighlightSquares(currentPlayerMoveIndex);
        if (squares != null && squares.isNotEmpty) {
          return PuzzleHint(
            type: HintType.highlight,
            // Store a generic marker; UI layer can provide localized text.
            content: '',
            highlightSquares: squares,
          );
        }
        return null;

      case HintType.showSolution:
        return PuzzleHint(
          type: HintType.showSolution,
          // Store raw solution string; UI layer formats with localization.
          content: _getFullSolution(),
        );
    }
  }

  PuzzleSolution? _getPrimarySolution() {
    return puzzle.optimalSolution ??
        (puzzle.solutions.isNotEmpty ? puzzle.solutions.first : null);
  }

  /// Get the next *player* move (excluding opponent responses).
  ///
  /// The caller passes the number of player moves already made in this attempt.
  String? _getNextPlayerMove(int currentPlayerMoveIndex) {
    final PuzzleSolution? solution = _getPrimarySolution();
    if (solution == null) {
      return null;
    }

    final List<PuzzleMove> playerMoves = solution.getPlayerMoves(
      puzzle.playerSide,
    );
    if (currentPlayerMoveIndex < playerMoves.length) {
      return playerMoves[currentPlayerMoveIndex].notation;
    }

    return null;
  }

  /// Get the full solution as a string
  String _getFullSolution() {
    final PuzzleSolution? solution = _getPrimarySolution();
    if (solution == null) {
      return '';
    }

    final List<String> moveNotations = solution.moves
        .map((PuzzleMove m) => m.notation)
        .toList(growable: false);
    return moveNotations.join(' → ');
  }

  /// Get squares to highlight for the next move
  List<int>? _getHighlightSquares(int currentMoveIndex) {
    final String? nextMove = _getNextPlayerMove(currentMoveIndex);
    if (nextMove == null) {
      return null;
    }

    // Parse the move notation to extract square indices
    // This is simplified - actual implementation would depend on move notation format
    // For now, return an empty list as a placeholder
    return <int>[];
  }

  /// Get number of hints given
  int get hintsGiven => _hintsGiven;

  /// Check if hints are available
  bool get hasHints {
    return puzzle.hint != null || puzzle.solutions.isNotEmpty;
  }

  /// Reset hint state
  void reset() {
    _hintsGiven = 0;
    _currentHintLevel = 0;
    logger.i("$_tag Hint service reset for puzzle ${puzzle.id}");
  }

  /// Get hint cost (for potential hint penalty system)
  int getHintCost(HintType type) {
    switch (type) {
      case HintType.textual:
        return 0; // Free
      case HintType.highlight:
        return 1; // Small cost
      case HintType.nextMove:
        return 2; // Medium cost
      case HintType.showSolution:
        return 3; // High cost
    }
  }
}
