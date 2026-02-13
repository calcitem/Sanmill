// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_validation_service.dart
//
// Service for validating puzzle integrity and correctness

import '../../game_page/services/mill.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';

/// Result of puzzle validation
class PuzzleValidationReport {
  const PuzzleValidationReport({
    this.errors = const <String>[],
    this.warnings = const <String>[],
  });

  /// Critical errors that make the puzzle invalid
  final List<String> errors;

  /// Non-critical warnings
  final List<String> warnings;

  /// Whether the puzzle is valid (no errors)
  bool get isValid => errors.isEmpty;

  /// Whether there are any issues at all
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;

  @override
  String toString() {
    if (!hasIssues) {
      return 'PuzzleValidationReport: OK';
    }
    final StringBuffer sb = StringBuffer('PuzzleValidationReport:\n');
    if (errors.isNotEmpty) {
      sb.writeln('  Errors: ${errors.length}');
      for (final String error in errors) {
        sb.writeln('    - $error');
      }
    }
    if (warnings.isNotEmpty) {
      sb.writeln('  Warnings: ${warnings.length}');
      for (final String warning in warnings) {
        sb.writeln('    - $warning');
      }
    }
    return sb.toString();
  }
}

/// Service for validating puzzles
class PuzzleValidationService {
  const PuzzleValidationService._();

  static const String _tag = '[PuzzleValidationService]';

  /// Validate a puzzle's structure and content
  ///
  /// This performs comprehensive validation including:
  /// - Required field presence
  /// - FEN format validation
  /// - Solution structure validation
  /// - Move count consistency
  static PuzzleValidationReport validatePuzzle(PuzzleInfo puzzle) {
    final List<String> errors = <String>[];
    final List<String> warnings = <String>[];

    // 1. Validate basic fields
    if (puzzle.id.trim().isEmpty) {
      errors.add('Puzzle ID is empty');
    }

    if (puzzle.title.trim().isEmpty) {
      errors.add('Puzzle title is empty');
    } else if (puzzle.title.length < 3) {
      warnings.add('Puzzle title is very short (${puzzle.title.length} chars)');
    } else if (puzzle.title.length > 100) {
      warnings.add('Puzzle title is very long (${puzzle.title.length} chars)');
    }

    if (puzzle.description.trim().isEmpty) {
      errors.add('Puzzle description is empty');
    } else if (puzzle.description.length < 10) {
      warnings.add(
        'Puzzle description is very short (${puzzle.description.length} chars)',
      );
    }

    // 2. Validate FEN format
    if (puzzle.initialPosition.trim().isEmpty) {
      errors.add('Initial position (FEN) is empty');
    } else {
      final Position tempPosition = Position();
      if (!tempPosition.validateFen(puzzle.initialPosition)) {
        errors.add('Invalid FEN format: ${puzzle.initialPosition}');
      } else {
        // Try to load the position
        final bool loaded = tempPosition.setFen(puzzle.initialPosition);
        if (!loaded) {
          errors.add('Failed to load FEN: ${puzzle.initialPosition}');
        }
      }
    }

    // 3. Validate solutions
    if (puzzle.solutions.isEmpty) {
      errors.add('Puzzle has no solutions');
    } else {
      // Check if at least one solution is marked optimal
      final bool hasOptimal = puzzle.solutions.any(
        (PuzzleSolution s) => s.isOptimal,
      );
      if (!hasOptimal) {
        warnings.add('No solution is marked as optimal');
      }

      // Validate each solution
      for (int i = 0; i < puzzle.solutions.length; i++) {
        final PuzzleSolution solution = puzzle.solutions[i];

        if (solution.moves.isEmpty) {
          errors.add('Solution ${i + 1} has no moves');
          continue;
        }

        // Check move notations
        for (int j = 0; j < solution.moves.length; j++) {
          final PuzzleMove move = solution.moves[j];
          if (move.notation.trim().isEmpty) {
            errors.add('Solution ${i + 1}, move ${j + 1} has empty notation');
          }
        }

        // Validate alternating sides
        _validateAlternatingSides(solution, i + 1, errors, warnings);
      }

      // Check optimal move count consistency
      final int calculatedOptimal = puzzle.optimalMoveCount;
      if (calculatedOptimal == 0) {
        warnings.add('Optimal move count is 0 (empty optimal solution?)');
      }
    }

    // 4. Validate version
    if (puzzle.version < 1 || puzzle.version > 10) {
      warnings.add('Puzzle version (${puzzle.version}) is unusual');
    }

    // 5. Validate rating
    if (puzzle.rating != null) {
      if (puzzle.rating! < 100 || puzzle.rating! > 3000) {
        warnings.add(
          'Puzzle rating (${puzzle.rating}) is outside normal range',
        );
      }
    }

    // 6. Validate author for custom puzzles
    if (puzzle.isCustom &&
        (puzzle.author == null || puzzle.author!.trim().isEmpty)) {
      warnings.add('Custom puzzle should have an author');
    }

    logger.i(
      '$_tag Validation complete for puzzle ${puzzle.id}: '
      '${errors.length} errors, ${warnings.length} warnings',
    );

    return PuzzleValidationReport(errors: errors, warnings: warnings);
  }

