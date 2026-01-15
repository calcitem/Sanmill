// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_auto_player.dart';
import 'package:sanmill/puzzle/services/puzzle_manager.dart';
import 'package:sanmill/puzzle/services/puzzle_validator.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';

/// Integration test for the full puzzle solving flow
///
/// Simulates the logic in PuzzlePage without the UI layer:
/// 1. Initialize puzzle
/// 2. Player moves
/// 3. Validation
/// 4. Opponent auto-response
/// 5. Completion and progress update
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
  late PuzzleManager puzzleManager;

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
    appDocDir = Directory.systemTemp.createTempSync('sanmill_flow_test_');
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
    puzzleManager = PuzzleManager();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (appDocDir.existsSync()) {
      appDocDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    controller = GameController();
    controller.reset(force: true);
    controller.puzzleHumanColor = null;
    controller.isPuzzleAutoMoveInProgress = false;
    controller.animationManager = MockAnimationManager();

    // Reset puzzle manager state
    await puzzleManager.init();
    puzzleManager.settingsNotifier.value = const PuzzleSettings();
  });

  group('Puzzle Full Flow', () {
    test('Solves a form-mill puzzle completely', () async {
      // 1. Setup Puzzle
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'flow_test_001',
        title: 'Flow Test',
        description: 'Testing full flow',
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
        isCustom: true, // Mark as custom so we can track progress
        rating: 1500,
      );

      // Add to manager so we can update progress
      puzzleManager.addCustomPuzzle(puzzle);

      // 2. Initialize Game
      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);
      controller.gameInstance.gameMode = GameMode.puzzle;
      controller.position.setFen(puzzle.initialPosition);
      controller.puzzleHumanColor = controller.position.sideToMove; // White

      // Verify initial state
      expect(controller.puzzleHumanColor, equals(PieceColor.white));
      expect(puzzleManager.getProgress(puzzle.id), isNull);

      // 3. Player Move 1 (a1)
      bool moveResult = controller.applyMove(
        ExtMove('a1', side: PieceColor.white),
      );
      expect(moveResult, isTrue);
      validator.addMove('a1');

      // Check solution
      ValidationFeedback feedback = validator.validateSolution(
        controller.position,
      );
      expect(feedback.result, equals(ValidationResult.inProgress));

      // 4. Opponent Auto-Response (d1)
      // Simulate auto-player logic
      final List<List<String>> legacySolutions = puzzle.solutions
          .map(
            (PuzzleSolution s) =>
                s.moves.map((PuzzleMove m) => m.notation).toList(),
          )
          .toList();

      // We expect the auto-player to find 'd1'
      final Completer<void> autoPlayCompleter = Completer<void>();
      await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: legacySolutions,
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => controller.position.sideToMove, // Black
        movesSoFar: () => <String>['a1'],
        applyMove: (String move) {
          expect(move, equals('d1'));
          final bool result = controller.applyMove(
            ExtMove(move, side: PieceColor.black),
          );
          validator.addMove(move);
          autoPlayCompleter.complete();
          return result;
        },
        onWrongMove: () {
          fail('Auto player should not fail here');
        },
      );
      await autoPlayCompleter.future;

      // 5. Player Move 2 (a4) - Winning move
      moveResult = controller.applyMove(ExtMove('a4', side: PieceColor.white));
      expect(moveResult, isTrue);
      validator.addMove('a4');

      // Check solution
      feedback = validator.validateSolution(controller.position);
      expect(feedback.result, equals(ValidationResult.correct));

      // 6. Complete Puzzle
      puzzleManager.completePuzzle(
        puzzleId: puzzle.id,
        moveCount: 2, // 2 player moves (a1, a4)
        difficulty: puzzle.difficulty,
        optimalMoveCount: puzzle.optimalMoveCount,
        hintsUsed: false,
      );

      // 7. Verify Progress Updated
      final PuzzleProgress? progress = puzzleManager.getProgress(puzzle.id);
      expect(progress, isNotNull);
      expect(progress!.completed, isTrue);
      expect(progress.stars, equals(3));
      expect(progress.attempts, equals(1));

      // Verify User Rating Updated
      final int newRating = puzzleManager.settingsNotifier.value.userRating;
      expect(newRating, isNot(equals(1500))); // Should have changed
    });

    test('Handles wrong move correctly', () async {
      // 1. Setup Puzzle
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'flow_test_002',
        title: 'Wrong Move Test',
        description: 'Testing failure flow',
        category: PuzzleCategory.formMill,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          const PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
            ],
          ),
        ],
        isCustom: true,
      );
      puzzleManager.addCustomPuzzle(puzzle);

      // 2. Initialize Game
      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);
      controller.gameInstance.gameMode = GameMode.puzzle;
      controller.position.setFen(puzzle.initialPosition);

      // 3. Player makes WRONG move (a4 instead of a1)
      final bool moveResult = controller.applyMove(
        ExtMove('a4', side: PieceColor.white),
      );
      expect(moveResult, isTrue);
      validator.addMove('a4');

      // 4. Validate
      final ValidationFeedback _ = validator.validateSolution(
        controller.position,
      );

      // Check auto-player response for this wrong line
      final List<List<String>> legacySolutions = puzzle.solutions
          .map(
            (PuzzleSolution s) =>
                s.moves.map((PuzzleMove m) => m.notation).toList(),
          )
          .toList();

      bool wrongMoveCallbackCalled = false;
      await PuzzleAutoPlayer.autoPlayOpponentResponses(
        solutions: legacySolutions,
        humanColor: PieceColor.white,
        isGameOver: () => false,
        sideToMove: () => PieceColor.black,
        movesSoFar: () => <String>['a4'],
        applyMove: (_) => true,
        onWrongMove: () async {
          wrongMoveCallbackCalled = true;
        },
      );

      // Since a4 is not in any solution, auto-player will trigger onWrongMove immediately
      expect(wrongMoveCallbackCalled, isTrue);

      // 5. Record attempt failure
      puzzleManager.recordAttempt(puzzle.id);
      final PuzzleProgress? progress = puzzleManager.getProgress(puzzle.id);
      expect(progress!.attempts, equals(1));
      expect(progress.completed, isFalse);
    });

    test('Handles capture puzzle flow', () async {
      // 1. Setup Puzzle (Capture 1 piece)
      final PuzzleInfo puzzle = PuzzleInfo(
        id: 'flow_test_capture',
        title: 'Capture Flow',
        description: 'Capture a piece',
        category: PuzzleCategory.capturePieces,
        difficulty: PuzzleDifficulty.easy,
        initialPosition:
            '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        solutions: <PuzzleSolution>[
          const PuzzleSolution(
            moves: <PuzzleMove>[
              PuzzleMove(notation: 'a1', side: PieceColor.white),
              PuzzleMove(notation: 'g1', side: PieceColor.black),
              PuzzleMove(notation: 'a4', side: PieceColor.white),
              PuzzleMove(notation: 'g4', side: PieceColor.black),
              PuzzleMove(notation: 'a7', side: PieceColor.white),
              PuzzleMove(notation: 'xg1', side: PieceColor.white), // Capture
            ],
          ),
        ],
        isCustom: true,
      );
      puzzleManager.addCustomPuzzle(puzzle);

      final PuzzleValidator validator = PuzzleValidator(puzzle: puzzle);
      controller.position.setFen(puzzle.initialPosition);

      // Simulate moves
      // Use g-line for opponent to avoid interference with a-line mill
      final List<String> moves = <String>['a1', 'g1', 'a4', 'g4', 'a7', 'xg1'];
      for (final String move in moves) {
        if (move.startsWith('x')) {
          // It's a removal.
          expect(controller.position.action, equals(Act.remove));
          final String square = move.substring(1);
          controller.applyMove(ExtMove(square, side: PieceColor.white));
        } else {
          controller.applyMove(
            ExtMove(move, side: controller.position.sideToMove),
          );
        }
        validator.addMove(move);
      }

      // Check validation
      final ValidationFeedback feedback = validator.validateSolution(
        controller.position,
      );
      expect(feedback.result, equals(ValidationResult.correct));
    });
  });
}
