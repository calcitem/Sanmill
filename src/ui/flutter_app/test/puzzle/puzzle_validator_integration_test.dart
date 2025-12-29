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

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';

/// Integration tests for PuzzleValidator that execute actual game moves
/// These tests verify the validator against real game state changes
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;
  late GameController controller;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

    // Initialize bitboards
    initBitboards();

    // Mock engine channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'uciok';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    // Mock path provider
    appDocDir = Directory.systemTemp.createTempSync('sanmill_integration_');
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
    SoundManager.instance = MockAudios();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() {
    controller = GameController();
    controller.reset(force: true);
    controller.puzzleHumanColor = null;
    controller.isPuzzleAutoMoveInProgress = false;
    controller.animationManager = MockAnimationManager();
  });

  group('PuzzleValidator Integration - Form Mill Puzzles', () {
    test('tracks player moves correctly through actual game moves', () async {
      // Simple test: Just verify moves are tracked correctly
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'track_moves',
        title: 'Track Moves Test',
        description: 'Verify move tracking',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          const PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'd1', side: PieceColor.black),
              PuzzleMove(notation: 'a4', side: PieceColor.white),
            ],
          ),
        ],
      );

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);

      // Set up game state
      controller.position.setFen(puzzle.initialPosition);

      // Execute moves and track them
      controller.position.doMove('a1');
      validator.addMove('a1');

      expect(validator.moveCount, equals(1));
      expect(validator.playerMoves, equals(<String>['a1']));

      // Opponent move (not tracked)
      controller.position.doMove('d1');

      // Another player move
      controller.position.doMove('a4');
      validator.addMove('a4');

      expect(validator.moveCount, equals(2));
      expect(validator.playerMoves, equals(<String>['a1', 'a4']));
    });

    test('validates move sequence matches solution', () async {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'sequence_match',
        title: 'Sequence Match',
        description: 'Test exact sequence matching',
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

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);
      controller.position.setFen(puzzle.initialPosition);

      // Play correct sequence
      controller.position.doMove('a1');
      validator.addMove('a1');

      controller.position.doMove('d1');
      // Don't track opponent move

      // At this point, the game state shows player has followed solution
      expect(validator.moveCount, equals(1));

      // Verify internal matching logic
      final List<PuzzleMove> expectedPlayerMoves = puzzle.solutions.first
          .getPlayerMoves(puzzle.playerSide);
      expect(expectedPlayerMoves.length, greaterThan(0));
      expect(expectedPlayerMoves[0].notation, equals('a1'));
    });
  });

  group('PuzzleValidator Integration - Multiple Solutions', () {
    test('tracks moves for alternative solutions', () async {
      // Puzzle with two valid solutions
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'multi_solution',
        title: 'Multiple Solutions',
        description: 'Two ways to solve',
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

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);
      controller.position.setFen(puzzle.initialPosition);

      // Play the alternative solution
      controller.position.doMove('a4');
      validator.addMove('a4');

      expect(validator.moveCount, equals(1));

      // Verify this move exists in one of the solutions
      bool foundInSolution = false;
      for (final PuzzleSolution solution in puzzle.solutions) {
        final List<PuzzleMove> playerMoves = solution.getPlayerMoves(
          puzzle.playerSide,
        );
        if (playerMoves.isNotEmpty && playerMoves[0].notation == 'a4') {
          foundInSolution = true;
          break;
        }
      }
      expect(foundInSolution, isTrue);
    });
  });

  group('PuzzleValidator Integration - Hint System', () {
    test('provides correct hints from optimal solution', () async {
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'hint_test',
        title: 'Hint Test',
        description: 'Test hint provision',
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
            ],
          ),
        ],
      );

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);

      // Get first hint
      final String? hint1 = validator.getHint();
      expect(hint1, equals('a1'));

      // Play first move
      validator.addMove('a1');

      // Get next hint (should skip opponent move)
      final String? hint2 = validator.getHint();
      expect(hint2, equals('a4'));

      // Play second move
      validator.addMove('a4');

      // No more hints
      final String? hint3 = validator.getHint();
      expect(hint3, isNull);
    });
  });
}
