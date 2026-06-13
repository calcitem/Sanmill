// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_settings_test.dart
//
// Tests for PuzzleSettings model including copyWith, progress management,
// and completion statistics.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

PuzzleInfo _makePuzzle(String id) {
  return PuzzleInfo(
    id: id,
    title: 'Puzzle $id',
    description: 'Description for $id',
    category: PuzzleCategory.formMill,
    difficulty: PuzzleDifficulty.easy,
    initialPosition:
        '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
    solutions: const <PuzzleSolution>[
      PuzzleSolution(
        moves: <PuzzleMove>[PuzzleMove(notation: 'a1', side: PieceColor.white)],
      ),
    ],
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
  // Default values
  // ---------------------------------------------------------------------------
  group('PuzzleSettings defaults', () {
    test('should have sensible defaults', () {
      const PuzzleSettings settings = PuzzleSettings();

      expect(settings.allPuzzles, isEmpty);
      expect(settings.progressMap, isEmpty);
      expect(settings.showHints, isTrue);
      expect(settings.autoShowSolution, isFalse);
      expect(settings.soundEnabled, isTrue);
      expect(settings.userRating, 1500);
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------
  group('PuzzleSettings.copyWith', () {
    test('should copy with no changes when no arguments', () {
      const PuzzleSettings original = PuzzleSettings(
        showHints: false,
        userRating: 1600,
      );
      final PuzzleSettings copy = original.copyWith();

      expect(copy.showHints, isFalse);
      expect(copy.userRating, 1600);
    });

    test('should override only specified fields', () {
      const PuzzleSettings original = PuzzleSettings();
      final PuzzleSettings updated = original.copyWith(
        showHints: false,
        autoShowSolution: true,
        userRating: 1800,
      );

      expect(updated.showHints, isFalse);
      expect(updated.autoShowSolution, isTrue);
      expect(updated.userRating, 1800);
      // Unchanged
      expect(updated.soundEnabled, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // getProgress / updateProgress
  // ---------------------------------------------------------------------------
  group('PuzzleSettings progress management', () {
    test('getProgress should return null for unknown puzzle', () {
      const PuzzleSettings settings = PuzzleSettings();
      expect(settings.getProgress('unknown'), isNull);
    });

    test('getProgress should return stored progress', () {
      final PuzzleSettings settings = PuzzleSettings(
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', completed: true, stars: 3),
        },
      );

      final PuzzleProgress? progress = settings.getProgress('p1');
      expect(progress, isNotNull);
      expect(progress!.completed, isTrue);
      expect(progress.stars, 3);
    });

    test('updateProgress should add new progress', () {
      const PuzzleSettings settings = PuzzleSettings();
      final PuzzleSettings updated = settings.updateProgress(
        PuzzleProgress(puzzleId: 'p1', completed: true, stars: 2),
      );

      expect(updated.getProgress('p1'), isNotNull);
      expect(updated.getProgress('p1')!.stars, 2);
    });

    test('updateProgress should replace existing progress', () {
      final PuzzleSettings settings = PuzzleSettings(
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', stars: 1),
        },
      );

      final PuzzleSettings updated = settings.updateProgress(
        PuzzleProgress(puzzleId: 'p1', completed: true, stars: 3),
      );

      expect(updated.getProgress('p1')!.stars, 3);
      expect(updated.getProgress('p1')!.completed, isTrue);
    });

    test('updateProgress should not affect other puzzles', () {
      final PuzzleSettings settings = PuzzleSettings(
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', stars: 1),
          'p2': PuzzleProgress(puzzleId: 'p2', stars: 2),
        },
      );

      final PuzzleSettings updated = settings.updateProgress(
        PuzzleProgress(puzzleId: 'p1', stars: 3),
      );

      expect(updated.getProgress('p1')!.stars, 3);
      expect(updated.getProgress('p2')!.stars, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // totalCompleted / totalStars / completionPercentage
  // ---------------------------------------------------------------------------
  group('PuzzleSettings statistics', () {
    test('totalCompleted should count completed puzzles in allPuzzles', () {
      final PuzzleSettings settings = PuzzleSettings(
        allPuzzles: <PuzzleInfo>[_makePuzzle('p1'), _makePuzzle('p2')],
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', completed: true),
          'p2': PuzzleProgress(puzzleId: 'p2'),
          'p3': PuzzleProgress(
            puzzleId: 'p3',
            completed: true,
          ), // Not in allPuzzles
        },
      );

      // Only p1 is completed AND in allPuzzles
      expect(settings.totalCompleted, 1);
    });

    test('totalStars should sum stars for existing puzzles', () {
      final PuzzleSettings settings = PuzzleSettings(
        allPuzzles: <PuzzleInfo>[_makePuzzle('p1'), _makePuzzle('p2')],
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', stars: 3),
          'p2': PuzzleProgress(puzzleId: 'p2', stars: 2),
          'p3': PuzzleProgress(puzzleId: 'p3', stars: 1), // Not in allPuzzles
        },
      );

      expect(settings.totalStars, 5); // 3 + 2 (p3 excluded)
    });

    test('completionPercentage should be 0 for empty puzzles', () {
      const PuzzleSettings settings = PuzzleSettings();
      expect(settings.completionPercentage, 0.0);
    });

    test('completionPercentage should be 100 when all completed', () {
      final PuzzleSettings settings = PuzzleSettings(
        allPuzzles: <PuzzleInfo>[_makePuzzle('p1'), _makePuzzle('p2')],
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', completed: true),
          'p2': PuzzleProgress(puzzleId: 'p2', completed: true),
        },
      );

      expect(settings.completionPercentage, 100.0);
    });

    test('completionPercentage should be 50 when half completed', () {
      final PuzzleSettings settings = PuzzleSettings(
        allPuzzles: <PuzzleInfo>[_makePuzzle('p1'), _makePuzzle('p2')],
        progressMap: <String, PuzzleProgress>{
          'p1': PuzzleProgress(puzzleId: 'p1', completed: true),
          'p2': PuzzleProgress(puzzleId: 'p2'),
        },
      );

      expect(settings.completionPercentage, 50.0);
    });
  });

  // ---------------------------------------------------------------------------
  // JSON serialization
  // ---------------------------------------------------------------------------
  group('PuzzleSettings JSON', () {
    test('toJson should include all fields', () {
      const PuzzleSettings settings = PuzzleSettings(
        showHints: false,
        autoShowSolution: true,
        soundEnabled: false,
        userRating: 1800,
      );

      final Map<String, dynamic> json = settings.toJson();

      expect(json['showHints'], isFalse);
      expect(json['autoShowSolution'], isTrue);
      expect(json['soundEnabled'], isFalse);
      expect(json['userRating'], 1800);
    });

    test('fromJson should parse basic fields', () {
      final PuzzleSettings settings = PuzzleSettings.fromJson(<String, dynamic>{
        'showHints': false,
        'autoShowSolution': true,
        'soundEnabled': false,
        'userRating': 2000,
      });

      expect(settings.showHints, isFalse);
      expect(settings.autoShowSolution, isTrue);
      expect(settings.soundEnabled, isFalse);
      expect(settings.userRating, 2000);
    });

    test('fromJson with empty map should use defaults', () {
      final PuzzleSettings settings = PuzzleSettings.fromJson(
        const <String, dynamic>{},
      );

      expect(settings.showHints, isTrue);
      expect(settings.autoShowSolution, isFalse);
      expect(settings.soundEnabled, isTrue);
      expect(settings.userRating, 1500);
    });
  });
}
