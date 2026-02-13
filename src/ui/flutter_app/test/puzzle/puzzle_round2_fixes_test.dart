// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Unit tests for the second round of puzzle logic fixes:
//
// A. _giveUp marks solutionViewed (tested indirectly via model logic)
// B. _savePuzzle preserves description when forcing isOptimal
// C. getHintOfType only increments _hintsGiven when a hint is returned

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_hint_service.dart';

void main() {
  // -----------------------------------------------------------------------
  // Fix A: solutionViewed should prevent stars after viewing Give Up dialog.
  //
  // The actual UI flow (_giveUp setting the flag) cannot be unit-tested
  // without a widget test, but we can verify the star-prevention logic
  // that depends on the flag.
  // -----------------------------------------------------------------------
  group('Fix A: solutionViewed prevents stars after viewing solution', () {
    test('stars = 0 for all difficulties when solutionViewed is true', () {
      for (final PuzzleDifficulty diff in PuzzleDifficulty.values) {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 1,
          optimalMoveCount: 1,
          difficulty: diff,
          hintsUsed: false,
          solutionViewed: true,
        );
        expect(
          stars,
          equals(0),
          reason:
              'solutionViewed must yield 0 stars for difficulty ${diff.name}',
        );
      }
    });

    test('persisted solutionViewed overrides clean local flag', () {
      // Simulates the _onPuzzleSolved logic where _solutionViewed was reset
      // by _resetPuzzle but the persisted progress has solutionViewed=true.
      const bool localFlag = false;
      final PuzzleProgress persisted = PuzzleProgress(
        puzzleId: 'test',
        solutionViewed: true,
      );
      final bool effective = localFlag || persisted.solutionViewed;
      expect(effective, isTrue);

      final int stars = PuzzleProgress.calculateStars(
        moveCount: 3,
        optimalMoveCount: 3,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
        solutionViewed: effective,
      );
      expect(stars, equals(0));
    });
  });

  // -----------------------------------------------------------------------
  // Fix B: PuzzleSolution description preserved when forcing isOptimal.
  // -----------------------------------------------------------------------
  group('Fix B: PuzzleSolution description preserved on isOptimal promotion',
      () {
    test('description is preserved when creating optimal replacement', () {
      // Simulate the _savePuzzle fix: replace the first solution with
      // isOptimal=true while preserving description.
      const PuzzleSolution original = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
        ],
        description: 'Main line',
        isOptimal: false,
      );

      // Fixed code: passes description explicitly.
      final PuzzleSolution promoted = PuzzleSolution(
        moves: original.moves,
        description: original.description,
      );

      expect(promoted.isOptimal, isTrue);
      expect(promoted.description, equals('Main line'));
      expect(promoted.moves.length, equals(1));
    });

    test('null description remains null after promotion', () {
      const PuzzleSolution original = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
        ],
        isOptimal: false,
      );

      final PuzzleSolution promoted = PuzzleSolution(
        moves: original.moves,
        description: original.description,
      );

      expect(promoted.isOptimal, isTrue);
      expect(promoted.description, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Fix C: getHintOfType only increments _hintsGiven on successful hint.
  // -----------------------------------------------------------------------
  group('Fix C: getHintOfType only counts actually returned hints', () {
    test('hintsGiven not incremented when textual hint is unavailable', () {
      // Puzzle with no textual hint (hint is null).
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'no_hint',
        title: 'No Hint',
        description: 'Puzzle without hint text',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);
      expect(service.hintsGiven, equals(0));

      // Request a textual hint that doesn't exist.
      final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

      expect(hint, isNull);
      // Counter should NOT have been incremented.
      expect(service.hintsGiven, equals(0));
    });

    test('hintsGiven not incremented when empty hint text', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'empty_hint',
        title: 'Empty Hint',
        description: 'Puzzle with empty hint text',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        hint: '',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);
      final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

      expect(hint, isNull);
      expect(service.hintsGiven, equals(0));
    });

    test('hintsGiven incremented when textual hint IS available', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'with_hint',
        title: 'With Hint',
        description: 'Puzzle with hint text',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        hint: 'Try the outer ring',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);
      final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

      expect(hint, isNotNull);
      expect(hint!.type, equals(HintType.textual));
      expect(service.hintsGiven, equals(1));
    });

    test('hintsGiven not incremented for nextMove beyond solution length', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'short_sol',
        title: 'Short Solution',
        description: 'Only one player move',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);

      // Request hint for move index 0 (exists) → should succeed.
      final PuzzleHint? hint0 = service.getHintOfType(HintType.nextMove, 0);
      expect(hint0, isNotNull);
      expect(service.hintsGiven, equals(1));

      // Request hint for move index 10 (beyond solution) → should fail.
      final PuzzleHint? hint10 = service.getHintOfType(HintType.nextMove, 10);
      expect(hint10, isNull);
      // Counter should still be 1 (not 2).
      expect(service.hintsGiven, equals(1));
    });

    test('hintsGiven incremented for showSolution (always available)', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'show_sol',
        title: 'Show Sol',
        description: 'Test showSolution hint',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);
      final PuzzleHint? hint = service.getHintOfType(
        HintType.showSolution,
        0,
      );

      expect(hint, isNotNull);
      expect(service.hintsGiven, equals(1));
    });

    test('hintsGiven not incremented for highlight (always returns empty)', () {
      // _getHighlightSquares currently returns an empty list, so the hint
      // is null (guard: squares != null && squares.isNotEmpty).
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'highlight_test',
        title: 'Highlight',
        description: 'Test highlight hint',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleHintService service = PuzzleHintService(puzzle: puzzle);
      final PuzzleHint? hint = service.getHintOfType(HintType.highlight, 0);

      expect(hint, isNull);
      // Counter should NOT be incremented since no hint was returned.
      expect(service.hintsGiven, equals(0));
    });
  });
}
