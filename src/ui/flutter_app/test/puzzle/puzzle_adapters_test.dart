// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_adapters_test.dart
//
// Tests for puzzle Hive type adapter constants and type IDs.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_adapters.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

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
  // Type ID constants
  // ---------------------------------------------------------------------------
  group('Puzzle adapter type ID constants', () {
    test('should have unique type IDs', () {
      final Set<int> ids = <int>{
        puzzleInfoTypeId,
        puzzleProgressTypeId,
        puzzleSettingsTypeId,
        puzzleDifficultyTypeId,
        puzzleCategoryTypeId,
        pieceColorTypeId,
        puzzleMoveTypeId,
        puzzleSolutionTypeId,
        puzzlePackMetadataTypeId,
      };

      expect(ids.length, 9, reason: 'All type IDs should be unique');
    });

    test('type IDs should be in the 30-40 range', () {
      expect(puzzleInfoTypeId, 30);
      expect(puzzleProgressTypeId, 31);
      expect(puzzleSettingsTypeId, 32);
      expect(puzzleDifficultyTypeId, 33);
      expect(puzzleCategoryTypeId, 34);
      expect(pieceColorTypeId, 35);
      expect(puzzleMoveTypeId, 36);
      expect(puzzleSolutionTypeId, 37);
      expect(puzzlePackMetadataTypeId, 38);
    });
  });

  // ---------------------------------------------------------------------------
  // PieceColorAdapter
  // ---------------------------------------------------------------------------
  group('PieceColorAdapter', () {
    test('should have typeId 35', () {
      final PieceColorAdapter adapter = PieceColorAdapter();
      expect(adapter.typeId, 35);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleDifficultyAdapter
  // ---------------------------------------------------------------------------
  group('PuzzleDifficultyAdapter', () {
    test('should have correct typeId', () {
      final PuzzleDifficultyAdapter adapter = PuzzleDifficultyAdapter();
      expect(adapter.typeId, puzzleDifficultyTypeId);
      expect(adapter.typeId, 33);
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleCategoryAdapter
  // ---------------------------------------------------------------------------
  group('PuzzleCategoryAdapter', () {
    test('should have correct typeId', () {
      final PuzzleCategoryAdapter adapter = PuzzleCategoryAdapter();
      expect(adapter.typeId, puzzleCategoryTypeId);
      expect(adapter.typeId, 34);
    });
  });

  // ---------------------------------------------------------------------------
  // No collision with other adapters
  // ---------------------------------------------------------------------------
  group('Adapter type ID collision check', () {
    test('puzzle type IDs should not collide with stats type IDs', () {
      // Stats adapters use typeIds 50, 51
      // Puzzle adapters use 30-38
      // Rule variant uses 35 (same range)
      // Ensure no overlap with display (1), general (2), rule (3/4/8/10) adapters
      final List<int> puzzleIds = <int>[
        puzzleInfoTypeId,
        puzzleProgressTypeId,
        puzzleSettingsTypeId,
        puzzleDifficultyTypeId,
        puzzleCategoryTypeId,
        pieceColorTypeId,
        puzzleMoveTypeId,
        puzzleSolutionTypeId,
        puzzlePackMetadataTypeId,
      ];

      // Known type IDs from other parts of the app
      const List<int> otherIds = <int>[
        0, // ColorSettings
        1, // DisplaySettings
        2, // GeneralSettings
        3, // RuleSettings
        4, // BoardFullAction
        5, // SearchAlgorithm
        6, // LegacyColorAdapter
        7, // LocaleAdapter
        8, // StalemateAction
        9, // PointPaintingStyle
        10, // MillFormationActionInPlacingPhase
        11, // SoundTheme
        12, // MovesViewLayout
        13, // LlmProvider
        50, // PlayerStats
        51, // StatsSettings
      ];

      for (final int pid in puzzleIds) {
        expect(
          otherIds.contains(pid),
          isFalse,
          reason: 'Puzzle typeId $pid collides with another adapter',
        );
      }
    });
  });
}