  /// Validate that moves alternate sides correctly.
  ///
  /// In Mill games a player who forms a mill gets an extra removal move on the
  /// same turn.  If the puzzle encodes that removal as a separate [PuzzleMove]
  /// entry (same side as the preceding placement), strict alternation would be
  /// violated.  We therefore emit a *warning* rather than an error so that
  /// legitimate puzzles are not rejected.
  static void _validateAlternatingSides(
    PuzzleSolution solution,
    int solutionNumber,
    List<String> errors,
    List<String> warnings,
  ) {
    if (solution.moves.length < 2) {
      return; // Too short to validate alternation
    }

    PieceColor expectedSide = solution.moves.first.side;
    for (int i = 0; i < solution.moves.length; i++) {
      if (solution.moves[i].side != expectedSide) {
        // Consecutive moves by the same side may indicate a removal sub-move,
        // which is valid in Mill games.  Report as a warning, not an error.
        warnings.add(
          'Solution $solutionNumber: Move ${i + 1} has unexpected side '
          '(expected ${expectedSide.name}, got ${solution.moves[i].side.name}). '
          'This may be valid if it represents a removal after forming a mill.',
        );
      }
      expectedSide = solution.moves[i].side.opponent;
    }
  }

  /// Quick validation for common issues
  ///
  /// Returns an error message if validation fails, null if OK
  static String? quickValidate(PuzzleInfo puzzle) {
    if (puzzle.title.trim().isEmpty) {
      return 'Puzzle must have a title';
    }

    if (puzzle.description.trim().isEmpty) {
      return 'Puzzle must have a description';
    }

    if (puzzle.initialPosition.trim().isEmpty) {
      return 'Puzzle must have an initial position';
    }

    final Position tempPosition = Position();
    if (!tempPosition.validateFen(puzzle.initialPosition)) {
      return 'Puzzle has invalid FEN format';
    }

    if (puzzle.solutions.isEmpty) {
      return 'Puzzle must have at least one solution';
    }

    return null; // All OK
  }

  /// Validate puzzle for contribution/export
  ///
  /// Stricter validation for puzzles being shared or contributed
  static PuzzleValidationReport validateForContribution(PuzzleInfo puzzle) {
    final PuzzleValidationReport baseReport = validatePuzzle(puzzle);
    final List<String> errors = List<String>.from(baseReport.errors);
    final List<String> warnings = List<String>.from(baseReport.warnings);

    // Additional checks for contribution
    if (puzzle.title.length < 5) {
      errors.add('Title too short for contribution (minimum 5 characters)');
    }

    if (puzzle.title.length > 80) {
      warnings.add('Title is quite long (${puzzle.title.length} chars)');
    }

    if (puzzle.description.length < 15) {
      errors.add(
        'Description too short for contribution (minimum 15 characters)',
      );
    }

    if (puzzle.description.length > 500) {
      warnings.add(
        'Description is quite long (${puzzle.description.length} chars)',
      );
    }

    if (puzzle.author == null || puzzle.author!.trim().isEmpty) {
      errors.add('Please add your name as author before contributing');
    }

    if (puzzle.solutions.length > 5) {
      warnings.add('Puzzle has many solutions (${puzzle.solutions.length})');
    }

    return PuzzleValidationReport(errors: errors, warnings: warnings);
  }
}
