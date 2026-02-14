// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_transform_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_transform_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PuzzleTransformService.transformMove
  // ---------------------------------------------------------------------------
  group('PuzzleTransformService.transformMove', () {
    test('identity should preserve move', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd5',
        side: PieceColor.white,
        comment: 'test comment',
      );
      final PuzzleMove result = PuzzleTransformService.transformMove(
        move,
        TransformationType.identity,
      );
      expect(result.notation, 'd5');
      expect(result.side, PieceColor.white);
      expect(result.comment, 'test comment');
    });

    test('should transform notation while preserving side and comment', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'd5',
        side: PieceColor.black,
        comment: 'a great move',
      );
      final PuzzleMove result = PuzzleTransformService.transformMove(
        move,
        TransformationType.rotate90,
      );
      // d5 is index 0, rotate90 maps 0 -> 2, index 2 is e4
      expect(result.notation, 'e4');
      expect(result.side, PieceColor.black);
      expect(result.comment, 'a great move');
    });

    test('should handle null comment', () {
      const PuzzleMove move = PuzzleMove(
        notation: 'a1',
        side: PieceColor.white,
      );
      final PuzzleMove result = PuzzleTransformService.transformMove(
        move,
        TransformationType.swap,
      );
      expect(result.comment, isNull);
      expect(result.side, PieceColor.white);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleTransformService.transformSolution
  // ---------------------------------------------------------------------------
  group('PuzzleTransformService.transformSolution', () {
    test('identity should preserve solution', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'd5', side: PieceColor.white),
          PuzzleMove(notation: 'e4', side: PieceColor.black),
        ],
        description: 'test solution',
        isOptimal: true,
      );
      final PuzzleSolution result = PuzzleTransformService.transformSolution(
        solution,
        TransformationType.identity,
      );
      expect(result.moves.length, 2);
      expect(result.moves[0].notation, 'd5');
      expect(result.moves[1].notation, 'e4');
      expect(result.description, 'test solution');
      expect(result.isOptimal, isTrue);
    });

    test('should transform all moves in solution', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'd5', side: PieceColor.white),
          PuzzleMove(notation: 'd7', side: PieceColor.black),
          PuzzleMove(notation: 'xd5', side: PieceColor.white),
        ],
        isOptimal: false,
      );
      final PuzzleSolution result = PuzzleTransformService.transformSolution(
        solution,
        TransformationType.swap,
      );
      // swap: d5(inner,0) -> d7(outer,16), d7(outer,16) -> d5(inner,0)
      expect(result.moves[0].notation, 'd7');
      expect(result.moves[1].notation, 'd5');
      expect(result.moves[2].notation, 'xd7');
      expect(result.isOptimal, isFalse);
    });

    test('should preserve move sides', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'a4', side: PieceColor.black),
        ],
      );
      final PuzzleSolution result = PuzzleTransformService.transformSolution(
        solution,
        TransformationType.rotate90,
      );
      expect(result.moves[0].side, PieceColor.white);
      expect(result.moves[1].side, PieceColor.black);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleTransformService.transformPuzzle
  // ---------------------------------------------------------------------------
  group('PuzzleTransformService.transformPuzzle', () {
    late PuzzleInfo testPuzzle;

    setUp(() {
      testPuzzle = PuzzleInfo(
        id: 'test_puzzle_1',
        title: 'Test Puzzle',
        description: 'A test puzzle for transformation',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.medium,
        initialPosition:
            'O@O*****/********/********'
            ' w p p 3 6 3 6 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'd5', side: PieceColor.white),
              PuzzleMove(notation: 'e5', side: PieceColor.black),
            ],
            isOptimal: true,
          ),
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'c4', side: PieceColor.white),
              PuzzleMove(notation: 'e5', side: PieceColor.black),
            ],
            isOptimal: false,
          ),
        ],
        hint: 'Focus on the corner',
        tags: const <String>['test', 'transform'],
      );
    });

    test('identity should return same puzzle', () {
      final PuzzleInfo result = PuzzleTransformService.transformPuzzle(
        testPuzzle,
        TransformationType.identity,
      );
      // Identity returns the same object
      expect(identical(result, testPuzzle), isTrue);
    });

    test('should transform initial position', () {
      final PuzzleInfo result = PuzzleTransformService.transformPuzzle(
        testPuzzle,
        TransformationType.rotate90,
      );
      // The FEN should be different after rotation
      expect(result.initialPosition, isNot(testPuzzle.initialPosition));
      // But the non-board part should be preserved
      expect(
        result.initialPosition.substring(26),
        testPuzzle.initialPosition.substring(26),
      );
    });

    test('should transform all solutions', () {
      final PuzzleInfo result = PuzzleTransformService.transformPuzzle(
        testPuzzle,
        TransformationType.rotate90,
      );
      expect(result.solutions.length, 2);
      // Each solution's moves should be transformed
      expect(result.solutions[0].moves[0].notation, isNot('d5'));
      expect(result.solutions[0].isOptimal, isTrue);
      expect(result.solutions[1].isOptimal, isFalse);
    });

    test('should preserve metadata fields', () {
      final PuzzleInfo result = PuzzleTransformService.transformPuzzle(
        testPuzzle,
        TransformationType.mirrorHorizontal,
      );
      expect(result.id, testPuzzle.id);
      expect(result.title, testPuzzle.title);
      expect(result.description, testPuzzle.description);
      expect(result.category, testPuzzle.category);
      expect(result.difficulty, testPuzzle.difficulty);
      expect(result.hint, testPuzzle.hint);
      expect(result.tags, testPuzzle.tags);
    });

    test('applying transform then inverse should restore original', () {
      for (final TransformationType t in TransformationType.values) {
        if (t == TransformationType.identity) {
          continue;
        }
        final PuzzleInfo transformed = PuzzleTransformService.transformPuzzle(
          testPuzzle,
          t,
        );
        // Compute the inverse transform type by finding the one whose
        // map is the inverse of t's map
        final List<int> forwardMap = getTransformMap(t);
        final List<int> invMap = inverseTransformMap(forwardMap);
        // Find the matching type
        TransformationType? invType;
        for (final TransformationType candidate in TransformationType.values) {
          final List<int> candidateMap = getTransformMap(candidate);
          bool matches = true;
          for (int i = 0; i < 24; i++) {
            if (candidateMap[i] != invMap[i]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            invType = candidate;
            break;
          }
        }
        expect(
          invType,
          isNotNull,
          reason: 'Inverse of $t should exist as a named transform',
        );
        final PuzzleInfo restored = PuzzleTransformService.transformPuzzle(
          transformed,
          invType!,
        );
        expect(
          restored.initialPosition,
          testPuzzle.initialPosition,
          reason: 'Applying $t then its inverse should restore FEN',
        );
        for (int i = 0; i < testPuzzle.solutions.length; i++) {
          for (int j = 0; j < testPuzzle.solutions[i].moves.length; j++) {
            expect(
              restored.solutions[i].moves[j].notation,
              testPuzzle.solutions[i].moves[j].notation,
              reason:
                  'Applying $t then inverse should restore move '
                  'notation (sol $i, move $j)',
            );
          }
        }
      }
    });

    test('all 16 transforms should produce valid puzzles', () {
      for (final TransformationType t in TransformationType.values) {
        final PuzzleInfo result = PuzzleTransformService.transformPuzzle(
          testPuzzle,
          t,
        );
        // Basic validity: FEN is 26+ chars, solutions are non-empty
        expect(
          result.initialPosition.length,
          greaterThanOrEqualTo(26),
          reason: 'FEN for $t should be at least 26 chars',
        );
        expect(
          result.solutions.length,
          testPuzzle.solutions.length,
          reason: 'Solution count should be preserved for $t',
        );
        for (int i = 0; i < result.solutions.length; i++) {
          expect(
            result.solutions[i].moves.length,
            testPuzzle.solutions[i].moves.length,
            reason: 'Move count should be preserved for $t, solution $i',
          );
        }
      }
    });
  });
}
