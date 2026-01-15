// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/services/puzzle_manager.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory appDocDir;
  late PuzzleManager manager;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

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

    // Provide a stable documents directory for Hive/path_provider callers
    appDocDir = Directory.systemTemp.createTempSync('sanmill_manager_test_');
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
    manager = PuzzleManager();
  });

  setUp(() async {
    // Reset manager state before each test
    await manager.init();
    manager.settingsNotifier.value = const PuzzleSettings();
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

  group('PuzzleManager', () {
    test('initializes with empty state', () {
      expect(manager.getAllPuzzles(), isEmpty);
    });

    group('Custom Puzzles', () {
      late PuzzleInfo customPuzzle;

      setUp(() {
        customPuzzle = PuzzleInfo(
          id: 'custom_001',
          title: 'Custom Puzzle',
          description: 'A custom puzzle',
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
          ],
          isCustom: true,
          author: 'Me',
        );
      });

      test('addCustomPuzzle adds puzzle', () {
        final bool added = manager.addCustomPuzzle(customPuzzle);
        expect(added, isTrue);

        final List<PuzzleInfo> puzzles = manager.getAllPuzzles();
        expect(puzzles.length, equals(1));
        expect(puzzles.first.id, equals('custom_001'));
      });

      test('addCustomPuzzle fails for duplicate ID', () {
        manager.addCustomPuzzle(customPuzzle);
        final bool addedAgain = manager.addCustomPuzzle(customPuzzle);

        expect(addedAgain, isFalse);
        expect(manager.getAllPuzzles().length, equals(1));
      });

      test('getCustomPuzzles returns only custom puzzles', () {
        // Add custom puzzle
        manager.addCustomPuzzle(customPuzzle);

        // Mock a built-in puzzle (by manipulating settings directly for test)
        final PuzzleInfo builtInPuzzle = customPuzzle.copyWith(
          id: 'builtin_001',
          isCustom: false,
        );
        final PuzzleSettings settings = manager.settingsNotifier.value;
        manager.settingsNotifier.value = settings.copyWith(
          allPuzzles: <PuzzleInfo>[...settings.allPuzzles, builtInPuzzle],
        );

        final List<PuzzleInfo> customPuzzles = manager.getCustomPuzzles();
        expect(customPuzzles.length, equals(1));
        expect(customPuzzles.first.id, equals('custom_001'));
      });

      test('deletePuzzle deletes custom puzzle', () {
        manager.addCustomPuzzle(customPuzzle);
        final bool deleted = manager.deletePuzzle('custom_001');

        expect(deleted, isTrue);
        expect(manager.getAllPuzzles(), isEmpty);
      });

      test('deletePuzzle fails for non-existent puzzle', () {
        final bool deleted = manager.deletePuzzle('non_existent');
        expect(deleted, isFalse);
      });

      test('deletePuzzle fails for built-in puzzle', () {
        // Mock a built-in puzzle
        final PuzzleInfo builtInPuzzle = customPuzzle.copyWith(
          id: 'builtin_002',
          isCustom: false,
        );
        final PuzzleSettings settings = manager.settingsNotifier.value;
        manager.settingsNotifier.value = settings.copyWith(
          allPuzzles: <PuzzleInfo>[builtInPuzzle],
        );

        final bool deleted = manager.deletePuzzle('builtin_002');
        expect(deleted, isFalse);
        expect(manager.getAllPuzzles().length, equals(1));
      });

      test('updatePuzzle updates existing custom puzzle', () {
        manager.addCustomPuzzle(customPuzzle);

        final PuzzleInfo updatedPuzzle = customPuzzle.copyWith(
          title: 'Updated Title',
        );
        final bool updated = manager.updatePuzzle(updatedPuzzle);

        expect(updated, isTrue);
        final PuzzleInfo? retrieved = manager.getPuzzleById('custom_001');
        expect(retrieved?.title, equals('Updated Title'));
      });
    });

    group('Progress Tracking', () {
      late PuzzleInfo testPuzzle;

      setUp(() {
        testPuzzle = PuzzleInfo(
          id: 'prog_test_001',
          title: 'Progress Test',
          description: 'Testing progress',
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
          isCustom: true,
          rating: 1500,
        );
        manager.addCustomPuzzle(testPuzzle);
      });

      test('recordAttempt increments attempts', () {
        manager.recordAttempt('prog_test_001');

        final PuzzleProgress? progress = manager.getProgress('prog_test_001');
        expect(progress, isNotNull);
        expect(progress!.attempts, equals(1));
      });

      test('recordHintUsed increments hints used', () {
        manager.recordHintUsed('prog_test_001');

        final PuzzleProgress? progress = manager.getProgress('prog_test_001');
        expect(progress, isNotNull);
        expect(progress!.hintsUsed, equals(1));
      });

      test('completePuzzle updates progress and calculates stars', () {
        manager.completePuzzle(
          puzzleId: 'prog_test_001',
          moveCount: 1,
          difficulty: PuzzleDifficulty.easy,
          optimalMoveCount: 1,
          hintsUsed: false,
        );

        final PuzzleProgress? progress = manager.getProgress('prog_test_001');
        expect(progress, isNotNull);
        expect(progress!.completed, isTrue);
        expect(progress.stars, equals(3));
        expect(progress.bestMoveCount, equals(1));
      });

      test('completePuzzle updates user rating', () {
        final int initialRating = manager.settingsNotifier.value.userRating;

        manager.completePuzzle(
          puzzleId: 'prog_test_001',
          moveCount: 1,
          difficulty: PuzzleDifficulty.easy,
          optimalMoveCount: 1,
          hintsUsed: false,
        );

        final int newRating = manager.settingsNotifier.value.userRating;
        expect(newRating, isNot(equals(initialRating)));
      });

      test('resetProgress clears progress for puzzle', () {
        manager.completePuzzle(
          puzzleId: 'prog_test_001',
          moveCount: 1,
          difficulty: PuzzleDifficulty.easy,
          optimalMoveCount: 1,
          hintsUsed: false,
        );

        manager.resetProgress('prog_test_001');

        final PuzzleProgress? progress = manager.getProgress('prog_test_001');
        // PuzzleProgress is technically not deleted, but reset to default values
        // or actually the implementation replaces it with new PuzzleProgress(id)
        expect(progress, isNotNull);
        expect(progress!.completed, isFalse);
        expect(progress.stars, equals(0));
        expect(progress.attempts, equals(0));
      });

      test('resetAllProgress clears all progress', () {
        manager.completePuzzle(
          puzzleId: 'prog_test_001',
          moveCount: 1,
          difficulty: PuzzleDifficulty.easy,
          optimalMoveCount: 1,
          hintsUsed: false,
        );

        manager.resetAllProgress();

        final PuzzleProgress? progress = manager.getProgress('prog_test_001');
        expect(progress, isNull);
      });
    });

    group('Recommendations', () {
      test('getRecommendedPuzzles filters and sorts', () {
        // Create puzzles with different ratings
        final List<PuzzleInfo> puzzles = <PuzzleInfo>[
          PuzzleInfo(
            id: 'rec_1000',
            title: 'Easy',
            description: 'Easy',
            category: PuzzleCategory.formMill,
            difficulty: PuzzleDifficulty.beginner,
            initialPosition: 'fen',
            solutions: const <PuzzleSolution>[],
            rating: 1000,
            isCustom: true,
          ),
          PuzzleInfo(
            id: 'rec_1500',
            title: 'Medium',
            description: 'Medium',
            category: PuzzleCategory.formMill,
            difficulty: PuzzleDifficulty.medium,
            initialPosition: 'fen',
            solutions: const <PuzzleSolution>[],
            rating: 1500,
            isCustom: true,
          ),
          PuzzleInfo(
            id: 'rec_2000',
            title: 'Hard',
            description: 'Hard',
            category: PuzzleCategory.formMill,
            difficulty: PuzzleDifficulty.hard,
            initialPosition: 'fen',
            solutions: const <PuzzleSolution>[],
            rating: 2000,
            isCustom: true,
          ),
        ];

        puzzles.forEach(manager.addCustomPuzzle);

        // Test with user rating 1450
        // Should recommend 1500 (diff 50) and maybe 1000 (diff 450 - outside default range 200?)
        // Wait, default range is 200.
        // 1450 -> 1000 is diff 450 (excluded)
        // 1450 -> 1500 is diff 50 (included)
        // 1450 -> 2000 is diff 550 (excluded)

        List<PuzzleInfo> recommended = manager.getRecommendedPuzzles(
          targetRating: 1450,
        );

        expect(recommended.length, equals(1));
        expect(recommended.first.id, equals('rec_1500'));

        // Test with wider range
        recommended = manager.getRecommendedPuzzles(
          targetRating: 1450,
          ratingRange: 500,
        );

        expect(recommended.length, equals(2)); // 1500 and 1000
        expect(recommended[0].id, equals('rec_1500')); // Closest
        expect(recommended[1].id, equals('rec_1000'));
      });
    });

    group('Settings', () {
      test('updateSettings updates values', () {
        manager.updateSettings(
          showHints: true,
          autoShowSolution: true,
          soundEnabled: false,
        );

        final PuzzleSettings settings = manager.settingsNotifier.value;
        expect(settings.showHints, isTrue);
        expect(settings.autoShowSolution, isTrue);
        expect(settings.soundEnabled, isFalse);
      });
    });
  });
}
