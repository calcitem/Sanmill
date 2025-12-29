// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_validator.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

    // Initialize bitboards
    initBitboards();

    // Provide a stable documents directory for Hive/path_provider callers
    appDocDir = Directory.systemTemp.createTempSync('sanmill_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return appDocDir.path;
            default:
              return null;
          }
        });

    await DB.init();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  group('PuzzleValidator', () {
    late PuzzleInfo testPuzzle;
    late Position testPosition;

    setUp(() {
      // Create a test puzzle with a simple solution
      testPuzzle = PuzzleInfo(
        id: 'test_puzzle',
        title: 'Test Puzzle',
        description: 'Test puzzle for validator',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
              PuzzleMove(notation: 'a4', side: PieceColor.white),
            ],
            isOptimal: true,
          ),
        ],
      );

      testPosition = Position();
      testPosition.setFen(testPuzzle.initialPosition);
    });

    test('addMove increments move count', () {
      final PuzzleValidator validator = PuzzleValidator(puzzle: testPuzzle);

      expect(validator.moveCount, equals(0));

      validator.addMove('a1');
      expect(validator.moveCount, equals(1));

      validator.addMove('a4');
      expect(validator.moveCount, equals(2));
    });

    test('undoLastMove decrements move count', () {
      final PuzzleValidator validator = PuzzleValidator(puzzle: testPuzzle);

      validator.addMove('a1');
      validator.addMove('a4');
      expect(validator.moveCount, equals(2));

      validator.undoLastMove();
      expect(validator.moveCount, equals(1));

      validator.undoLastMove();
      expect(validator.moveCount, equals(0));
    });

    test('undoLastMove on empty list does not crash', () {
      final PuzzleValidator validator = PuzzleValidator(puzzle: testPuzzle);

      expect(validator.moveCount, equals(0));
      validator.undoLastMove();
      expect(validator.moveCount, equals(0));
    });

    test('playerMoves returns unmodifiable list', () {
      final PuzzleValidator validator = PuzzleValidator(puzzle: testPuzzle);

      validator.addMove('a1');
      validator.addMove('a4');

      final List<String> moves = validator.playerMoves;
      expect(moves.length, equals(2));
      expect(() => moves.add('test'), throwsUnsupportedError);
    });

    test('reset clears all moves', () {
      final PuzzleValidator validator = PuzzleValidator(puzzle: testPuzzle);

      validator.addMove('a1');
      validator.addMove('a4');
      expect(validator.moveCount, equals(2));

      validator.reset();
      expect(validator.moveCount, equals(0));
      expect(validator.playerMoves, isEmpty);
    });
  });

  group('PuzzleValidator with multiple solutions', () {
    test('getHint returns next move from optimal solution', () {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'hint_test',
        title: 'Hint Test',
        description: 'Test hint with multiple solutions',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
              PuzzleMove(notation: 'a4', side: PieceColor.white),
            ],
            isOptimal: true,
          ),
          PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a7', side: PieceColor.white),
            ],
            isOptimal: false,
          ),
        ],
      );

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);

      // Should get hints from optimal solution only
      final String? hint1 = validator.getHint();
      expect(hint1, equals('a1'));

      validator.addMove('a1');
      final String? hint2 = validator.getHint();
      expect(hint2, equals('a4'));

      validator.addMove('a4');
      final String? hint3 = validator.getHint();
      expect(hint3, isNull);
    });
  });

  group('PuzzleValidator edge cases', () {
    test('handles puzzle with empty solutions', () {
      final PuzzleInfo emptyPuzzle = PuzzleInfo(
        id: 'empty_puzzle',
        title: 'Empty',
        description: 'Puzzle with no solutions',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[],
      );

      final PuzzleValidator validator = PuzzleValidator(puzzle: emptyPuzzle);

      final String? hint = validator.getHint();
      expect(hint, isNull);
    });

    test('handles very long solution sequence', () {
      // Create a solution with many moves
      final List<PuzzleMove> longMoves = List<PuzzleMove>.generate(
        20,
        (int i) => PuzzleMove(
          notation: 'move$i',
          side: i.isEven ? PieceColor.white : PieceColor.black,
        ),
      );

      final PuzzleInfo longPuzzle = PuzzleInfo(
        id: 'long_puzzle',
        title: 'Long Puzzle',
        description: 'Puzzle with many moves',
        category: PuzzleCategory.winGame,
        difficulty: PuzzleDifficulty.master,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[PuzzleSolution(moves: longMoves)],
      );

      final PuzzleValidator validator = PuzzleValidator(puzzle: longPuzzle);

      // Add all white moves (player moves)
      for (int i = 0; i < 20; i += 2) {
        validator.addMove('move$i');
      }

      expect(validator.moveCount, equals(10));
    });
  });
}
