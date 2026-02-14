// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_transform_service.dart
//
// Applies board symmetry transformations to puzzles.
//
// Transforms both the initial position (FEN) and all solution move notations
// so that the puzzle can be presented in any of the 16 symmetrically
// equivalent orientations.  This prevents memorization and increases
// puzzle replayability.

import '../../game_page/services/mill.dart';
import '../../game_page/services/transform/transform.dart';
import '../models/puzzle_models.dart';

/// Stateless utility for applying board symmetry transformations to puzzles.
///
/// All methods are static and side-effect-free: they return new objects
/// rather than mutating the originals.
class PuzzleTransformService {
  const PuzzleTransformService._();

  /// Transforms an entire [PuzzleInfo], producing a new puzzle whose
  /// initial position and all solution move notations have been remapped
  /// according to [type].
  ///
  /// Metadata fields (title, description, difficulty, tags, etc.) are
  /// preserved unchanged—only game-logic data is transformed.
  static PuzzleInfo transformPuzzle(
    PuzzleInfo puzzle,
    TransformationType type,
  ) {
    if (type == TransformationType.identity) {
      return puzzle;
    }

    final String transformedFen = transformFEN(
      puzzle.initialPosition,
      type,
    );

    final List<PuzzleSolution> transformedSolutions = puzzle.solutions
        .map(
          (PuzzleSolution s) => transformSolution(s, type),
        )
        .toList();

    return puzzle.copyWith(
      initialPosition: transformedFen,
      solutions: transformedSolutions,
    );
  }

  /// Transforms a single [PuzzleSolution] by remapping every move notation.
  static PuzzleSolution transformSolution(
    PuzzleSolution solution,
    TransformationType type,
  ) {
    if (type == TransformationType.identity) {
      return solution;
    }

    final List<PuzzleMove> transformedMoves = solution.moves
        .map(
          (PuzzleMove m) => transformMove(m, type),
        )
        .toList();

    return PuzzleSolution(
      moves: transformedMoves,
      description: solution.description,
      isOptimal: solution.isOptimal,
    );
  }

  /// Transforms a single [PuzzleMove] by remapping its notation.
  ///
  /// The [PuzzleMove.side] and [PuzzleMove.comment] are preserved.
  static PuzzleMove transformMove(PuzzleMove move, TransformationType type) {
    if (type == TransformationType.identity) {
      return move;
    }

    return PuzzleMove(
      notation: transformMoveNotation(move.notation, type),
      side: move.side,
      comment: move.comment,
    );
  }
}
