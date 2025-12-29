// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ignore_for_file: unused_import

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_export_service.dart';

void main() {
  group('PuzzleExportService JSON format', () {
    test('exports single solution puzzle correctly', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'test_001',
        title: 'Test Puzzle',
        description: 'A test puzzle',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: const <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
            ],
          ),
        ],
      );

      final Map<String, dynamic> json = puzzle.toJson();

      expect(json['id'], equals('test_001'));
      expect(json['solutions'], isA<List<dynamic>>());
      final List<dynamic> solutions = json['solutions'] as List<dynamic>;
      expect(solutions.length, equals(1));
      final Map<String, dynamic> firstSolution =
          solutions[0] as Map<String, dynamic>;
      expect(firstSolution['moves'], isA<List<dynamic>>());
    });

    test('exports multiple solutions with optimal marking', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'multi_test',
        title: 'Multi Test',
        description: 'Multi solution test',
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

      final Map<String, dynamic> json = puzzle.toJson();

      final List<dynamic> solutions = json['solutions'] as List<dynamic>;
      expect(solutions.length, equals(2));
      final Map<String, dynamic> firstSolution =
          solutions[0] as Map<String, dynamic>;
      final Map<String, dynamic> secondSolution =
          solutions[1] as Map<String, dynamic>;
      expect(firstSolution['isOptimal'], isTrue);
      expect(secondSolution['isOptimal'], isFalse);
    });

    test('imports puzzle with multiple solutions correctly', () {
      final String jsonString = jsonEncode(<String, dynamic>{
        'formatVersion': '1.0',
        'exportDate': '2025-12-28T00:00:00.000Z',
        'puzzleCount': 1,
        'puzzles': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'import_test',
            'title': 'Import Test',
            'description': 'Test import with multiple solutions',
            'category': 'formMill',
            'difficulty': 'easy',
            'initialPosition':
                '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
            'solutions': <Map<String, dynamic>>[
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a1', 'side': 'white'},
                  <String, dynamic>{'notation': 'd1', 'side': 'black'},
                ],
              },
              <String, dynamic>{
                'moves': <Map<String, dynamic>>[
                  <String, dynamic>{'notation': 'a4', 'side': 'white'},
                  <String, dynamic>{'notation': 'd4', 'side': 'black'},
                ],
                'isOptimal': false,
              },
            ],
            'tags': <String>[],
            'isCustom': false,
            'createdDate': '2025-01-01T00:00:00.000Z',
            'version': 1,
            'ruleVariantId': 'standard_9mm',
          },
        ],
      });

      // Parse the JSON to verify structure
      final Map<String, dynamic> data =
          jsonDecode(jsonString) as Map<String, dynamic>;
      final List<dynamic> puzzles = data['puzzles'] as List<dynamic>;
      final PuzzleInfo puzzle = PuzzleInfo.fromJson(
        puzzles[0] as Map<String, dynamic>,
      );

      expect(puzzle.solutions.length, equals(2));
      expect(puzzle.solutions[0].isOptimal, isTrue);
      expect(puzzle.solutions[1].isOptimal, isFalse);
      expect(puzzle.solutions[0].moves[0].notation, equals('a1'));
      expect(puzzle.solutions[1].moves[0].notation, equals('a4'));
    });

    test('exports puzzle pack metadata correctly', () {
      const PuzzlePackMetadata metadata = PuzzlePackMetadata(
        id: 'test_pack',
        name: 'Test Pack',
        description: 'A test pack',
        author: 'Test Author',
        version: '1.0.0',
      );

      final Map<String, dynamic> json = metadata.toJson();

      expect(json['id'], equals('test_pack'));
      expect(json['name'], equals('Test Pack'));
      expect(json['author'], equals('Test Author'));
      expect(json['version'], equals('1.0.0'));
    });
  });

  group('PuzzleSolution advanced tests', () {
    test('getPlayerMoves with complex sequence', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
          PuzzleMove(notation: 'd1', side: PieceColor.black),
          PuzzleMove(notation: 'a4', side: PieceColor.white),
          PuzzleMove(notation: 'd4', side: PieceColor.black),
          PuzzleMove(notation: 'a7', side: PieceColor.white),
          PuzzleMove(
            notation: 'xa1',
            side: PieceColor.white,
          ), // Remove after mill
        ],
      );

      final List<PuzzleMove> whiteMoves = solution.getPlayerMoves(
        PieceColor.white,
      );
      expect(whiteMoves.length, equals(4));
      expect(
        whiteMoves.map((PuzzleMove m) => m.notation).toList(),
        equals(<String>['a1', 'a4', 'a7', 'xa1']),
      );
    });

    test('equality works for complex solutions', () {
      const PuzzleSolution sol1 = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
        description: 'Main',
      );

      const PuzzleSolution sol2 = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
        description: 'Main',
      );

      const PuzzleSolution sol3 = PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a4', side: PieceColor.white)],
        description: 'Main',
      );

      expect(sol1, equals(sol2));
      expect(sol1, isNot(equals(sol3)));
    });

    test('handles move comments in JSON', () {
      const PuzzleSolution solution = PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(
            notation: 'a1',
            side: PieceColor.white,
            comment: 'Opening move',
          ),
          PuzzleMove(
            notation: 'd1',
            side: PieceColor.black,
            comment: 'Response',
          ),
        ],
      );

      final Map<String, dynamic> json = solution.toJson();
      final List<dynamic> moves = json['moves'] as List<dynamic>;
      final Map<String, dynamic> firstMove = moves[0] as Map<String, dynamic>;
      final Map<String, dynamic> secondMove = moves[1] as Map<String, dynamic>;
      expect(firstMove['comment'], equals('Opening move'));
      expect(secondMove['comment'], equals('Response'));

      final PuzzleSolution fromJson = PuzzleSolution.fromJson(json);
      expect(fromJson.moves[0].comment, equals('Opening move'));
      expect(fromJson.moves[1].comment, equals('Response'));
    });
  });

  group('PuzzleInfo edge cases with multiple solutions', () {
    test('handles empty solutions list gracefully', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'empty_sol',
        title: 'Empty',
        description: 'Test',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition: 'test_fen',
        solutions: const <PuzzleSolution>[],
      );

      expect(puzzle.optimalSolution, isNull);
      expect(puzzle.optimalMoveCount, equals(0));
    });

    test('handles all non-optimal solutions', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'non_optimal',
        title: 'Non Optimal',
        description: 'Test',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition: 'test_fen',
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

      // Should return first solution as fallback
      final PuzzleSolution? optimal = puzzle.optimalSolution;
      expect(optimal, isNotNull);
      expect(optimal!.moves[0].notation, equals('a1'));
    });

    test('handles very long solution list', () {
      final List<PuzzleSolution> manySolutions = List<PuzzleSolution>.generate(
        10,
        (int i) => PuzzleSolution(
          moves: <PuzzleMove>[
            PuzzleMove(notation: 'move$i', side: PieceColor.white),
          ],
          isOptimal: i == 0,
        ),
      );

      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'many_sol',
        title: 'Many Solutions',
        description: 'Puzzle with many solutions',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.expert,
        initialPosition: 'test_fen',
        solutions: manySolutions,
      );

      expect(puzzle.solutions.length, equals(10));
      expect(puzzle.optimalSolution?.moves[0].notation, equals('move0'));
    });
  });
}
