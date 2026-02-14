// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_collection_manager_test.dart
//
// Tests for PuzzleCollectionManager grouping and variant management.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

PuzzleInfo _makePuzzle({
  required String id,
  String ruleVariantId = 'standard_9mm',
  PuzzleDifficulty difficulty = PuzzleDifficulty.easy,
}) {
  return PuzzleInfo(
    id: id,
    title: 'Puzzle $id',
    description: 'Description $id',
    category: PuzzleCategory.formMill,
    difficulty: difficulty,
    initialPosition:
        '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
    solutions: const <PuzzleSolution>[
      PuzzleSolution(
        moves: <PuzzleMove>[
          PuzzleMove(notation: 'a1', side: PieceColor.white),
        ],
      ),
    ],
    ruleVariantId: ruleVariantId,
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
  // Empty manager
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionManager empty', () {
    test('should have no collections when given empty list', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[],
      );

      expect(manager.allCollections, isEmpty);
      expect(manager.availableVariants, isEmpty);
    });

    test('getCollection should return null for unknown variant', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[],
      );

      expect(manager.getCollection('nonexistent'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Single variant
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionManager single variant', () {
    test('should group puzzles by variant', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '2', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '3', ruleVariantId: 'standard_9mm'),
        ],
      );

      expect(manager.allCollections.length, 1);
      expect(manager.getCollection('standard_9mm'), isNotNull);
      expect(manager.getCollection('standard_9mm')!.puzzles.length, 3);
    });

    test('availableVariants should list the variant', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
        ],
      );

      expect(manager.availableVariants.length, 1);
      expect(manager.availableVariants.first.id, 'standard_9mm');
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple variants
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionManager multiple variants', () {
    test('should create separate collections per variant', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '2', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '3', ruleVariantId: 'twelve_mens_morris'),
          _makePuzzle(id: '4', ruleVariantId: 'twelve_mens_morris'),
          _makePuzzle(id: '5', ruleVariantId: 'twelve_mens_morris'),
        ],
      );

      expect(manager.allCollections.length, 2);
      expect(manager.getCollection('standard_9mm')!.puzzles.length, 2);
      expect(
        manager.getCollection('twelve_mens_morris')!.puzzles.length,
        3,
      );
    });

    test('availableVariants should list all variants', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '2', ruleVariantId: 'twelve_mens_morris'),
        ],
      );

      final List<String> ids = manager.availableVariants
          .map((RuleVariant v) => v.id)
          .toList();
      expect(ids, contains('standard_9mm'));
      expect(ids, contains('twelve_mens_morris'));
    });
  });

  // ---------------------------------------------------------------------------
  // Unknown variants
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionManager unknown variants', () {
    test('should ignore puzzles with unknown variant IDs', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'unknown_variant'),
        ],
      );

      // Unknown variants are not in PredefinedVariants, so no collection
      expect(manager.getCollection('unknown_variant'), isNull);
      expect(manager.allCollections, isEmpty);
    });

    test('should keep known variants and ignore unknown', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
          _makePuzzle(id: '2', ruleVariantId: 'unknown_variant'),
        ],
      );

      expect(manager.allCollections.length, 1);
      expect(manager.getCollection('standard_9mm')!.puzzles.length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------
  group('PuzzleCollectionManager.refresh', () {
    test('should rebuild collections after refresh', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
        ],
      );

      expect(manager.getCollection('standard_9mm')!.puzzles.length, 1);

      // Refresh with more puzzles
      manager.refresh(<PuzzleInfo>[
        _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
        _makePuzzle(id: '2', ruleVariantId: 'standard_9mm'),
        _makePuzzle(id: '3', ruleVariantId: 'twelve_mens_morris'),
      ]);

      expect(manager.getCollection('standard_9mm')!.puzzles.length, 2);
      expect(manager.getCollection('twelve_mens_morris'), isNotNull);
    });

    test('refresh with empty list should clear collections', () {
      final PuzzleCollectionManager manager = PuzzleCollectionManager(
        <PuzzleInfo>[
          _makePuzzle(id: '1', ruleVariantId: 'standard_9mm'),
        ],
      );

      manager.refresh(<PuzzleInfo>[]);

      expect(manager.allCollections, isEmpty);
    });
  });
}
