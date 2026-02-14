// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_collection_test.dart
//
// Tests for PuzzleCollection and PuzzleCollectionStats.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

/// Helper to create a minimal PuzzleInfo for testing.
PuzzleInfo _makePuzzle({
  required String id,
  PuzzleDifficulty difficulty = PuzzleDifficulty.easy,
  PuzzleCategory category = PuzzleCategory.formMill,
  int? rating,
  bool isCustom = false,
}) {
  return PuzzleInfo(
    id: id,
    title: 'Test Puzzle $id',
    description: 'Description for $id',
    category: category,
    difficulty: difficulty,
    initialPosition:
        '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
    solutions: const <PuzzleSolution>[
      PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      ),
    ],
    rating: rating,
    isCustom: isCustom,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // PuzzleCollection
  // ---------------------------------------------------------------------------
  group('PuzzleCollection', () {
    late PuzzleCollection collection;
    late RuleVariant variant;

    setUp(() {
      variant = PredefinedVariants.nineMensMorris;
      collection = PuzzleCollection(
        variant: variant,
        puzzles: <PuzzleInfo>[
          _makePuzzle(
            id: '1',
            difficulty: PuzzleDifficulty.beginner,
            category: PuzzleCategory.formMill,
            rating: 1200,
          ),
          _makePuzzle(
            id: '2',
            difficulty: PuzzleDifficulty.easy,
            category: PuzzleCategory.capturePieces,
            rating: 1400,
          ),
          _makePuzzle(
            id: '3',
            difficulty: PuzzleDifficulty.medium,
            category: PuzzleCategory.formMill,
            rating: 1600,
          ),
          _makePuzzle(
            id: '4',
            difficulty: PuzzleDifficulty.hard,
            category: PuzzleCategory.winGame,
            isCustom: true,
          ),
          _makePuzzle(
            id: '5',
            difficulty: PuzzleDifficulty.easy,
            category: PuzzleCategory.defend,
            rating: 1300,
            isCustom: true,
          ),
        ],
      );
    });

    group('getPuzzlesByDifficulty', () {
      test('should filter by difficulty', () {
        final List<PuzzleInfo> easy = collection.getPuzzlesByDifficulty(
          PuzzleDifficulty.easy,
        );
        expect(easy.length, 2);
        expect(
          easy.every((PuzzleInfo p) => p.difficulty == PuzzleDifficulty.easy),
          isTrue,
        );
      });

      test('should return empty for no matches', () {
        final List<PuzzleInfo> master = collection.getPuzzlesByDifficulty(
          PuzzleDifficulty.master,
        );
        expect(master, isEmpty);
      });
    });

    group('getPuzzlesByCategory', () {
      test('should filter by category', () {
        final List<PuzzleInfo> formMill = collection.getPuzzlesByCategory(
          PuzzleCategory.formMill,
        );
        expect(formMill.length, 2);
      });

      test('should return empty for no matches', () {
        final List<PuzzleInfo> endgame = collection.getPuzzlesByCategory(
          PuzzleCategory.endgame,
        );
        expect(endgame, isEmpty);
      });
    });

    group('getPuzzlesByRatingRange', () {
      test('should filter by rating range', () {
        final List<PuzzleInfo> mid = collection.getPuzzlesByRatingRange(
          1300,
          1500,
        );
        expect(mid.length, 2); // puzzles 2 (1400) and 5 (1300)
      });

      test('should exclude puzzles without ratings', () {
        final List<PuzzleInfo> all = collection.getPuzzlesByRatingRange(
          0,
          9999,
        );
        // Only 4 puzzles have ratings (puzzle 4 has no rating)
        expect(all.length, 4);
      });
    });

    group('getCustomPuzzles / getBuiltInPuzzles', () {
      test('should separate custom and built-in puzzles', () {
        final List<PuzzleInfo> custom = collection.getCustomPuzzles();
        final List<PuzzleInfo> builtIn = collection.getBuiltInPuzzles();

        expect(custom.length, 2);
        expect(builtIn.length, 3);
        expect(custom.length + builtIn.length, collection.puzzles.length);
      });
    });

    group('getSortedByDifficulty', () {
      test('should sort easiest first', () {
        final List<PuzzleInfo> sorted = collection.getSortedByDifficulty();

        for (int i = 0; i < sorted.length - 1; i++) {
          expect(
            sorted[i].difficulty.index,
            lessThanOrEqualTo(sorted[i + 1].difficulty.index),
            reason:
                'Puzzle ${sorted[i].id} should not be harder than '
                '${sorted[i + 1].id}',
          );
        }
      });
    });

    group('getSortedByRating', () {
      test('should sort lowest rating first', () {
        final List<PuzzleInfo> sorted = collection.getSortedByRating();

        // Should only include rated puzzles
        expect(sorted.every((PuzzleInfo p) => p.rating != null), isTrue);

        for (int i = 0; i < sorted.length - 1; i++) {
          expect(
            sorted[i].rating!,
            lessThanOrEqualTo(sorted[i + 1].rating!),
            reason:
                'Rating ${sorted[i].rating} should be <= '
                '${sorted[i + 1].rating}',
          );
        }
      });
    });

    group('stats', () {
      test('should return correct totals', () {
        final PuzzleCollectionStats stats = collection.stats;

        expect(stats.totalPuzzles, 5);
        expect(stats.customPuzzles, 2);
        expect(stats.builtInPuzzles, 3);
      });

      test('should count by difficulty', () {
        final PuzzleCollectionStats stats = collection.stats;

        expect(stats.byDifficulty[PuzzleDifficulty.beginner], 1);
        expect(stats.byDifficulty[PuzzleDifficulty.easy], 2);
        expect(stats.byDifficulty[PuzzleDifficulty.medium], 1);
        expect(stats.byDifficulty[PuzzleDifficulty.hard], 1);
        expect(stats.byDifficulty[PuzzleDifficulty.expert], 0);
        expect(stats.byDifficulty[PuzzleDifficulty.master], 0);
      });

      test('should count by category', () {
        final PuzzleCollectionStats stats = collection.stats;

        expect(stats.byCategory[PuzzleCategory.formMill], 2);
        expect(stats.byCategory[PuzzleCategory.capturePieces], 1);
        expect(stats.byCategory[PuzzleCategory.winGame], 1);
        expect(stats.byCategory[PuzzleCategory.defend], 1);
        expect(stats.byCategory[PuzzleCategory.endgame], 0);
      });

      test('should calculate average rating excluding unrated', () {
        final PuzzleCollectionStats stats = collection.stats;

        // Rated puzzles: 1200, 1400, 1600, 1300 → avg = 1375
        expect(stats.averageRating, closeTo(1375, 1));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Empty collection
  // ---------------------------------------------------------------------------
  group('PuzzleCollection empty', () {
    test('empty collection stats should be zeroed', () {
      final PuzzleCollection empty = PuzzleCollection(
        variant: PredefinedVariants.nineMensMorris,
        puzzles: <PuzzleInfo>[],
      );

      final PuzzleCollectionStats stats = empty.stats;
      expect(stats.totalPuzzles, 0);
      expect(stats.customPuzzles, 0);
      expect(stats.builtInPuzzles, 0);
      expect(stats.averageRating, isNull);
    });

    test('filters on empty collection should return empty', () {
      final PuzzleCollection empty = PuzzleCollection(
        variant: PredefinedVariants.nineMensMorris,
        puzzles: <PuzzleInfo>[],
      );

      expect(empty.getPuzzlesByDifficulty(PuzzleDifficulty.easy), isEmpty);
      expect(empty.getPuzzlesByCategory(PuzzleCategory.formMill), isEmpty);
      expect(empty.getCustomPuzzles(), isEmpty);
      expect(empty.getBuiltInPuzzles(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleCollectionStats
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionStats', () {
    test('should store all fields', () {
      final PuzzleCollectionStats stats = PuzzleCollectionStats(
        totalPuzzles: 100,
        customPuzzles: 20,
        builtInPuzzles: 80,
        byDifficulty: <PuzzleDifficulty, int>{
          PuzzleDifficulty.easy: 50,
          PuzzleDifficulty.hard: 50,
        },
        byCategory: <PuzzleCategory, int>{PuzzleCategory.formMill: 100},
        averageRating: 1500.0,
      );

      expect(stats.totalPuzzles, 100);
      expect(stats.customPuzzles, 20);
      expect(stats.builtInPuzzles, 80);
      expect(stats.averageRating, 1500.0);
    });
  });
}
