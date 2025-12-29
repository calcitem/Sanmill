// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_validator.dart
//
// Validates puzzle solutions and provides feedback

import '../../game_page/services/mill.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';

/// Result of puzzle validation
enum ValidationResult {
  /// Solution is correct
  correct,

  /// Solution is wrong
  wrong,

  /// Puzzle is still in progress
  inProgress,

  /// Invalid move attempted
  invalidMove,
}

/// Detailed validation feedback
class ValidationFeedback {
  ValidationFeedback({
    required this.result,
    this.message,
    this.isOptimal = false,
    this.moveCount = 0,
  });

  final ValidationResult result;
  final String? message;
  final bool isOptimal;
  final int moveCount;
}

/// Service for validating puzzle solutions
class PuzzleValidator {
  PuzzleValidator({required this.puzzle});

  static const String _tag = "[PuzzleValidator]";

  final PuzzleInfo puzzle;
  final List<String> _playerMoves = <String>[];
  int _currentMoveIndex = 0;

  /// Add a move to the solution
  void addMove(String move) {
    _playerMoves.add(move);
    _currentMoveIndex++;
    logger.t("$_tag Move added: $move (total: $_currentMoveIndex moves)");
  }

  /// Undo the last move
  void undoLastMove() {
    if (_playerMoves.isNotEmpty) {
      final String removedMove = _playerMoves.removeLast();
      if (_currentMoveIndex > 0) {
        _currentMoveIndex--;
      }
      logger.t(
        "$_tag Move undone: $removedMove (remaining: $_currentMoveIndex moves)",
      );
    }
  }

  /// Get current move count
  int get moveCount => _playerMoves.length;

  /// Get player's moves
  List<String> get playerMoves => List<String>.unmodifiable(_playerMoves);

  /// Validate the current solution
  ValidationFeedback validateSolution(Position currentPosition) {
    logger.i("$_tag Validating solution for puzzle ${puzzle.id}");
    logger.t("$_tag Player moves: $_playerMoves");

    // First, check if the move sequence matches any expected solution.
    // This prevents exploiting the puzzle by making opponent play poorly.
    final bool matchesSolution = _matchesAnySolution();

    if (matchesSolution) {
      // Verify objective is also met
      final bool objectiveMet = _checkObjective(currentPosition);
      if (objectiveMet) {
        final bool isOptimal = _playerMoves.length <= puzzle.optimalMoveCount;
        return ValidationFeedback(
          result: ValidationResult.correct,
          message: isOptimal
              ? "Perfect! Solved in optimal moves!"
              : "Correct! (${_playerMoves.length} moves, optimal: ${puzzle.optimalMoveCount})",
          isOptimal: isOptimal,
          moveCount: _playerMoves.length,
        );
      }
    }

    // Check if still in progress (objective not met)
    final bool objectiveMet = _checkObjective(currentPosition);
    if (!objectiveMet) {
      return ValidationFeedback(
        result: ValidationResult.inProgress,
        message: "Keep going! The objective hasn't been achieved yet.",
        moveCount: _playerMoves.length,
      );
    }

    // Objective met but move sequence doesn't match - this is WRONG
    // The user likely exploited the puzzle by making opponent play poorly
    logger.w("$_tag Objective met but solution differs - likely exploited");
    return ValidationFeedback(
      result: ValidationResult.wrong,
      message:
          "Objective reached but not following the correct sequence. Try to match the intended solution.",
      moveCount: _playerMoves.length,
    );
  }

  /// Check if the puzzle objective is met
  bool _checkObjective(Position position) {
    switch (puzzle.category) {
      case PuzzleCategory.formMill:
        // Check if a mill was formed by the last move
        return _checkMillFormed(position);

      case PuzzleCategory.capturePieces:
        // Check if required pieces were captured
        return _checkPiecesCaptured(position);

      case PuzzleCategory.winGame:
      case PuzzleCategory.endgame:
        // Check if the game is won
        return position.winner != PieceColor.nobody;

      case PuzzleCategory.defend:
        // Check if position is still viable (not lost)
        return position.winner != position.sideToMove.opponent;

      case PuzzleCategory.findBestMove:
      case PuzzleCategory.opening:
      case PuzzleCategory.mixed:
        // These require move sequence validation
        return _matchesAnySolution();
    }
  }

  /// Check if a mill was formed
  bool _checkMillFormed(Position position) {
    // A mill should have been formed in the current position
    // This is indicated by the ability to remove opponent's piece
    return position.action == Act.remove;
  }

  /// Check if required pieces were captured
  bool _checkPiecesCaptured(Position position) {
    // Get initial and current piece counts
    // Extract from position notation or track during game
    // For now, check if opponent has fewer pieces
    final int opponentPiecesOnBoard =
        position.pieceOnBoardCount[position.sideToMove.opponent] ?? 0;
    final int opponentPiecesInHand =
        position.pieceInHandCount[position.sideToMove.opponent] ?? 0;

    // If opponent has very few pieces, capture objective likely met
    return (opponentPiecesOnBoard + opponentPiecesInHand) <=
        (puzzle.title.contains('2') ? 2 : 3);
  }

  /// Check if player's moves match any solution sequence
  bool _matchesAnySolution() {
    for (final PuzzleSolution solution in puzzle.solutions) {
      if (_matchesSolution(solution)) {
        return true;
      }
    }
    return false;
  }

  /// Check if player's moves match a specific solution
  bool _matchesSolution(PuzzleSolution solution) {
    // Get only the player moves from the solution
    final List<PuzzleMove> expectedPlayerMoves = solution.getPlayerMoves(
      puzzle.playerSide,
    );

    // Check if the count matches first
    if (_playerMoves.length != expectedPlayerMoves.length) {
      return false;
    }

    // Compare each move
    for (int i = 0; i < _playerMoves.length; i++) {
      if (!_movesEquivalent(_playerMoves[i], expectedPlayerMoves[i].notation)) {
        return false;
      }
    }

    return true;
  }

  /// Check if two moves are equivalent
  bool _movesEquivalent(String move1, String move2) {
    // Normalize moves for comparison
    final String normalized1 = move1.trim().toLowerCase();
    final String normalized2 = move2.trim().toLowerCase();
    return normalized1 == normalized2;
  }

  /// Get next hint move
  String? getHint() {
    if (puzzle.solutions.isEmpty) {
      return null;
    }

    // Get the first (optimal) solution
    final PuzzleSolution firstSolution = puzzle.solutions.first;
    final List<PuzzleMove> playerMoves = firstSolution.getPlayerMoves(
      puzzle.playerSide,
    );

    // Return the next player move in the sequence
    if (_currentMoveIndex < playerMoves.length) {
      return playerMoves[_currentMoveIndex].notation;
    }

    return null;
  }

  /// Get textual hint
  String? getTextHint() {
    return puzzle.hint;
  }

  /// Reset validator state
  void reset() {
    _playerMoves.clear();
    _currentMoveIndex = 0;
    logger.i("$_tag Validator reset for puzzle ${puzzle.id}");
  }

  /// Check if a move is valid (basic validation)
  bool isValidMove(String move) {
    // Basic format validation
    if (move.isEmpty) {
      return false;
    }

    // More advanced validation would involve:
    // - Checking against legal moves in current position
    // - Verifying move notation format
    // For now, accept any non-empty move
    return true;
  }
}
