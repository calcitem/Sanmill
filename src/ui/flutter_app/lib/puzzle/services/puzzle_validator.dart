// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
  PuzzleValidator({required this.puzzle}) {
    // Pre-compute opponent piece baseline for capture objectives.
    final Position initial = Position();
    final bool ok = initial.setFen(puzzle.initialPosition);
    assert(
      ok,
      'PuzzleValidator failed to load initial position for puzzle ${puzzle.id}.',
    );
    _puzzleOpponentSide = initial.sideToMove.opponent;
    _initialOpponentPiecesTotal = _countPieces(initial, _puzzleOpponentSide);
  }

  static const String _tag = "[PuzzleValidator]";

  final PuzzleInfo puzzle;
  late final PieceColor _puzzleOpponentSide;
  late final int _initialOpponentPiecesTotal;
  bool _warnedMissingCaptureTarget = false;

  /// Full move history in notation form (player + opponent).
  ///
  /// Puzzle mode records all moves from the mainline (including auto-played
  /// opponent responses) to keep validation consistent with how solutions are
  /// stored (a complete move sequence with sides).
  final List<String> _playerMoves = <String>[];

  /// Add a move to the solution
  void addMove(String move) {
    _playerMoves.add(move);
    logger.t("$_tag Move added: $move (total: ${_playerMoves.length} moves)");
  }

  /// Undo the last move
  void undoLastMove() {
    if (_playerMoves.isNotEmpty) {
      final String removedMove = _playerMoves.removeLast();
      logger.t(
        "$_tag Move undone: $removedMove (remaining: ${_playerMoves.length} moves)",
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
    //
    // IMPORTANT: For custom puzzles (and for some rule variants), completing the
    // intended solution line may not always put the engine into an "objective"
    // state (e.g. `Act.remove` might not be used for mill formation in placing
    // phase). In that case, requiring `_checkObjective()` would incorrectly
    // block completion. Therefore, a full solution match is always considered
    // correct.
    final PuzzleSolution? matchedSolution = _findMatchingSolution();
    if (matchedSolution != null) {
      return ValidationFeedback(
        result: ValidationResult.correct,
        isOptimal: matchedSolution.isOptimal,
        moveCount: _playerMoves.length,
      );
    }

    // Check if still in progress (objective not met)
    final bool objectiveMet = _checkObjective(currentPosition);
    if (!objectiveMet) {
      return ValidationFeedback(
        result: ValidationResult.inProgress,
        moveCount: _playerMoves.length,
      );
    }

    // Objective met but move sequence doesn't match - this is WRONG
    // The user likely exploited the puzzle by making opponent play poorly
    logger.w("$_tag Objective met but solution differs - likely exploited");
    return ValidationFeedback(
      result: ValidationResult.wrong,
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
    final int? targetCaptures = _inferTargetCaptureCount();
    if (targetCaptures == null || targetCaptures <= 0) {
      if (!_warnedMissingCaptureTarget) {
        _warnedMissingCaptureTarget = true;
        logger.w(
          '$_tag capturePieces objective target is not specified. '
          'Add a number to the title/description (e.g. "Capture 2 pieces") '
          'or rely on exact solution matching.',
        );
      }
      return false;
    }

    final int currentOpponentTotal = _countPieces(
      position,
      _puzzleOpponentSide,
    );
    return currentOpponentTotal <= _initialOpponentPiecesTotal - targetCaptures;
  }

  /// Check if player's moves match any solution sequence
  bool _matchesAnySolution() {
    return _findMatchingSolution() != null;
  }

  static int _countPieces(Position position, PieceColor side) {
    final int onBoard = position.pieceOnBoardCount[side] ?? 0;
    final int inHand = position.pieceInHandCount[side] ?? 0;
    return onBoard + inHand;
  }

  int? _inferTargetCaptureCount() {
    // 1. Try to find explicit tag "capture:N" or "target:N"
    for (final String tag in puzzle.tags) {
      if (tag.startsWith('capture:') || tag.startsWith('target:')) {
        final List<String> parts = tag.split(':');
        if (parts.length == 2) {
          final int? value = int.tryParse(parts[1].trim());
          if (value != null && value > 0) {
            return value;
          }
        }
      }
    }

    // 2. Fallback to parsing title/description
    int? fromText(String text) {
      final RegExpMatch? match = RegExp(r'\d+').firstMatch(text);
      if (match == null) {
        return null;
      }
      final int? value = int.tryParse(match.group(0) ?? '');
      if (value == null || value <= 0) {
        return null;
      }
      return value;
    }

    return fromText(puzzle.title) ?? fromText(puzzle.description);
  }

  PuzzleSolution? _findMatchingSolution() {
    for (final PuzzleSolution solution in puzzle.solutions) {
      if (_matchesSolution(solution)) {
        return solution;
      }
    }
    return null;
  }

  /// Check if player's moves match a specific solution
  bool _matchesSolution(PuzzleSolution solution) {
    // Solutions are stored as a complete move sequence (player + opponent).
    // Compare against the full expected line so that auto-played opponent moves
    // don't break validation.
    final List<PuzzleMove> expectedMoves = solution.moves;

    if (_playerMoves.length != expectedMoves.length) {
      return false;
    }

    for (int i = 0; i < _playerMoves.length; i++) {
      if (!_movesEquivalent(_playerMoves[i], expectedMoves[i].notation)) {
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

  /// Reset validator state
  void reset() {
    _playerMoves.clear();
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
