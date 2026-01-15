// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_hint_service.dart';

void main() {
  group('PuzzleHintService', () {
    late PuzzleInfo testPuzzle;
    late PuzzleHintService hintService;

    setUp(() {
      testPuzzle = PuzzleInfo(
        id: 'hint_test_001',
        title: 'Test Puzzle',
        description: 'Puzzle for testing hints',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        hint: 'Try to form a mill on the outer ring',
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

      hintService = PuzzleHintService(puzzle: testPuzzle);
    });

    group('progressive hint system', () {
      test('first hint provides textual hint', () {
        final PuzzleHint? hint = hintService.getNextHint(0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.textual));
        expect(hint.content, equals('Try to form a mill on the outer ring'));
      });

      test('second hint shows next move', () {
        // Get first hint
        hintService.getNextHint(0);

        // Get second hint
        final PuzzleHint? hint = hintService.getNextHint(0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.nextMove));
        expect(hint.content, isNotEmpty);
        expect(hint.moveIndex, equals(0));
      });

      test('third hint shows full solution', () {
        // Get first and second hints
        hintService.getNextHint(0);
        hintService.getNextHint(0);

        // Get third hint
        final PuzzleHint? hint = hintService.getNextHint(0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.showSolution));
        expect(hint.content, isNotEmpty);
      });

      test('returns null when all hints exhausted', () {
        // Exhaust all hints
        hintService.getNextHint(0);
        hintService.getNextHint(0);
        hintService.getNextHint(0);

        // Try to get another hint
        final PuzzleHint? hint = hintService.getNextHint(0);

        expect(hint, isNull);
      });

      test('tracks hints given count', () {
        expect(hintService.hintsGiven, equals(0));

        hintService.getNextHint(0);
        expect(hintService.hintsGiven, equals(1));

        hintService.getNextHint(0);
        expect(hintService.hintsGiven, equals(2));

        hintService.getNextHint(0);
        expect(hintService.hintsGiven, equals(3));
      });
    });

    group('puzzle without textual hint', () {
      test('skips to next move hint when no textual hint', () {
        final PuzzleInfo puzzleNoHint = testPuzzle.copyWith();
        final PuzzleHintService service = PuzzleHintService(
          puzzle: puzzleNoHint,
        );

        final PuzzleHint? hint = service.getNextHint(0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.nextMove));
      });

      test('skips to next move hint when textual hint is empty', () {
        final PuzzleInfo puzzleEmptyHint = testPuzzle.copyWith(hint: '');
        final PuzzleHintService service = PuzzleHintService(
          puzzle: puzzleEmptyHint,
        );

        final PuzzleHint? hint = service.getNextHint(0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.nextMove));
      });
    });

    group('getHintOfType', () {
      test('can request specific textual hint', () {
        final PuzzleHint? hint = hintService.getHintOfType(HintType.textual, 0);

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.textual));
        expect(hint.content, equals('Try to form a mill on the outer ring'));
      });

      test('can request specific next move hint', () {
        final PuzzleHint? hint = hintService.getHintOfType(
          HintType.nextMove,
          0,
        );

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.nextMove));
        expect(hint.content, isNotEmpty);
      });

      test('can request full solution hint', () {
        final PuzzleHint? hint = hintService.getHintOfType(
          HintType.showSolution,
          0,
        );

        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.showSolution));
        expect(hint.content, isNotEmpty);
      });

      test('returns null for textual hint when not available', () {
        final PuzzleInfo puzzleNoHint = testPuzzle.copyWith();
        final PuzzleHintService service = PuzzleHintService(
          puzzle: puzzleNoHint,
        );

        final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

        expect(hint, isNull);
      });
    });

    group('reset functionality', () {
      test('resets hint state', () {
        // Give some hints
        hintService.getNextHint(0);
        hintService.getNextHint(0);
        expect(hintService.hintsGiven, equals(2));

        // Reset
        hintService.reset();

        // Verify reset
        expect(hintService.hintsGiven, equals(0));

        // First hint should be textual again
        final PuzzleHint? hint = hintService.getNextHint(0);
        expect(hint, isNotNull);
        expect(hint!.type, equals(HintType.textual));
      });
    });

    group('player move progression', () {
      test('provides correct next move at different positions', () {
        final PuzzleHint? hint1 = hintService.getHintOfType(
          HintType.nextMove,
          0,
        );
        expect(hint1, isNotNull);
        expect(hint1!.content, equals('a1'));

        final PuzzleHint? hint2 = hintService.getHintOfType(
          HintType.nextMove,
          1,
        );
        expect(hint2, isNotNull);
        expect(hint2!.content, equals('a4'));

        final PuzzleHint? hint3 = hintService.getHintOfType(
          HintType.nextMove,
          2,
        );
        expect(hint3, isNotNull);
        expect(hint3!.content, equals('a7'));
      });

      test('returns null for next move when beyond solution', () {
        // Player has already made all moves
        final PuzzleHint? hint = hintService.getHintOfType(
          HintType.nextMove,
          10,
        );

        expect(hint, isNull);
      });
    });

    group('multiple solutions', () {
      test('uses first optimal solution for hints', () {
        final PuzzleInfo multiSolutionPuzzle = PuzzleInfo(
          id: 'multi_sol_hint_test',
          title: 'Multi Solution',
          description: 'Multiple solutions',
          category: PuzzleCategory.formMill,
          difficulty: PuzzleDifficulty.medium,
          initialPosition:
              '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
          solutions: const <PuzzleSolution>[
            PuzzleSolution(
              moves: <PuzzleMove>[
                PuzzleMove(notation: 'a1', side: PieceColor.white),
              ],
            ),
            PuzzleSolution(
              moves: <PuzzleMove>[
                PuzzleMove(notation: 'a4', side: PieceColor.white),
              ],
              isOptimal: false,
            ),
          ],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: multiSolutionPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(HintType.nextMove, 0);

        expect(hint, isNotNull);
        expect(hint!.content, equals('a1'));
      });

      test('falls back to first solution if no optimal marked', () {
        final PuzzleInfo noOptimalPuzzle = PuzzleInfo(
          id: 'no_optimal_hint_test',
          title: 'No Optimal',
          description: 'No optimal solution marked',
          category: PuzzleCategory.formMill,
          difficulty: PuzzleDifficulty.easy,
          initialPosition:
              '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
          solutions: const <PuzzleSolution>[
            PuzzleSolution(
              moves: <PuzzleMove>[
                PuzzleMove(notation: 'a7', side: PieceColor.white),
              ],
              isOptimal: false,
            ),
            PuzzleSolution(
              moves: <PuzzleMove>[
                PuzzleMove(notation: 'd7', side: PieceColor.white),
              ],
              isOptimal: false,
            ),
          ],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: noOptimalPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(HintType.nextMove, 0);

        expect(hint, isNotNull);
        // Should use first solution
        expect(hint!.content, equals('a7'));
      });
    });

    group('edge cases', () {
      test('handles puzzle with no solutions', () {
        final PuzzleInfo emptyPuzzle = PuzzleInfo(
          id: 'empty_hint_test',
          title: 'Empty',
          description: 'No solutions',
          category: PuzzleCategory.formMill,
          difficulty: PuzzleDifficulty.easy,
          initialPosition:
              '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
          solutions: const <PuzzleSolution>[],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: emptyPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(HintType.nextMove, 0);

        expect(hint, isNull);
      });

      test('handles puzzle with empty solution', () {
        final PuzzleInfo emptyMovesPuzzle = PuzzleInfo(
          id: 'empty_moves_hint_test',
          title: 'Empty Moves',
          description: 'Solution with no moves',
          category: PuzzleCategory.formMill,
          difficulty: PuzzleDifficulty.easy,
          initialPosition:
              '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
          solutions: const <PuzzleSolution>[
            PuzzleSolution(moves: <PuzzleMove>[]),
          ],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: emptyMovesPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(HintType.nextMove, 0);

        expect(hint, isNull);
      });

      test('handles solution with only opponent moves', () {
        final PuzzleInfo opponentOnlyPuzzle = PuzzleInfo(
          id: 'opponent_only_hint_test',
          title: 'Opponent Moves',
          description: 'Only opponent moves in solution',
          category: PuzzleCategory.defend,
          difficulty: PuzzleDifficulty.medium,
          initialPosition:
              '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
          solutions: const <PuzzleSolution>[
            PuzzleSolution(
              moves: <PuzzleMove>[
                PuzzleMove(notation: 'd1', side: PieceColor.black),
                PuzzleMove(notation: 'd4', side: PieceColor.black),
              ],
            ),
          ],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: opponentOnlyPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(HintType.nextMove, 0);

        // Should return null since there are no player moves
        expect(hint, isNull);
      });

      test('handles very long hint text', () {
        final String longHint = 'A' * 10000;
        final PuzzleInfo longHintPuzzle = testPuzzle.copyWith(hint: longHint);
        final PuzzleHintService service = PuzzleHintService(
          puzzle: longHintPuzzle,
        );

        final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

        expect(hint, isNotNull);
        expect(hint!.content.length, equals(10000));
      });

      test('handles special characters in hint text', () {
        const String specialHint =
            'Try to form a mill 🎯\n使用特殊字符 "quotes" and \'apostrophes\'';
        final PuzzleInfo specialHintPuzzle = testPuzzle.copyWith(
          hint: specialHint,
        );
        final PuzzleHintService service = PuzzleHintService(
          puzzle: specialHintPuzzle,
        );

        final PuzzleHint? hint = service.getHintOfType(HintType.textual, 0);

        expect(hint, isNotNull);
        expect(hint!.content, equals(specialHint));
      });

      test('handles negative current player move index', () {
        final PuzzleHint? hint = hintService.getHintOfType(
          HintType.nextMove,
          -1,
        );

        // Should handle gracefully - either return first move or null
        // depending on implementation
        expect(hint, isNull);
      });
    });

    group('full solution generation', () {
      test('generates complete solution string', () {
        final PuzzleHint? hint = hintService.getHintOfType(
          HintType.showSolution,
          0,
        );

        expect(hint, isNotNull);
        expect(hint!.content, contains('a1'));
        expect(hint.content, contains('a4'));
        expect(hint.content, contains('a7'));
      });

      test('solution includes all player moves', () {
        final PuzzleInfo complexPuzzle = PuzzleInfo(
          id: 'complex_solution_test',
          title: 'Complex',
          description: 'Complex solution',
          category: PuzzleCategory.winGame,
          difficulty: PuzzleDifficulty.hard,
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
                PuzzleMove(notation: 'd7', side: PieceColor.black),
                PuzzleMove(notation: 'g1', side: PieceColor.white),
                PuzzleMove(notation: 'g4', side: PieceColor.black),
                PuzzleMove(notation: 'g7', side: PieceColor.white),
              ],
            ),
          ],
        );

        final PuzzleHintService service = PuzzleHintService(
          puzzle: complexPuzzle,
        );
        final PuzzleHint? hint = service.getHintOfType(
          HintType.showSolution,
          0,
        );

        expect(hint, isNotNull);
        // Should include all white (player) moves
        expect(hint!.content, contains('a1'));
        expect(hint.content, contains('a4'));
        expect(hint.content, contains('a7'));
        expect(hint.content, contains('g1'));
        expect(hint.content, contains('g7'));
      });
    });
  });
}
