// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// Unit tests verifying that solutionViewed correctly prevents star awards.
//
// These tests cover:
// - calculateStars returns 0 when solutionViewed is true.
// - PuzzleProgress.copyWith correctly propagates solutionViewed.
// - PuzzleSettings.updateProgress correctly stores solutionViewed.
// - Creating progress from scratch with solutionViewed works.
// - JSON round-trip preserves solutionViewed.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';

void main() {
  group('solutionViewed prevents star awards', () {
    test('calculateStars returns 0 when solutionViewed is true', () {
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 5,
        optimalMoveCount: 5,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
        solutionViewed: true,
      );

      expect(stars, equals(0));
    });

    test(
      'calculateStars returns 3 when solutionViewed is false and optimal',
      () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 5,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.easy,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      },
    );

    test(
      'solutionViewed overrides hints - 0 stars even without hints used',
      () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 5,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.beginner,
          hintsUsed: false,
          solutionViewed: true,
        );

        expect(stars, equals(0));
      },
    );

    test(
      'solutionViewed overrides difficulty - 0 stars for all difficulties',
      () {
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
            reason: 'solutionViewed should yield 0 stars for ${diff.name}',
          );
        }
      },
    );

    test('solutionViewed defaults to false in calculateStars', () {
      // Call without explicitly passing solutionViewed to verify default.
      final int stars = PuzzleProgress.calculateStars(
        moveCount: 5,
        optimalMoveCount: 5,
        difficulty: PuzzleDifficulty.easy,
        hintsUsed: false,
      );

      expect(stars, equals(3));
    });
  });

  group('PuzzleProgress solutionViewed persistence', () {
    test('default solutionViewed is false', () {
      final PuzzleProgress progress = PuzzleProgress(puzzleId: 'test');
      expect(progress.solutionViewed, isFalse);
    });

    test('copyWith sets solutionViewed to true', () {
      final PuzzleProgress original = PuzzleProgress(puzzleId: 'test');
      final PuzzleProgress updated = original.copyWith(solutionViewed: true);

      expect(updated.solutionViewed, isTrue);
      expect(original.solutionViewed, isFalse); // Original unchanged.
    });

    test('copyWith preserves solutionViewed when not specified', () {
      final PuzzleProgress original = PuzzleProgress(
        puzzleId: 'test',
        solutionViewed: true,
      );
      final PuzzleProgress updated = original.copyWith(stars: 2);

      expect(updated.solutionViewed, isTrue);
      expect(updated.stars, equals(2));
    });

    test('creating progress from null base with solutionViewed works', () {
      // This mirrors the fix in _showSolution: when no prior progress exists,
      // we create a fresh PuzzleProgress and set solutionViewed.
      const PuzzleProgress? priorProgress = null;
      final PuzzleProgress newProgress =
          (priorProgress ?? PuzzleProgress(puzzleId: 'fresh')).copyWith(
            solutionViewed: true,
          );

      expect(newProgress.puzzleId, equals('fresh'));
      expect(newProgress.solutionViewed, isTrue);
      expect(newProgress.completed, isFalse);
      expect(newProgress.stars, equals(0));
    });

    test('effectiveSolutionViewed correctly combines local and persisted', () {
      // Simulates the _onPuzzleSolved logic:
      // effectiveSolutionViewed = localFlag || (priorProgress?.solutionViewed ?? false)

      // Case 1: local false, persisted true => true.
      const bool localFlag1 = false;
      final PuzzleProgress prior1 = PuzzleProgress(
        puzzleId: 'test',
        solutionViewed: true,
      );
      final bool effective1 = localFlag1 || prior1.solutionViewed;
      expect(effective1, isTrue);

      // Case 2: local true, persisted false => true.
      const bool localFlag2 = true;
      final PuzzleProgress prior2 = PuzzleProgress(puzzleId: 'test');
      final bool effective2 = prior2.solutionViewed || localFlag2;
      expect(effective2, isTrue);

      // Case 3: both false => false.
      const bool localFlag3 = false;
      final PuzzleProgress prior3 = PuzzleProgress(puzzleId: 'test');
      final bool effective3 = localFlag3 || prior3.solutionViewed;
      expect(effective3, isFalse);

      // Case 4: no prior progress => fallback to false.
      const bool localFlag4 = false;
      const PuzzleProgress? prior4 = null;
      final bool effective4 = localFlag4 || (prior4?.solutionViewed ?? false);
      expect(effective4, isFalse);
    });

    test('JSON round-trip preserves solutionViewed = true', () {
      final PuzzleProgress original = PuzzleProgress(
        puzzleId: 'json_test',
        solutionViewed: true,
        completed: true,
      );

      final Map<String, dynamic> json = original.toJson();
      expect(json['solutionViewed'], isTrue);

      final PuzzleProgress restored = PuzzleProgress.fromJson(json);
      expect(restored.solutionViewed, isTrue);
    });

    test('JSON round-trip preserves solutionViewed = false', () {
      final PuzzleProgress original = PuzzleProgress(puzzleId: 'json_test2');

      final Map<String, dynamic> json = original.toJson();
      expect(json['solutionViewed'], isFalse);

      final PuzzleProgress restored = PuzzleProgress.fromJson(json);
      expect(restored.solutionViewed, isFalse);
    });
  });

  group('PuzzleSettings solutionViewed integration', () {
    test('updateProgress stores solutionViewed correctly', () {
      const PuzzleSettings settings = PuzzleSettings();

      // No progress yet.
      expect(settings.getProgress('puzzle_1'), isNull);

      // Update with solutionViewed = true.
      final PuzzleSettings updated = settings.updateProgress(
        PuzzleProgress(puzzleId: 'puzzle_1', solutionViewed: true),
      );

      final PuzzleProgress? stored = updated.getProgress('puzzle_1');
      expect(stored, isNotNull);
      expect(stored!.solutionViewed, isTrue);
    });

    test('updateProgress preserves solutionViewed across updates', () {
      const PuzzleSettings settings = PuzzleSettings();

      // First update: mark solutionViewed.
      final PuzzleSettings after1 = settings.updateProgress(
        PuzzleProgress(puzzleId: 'puzzle_2', solutionViewed: true),
      );

      // Second update: mark completed (should preserve solutionViewed).
      final PuzzleProgress existing = after1.getProgress('puzzle_2')!;
      final PuzzleSettings after2 = after1.updateProgress(
        existing.copyWith(completed: true, stars: 0),
      );

      final PuzzleProgress? stored = after2.getProgress('puzzle_2');
      expect(stored, isNotNull);
      expect(stored!.solutionViewed, isTrue);
      expect(stored.completed, isTrue);
      expect(stored.stars, equals(0));
    });
  });

  group('Optimal solution and player side', () {
    test('optimalMoveCount counts player moves only', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'count_test',
        title: 'Count Test',
        description: 'Test move counting',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
              PuzzleMove(notation: 'a4', side: PieceColor.white),
              PuzzleMove(notation: 'd4', side: PieceColor.black),
              PuzzleMove(notation: 'a7', side: PieceColor.white),
            ],
          ),
        ],
      );

      // White is the player (side-to-move in the FEN is white).
      // There are 3 white moves in the solution.
      expect(puzzle.optimalMoveCount, equals(3));
    });

    test('optimalSolution prefers isOptimal=true', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'optimal_test',
        title: 'Optimal Test',
        description: 'Test optimal selection',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
            isOptimal: false,
          ),
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a4', side: PieceColor.white),
            ],
          ),
        ],
      );

      expect(puzzle.optimalSolution, isNotNull);
      expect(puzzle.optimalSolution!.moves[0].notation, equals('a4'));
    });

    test('optimalSolution falls back to first when none marked optimal', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'fallback_test',
        title: 'Fallback Test',
        description: 'Test fallback',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
            isOptimal: false,
          ),
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a4', side: PieceColor.white),
            ],
            isOptimal: false,
          ),
        ],
      );

      expect(puzzle.optimalSolution, isNotNull);
      expect(puzzle.optimalSolution!.moves[0].notation, equals('a1'));
    });
  });
}
