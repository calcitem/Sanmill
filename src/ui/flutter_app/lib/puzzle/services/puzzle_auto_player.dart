// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_auto_player.dart
//
// Pure logic helpers for Puzzle mode auto-play:
// - Pick a solution line that matches the current move prefix.
// - Auto-play the opponent's forced responses until it is the human's turn again.

import '../../game_page/services/mill.dart';

/// Outcome of a puzzle auto-play attempt.
enum PuzzleAutoPlayOutcome {
  /// No-op: already the human's turn, or the game is over / inactive.
  noOp,

  /// One or more moves were auto-played successfully.
  playedMoves,

  /// No solution line matches the current move prefix; caller should roll back.
  wrongMove,

  /// A matching solution line exists, but we are already at its end.
  reachedEndOfLine,

  /// Auto-play failed because the expected solution move was illegal.
  illegalAutoMove,
}

/// Puzzle mode helper that keeps the auto-play logic testable and UI-free.
class PuzzleAutoPlayer {
  const PuzzleAutoPlayer();

  /// Normalizes a move string for prefix comparison.
  static String normalizeMove(String move) => move.trim().toLowerCase();

  /// Picks a solution line that matches the current move prefix.
  ///
  /// Returns the first matching solution to keep behavior stable.
  static List<String>? pickSolutionForPrefix({
    required List<List<String>> solutions,
    required List<String> movesSoFar,
  }) {
    if (solutions.isEmpty) {
      return null;
    }

    bool prefixMatches(List<String> solution) {
      if (solution.length < movesSoFar.length) {
        return false;
      }
      for (int i = 0; i < movesSoFar.length; i++) {
        if (normalizeMove(solution[i]) != normalizeMove(movesSoFar[i])) {
          return false;
        }
      }
      return true;
    }

    for (final List<String> solution in solutions) {
      if (prefixMatches(solution)) {
        return solution;
      }
    }
    return null;
  }

  /// Auto-plays the opponent's forced responses until it's the human's turn again.
  ///
  /// This function is UI-free. The caller provides callbacks to:
  /// - read the current side to move and game-over state
  /// - read the current mainline moves
  /// - apply a move
  /// - handle a wrong move (typically: show feedback + undo)
  static Future<PuzzleAutoPlayOutcome> autoPlayOpponentResponses({
    required List<List<String>> solutions,
    required PieceColor humanColor,
    required bool Function() isGameOver,
    required PieceColor Function() sideToMove,
    required List<String> Function() movesSoFar,
    required bool Function(String move) applyMove,
    required Future<void> Function() onWrongMove,
    int maxAutoPlies = 64,
  }) async {
    if (isGameOver()) {
      return PuzzleAutoPlayOutcome.noOp;
    }

    if (sideToMove() == humanColor) {
      return PuzzleAutoPlayOutcome.noOp;
    }

    int played = 0;

    while (!isGameOver() && sideToMove() != humanColor) {
      final List<String> currentMoves = movesSoFar();
      final List<String>? solution = pickSolutionForPrefix(
        solutions: solutions,
        movesSoFar: currentMoves,
      );

      if (solution == null) {
        await onWrongMove();
        return PuzzleAutoPlayOutcome.wrongMove;
      }

      final int nextIndex = currentMoves.length;
      if (nextIndex >= solution.length) {
        return PuzzleAutoPlayOutcome.reachedEndOfLine;
      }

      final String expectedMove = solution[nextIndex];
      final bool ok = applyMove(expectedMove);
      assert(
        ok,
        'Puzzle auto-move failed. The expected solution move is illegal in the current position.',
      );
      if (!ok) {
        return PuzzleAutoPlayOutcome.illegalAutoMove;
      }

      played++;
      assert(
        played <= maxAutoPlies,
        'Puzzle auto-play exceeded maxAutoPlies=$maxAutoPlies. '
        'This likely indicates a loop or an incorrect side-to-move update.',
      );
      if (played > maxAutoPlies) {
        return PuzzleAutoPlayOutcome.illegalAutoMove;
      }
    }

    return played > 0
        ? PuzzleAutoPlayOutcome.playedMoves
        : PuzzleAutoPlayOutcome.noOp;
  }
}
