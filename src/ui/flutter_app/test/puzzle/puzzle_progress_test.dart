// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';

void main() {
  group('PuzzleProgress', () {
    group('constructor and basic properties', () {
      test('creates with default values', () {
        final PuzzleProgress progress = PuzzleProgress(puzzleId: 'test_001');

        expect(progress.puzzleId, equals('test_001'));
        expect(progress.completed, isFalse);
        expect(progress.stars, equals(0));
        expect(progress.bestMoveCount, isNull);
        expect(progress.attempts, equals(0));
        expect(progress.hintsUsed, equals(0));
        expect(progress.solutionViewed, isFalse);
        expect(progress.lastAttemptDate, isNull);
        expect(progress.completionDate, isNull);
      });

      test('creates with all fields specified', () {
        final DateTime now = DateTime.now();
        final DateTime earlier = now.subtract(const Duration(days: 1));

        final PuzzleProgress progress = PuzzleProgress(
          puzzleId: 'test_002',
          completed: true,
          stars: 3,
          bestMoveCount: 5,
          attempts: 3,
          hintsUsed: 1,
          solutionViewed: false,
          lastAttemptDate: now,
          completionDate: earlier,
        );

        expect(progress.puzzleId, equals('test_002'));
        expect(progress.completed, isTrue);
        expect(progress.stars, equals(3));
        expect(progress.bestMoveCount, equals(5));
        expect(progress.attempts, equals(3));
        expect(progress.hintsUsed, equals(1));
        expect(progress.solutionViewed, isFalse);
        expect(progress.lastAttemptDate, equals(now));
        expect(progress.completionDate, equals(earlier));
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final PuzzleProgress original = PuzzleProgress(
          puzzleId: 'test_003',
          completed: false,
          stars: 0,
        );

        final PuzzleProgress updated = original.copyWith(
          completed: true,
          stars: 3,
          bestMoveCount: 7,
        );

        expect(updated.puzzleId, equals('test_003'));
        expect(updated.completed, isTrue);
        expect(updated.stars, equals(3));
        expect(updated.bestMoveCount, equals(7));
      });

      test('preserves original values when not specified', () {
        final DateTime now = DateTime.now();
        final PuzzleProgress original = PuzzleProgress(
          puzzleId: 'test_004',
          completed: true,
          stars: 2,
          attempts: 5,
          lastAttemptDate: now,
        );

        final PuzzleProgress updated = original.copyWith(stars: 3);

        expect(updated.puzzleId, equals('test_004'));
        expect(updated.completed, isTrue);
        expect(updated.stars, equals(3));
        expect(updated.attempts, equals(5));
        expect(updated.lastAttemptDate, equals(now));
      });
    });

    group('JSON serialization', () {
      test('toJson serializes all fields correctly', () {
        final DateTime now = DateTime.now();
        final DateTime earlier = now.subtract(const Duration(days: 2));

        final PuzzleProgress progress = PuzzleProgress(
          puzzleId: 'test_005',
          completed: true,
          stars: 3,
          bestMoveCount: 8,
          attempts: 4,
          hintsUsed: 2,
          solutionViewed: true,
          lastAttemptDate: now,
          completionDate: earlier,
        );

        final Map<String, dynamic> json = progress.toJson();

        expect(json['puzzleId'], equals('test_005'));
        expect(json['completed'], isTrue);
        expect(json['stars'], equals(3));
        expect(json['bestMoveCount'], equals(8));
        expect(json['attempts'], equals(4));
        expect(json['hintsUsed'], equals(2));
        expect(json['solutionViewed'], isTrue);
        expect(json['lastAttemptDate'], equals(now.toIso8601String()));
        expect(json['completionDate'], equals(earlier.toIso8601String()));
      });

      test('fromJson deserializes all fields correctly', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_006',
          'completed': true,
          'stars': 2,
          'bestMoveCount': 10,
          'attempts': 6,
          'hintsUsed': 3,
          'solutionViewed': false,
          'lastAttemptDate': '2026-01-15T10:30:00.000Z',
          'completionDate': '2026-01-14T15:20:00.000Z',
        };

        final PuzzleProgress progress = PuzzleProgress.fromJson(json);

        expect(progress.puzzleId, equals('test_006'));
        expect(progress.completed, isTrue);
        expect(progress.stars, equals(2));
        expect(progress.bestMoveCount, equals(10));
        expect(progress.attempts, equals(6));
        expect(progress.hintsUsed, equals(3));
        expect(progress.solutionViewed, isFalse);
        expect(progress.lastAttemptDate, isNotNull);
        expect(progress.completionDate, isNotNull);
      });

      test('fromJson handles missing optional fields', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_007',
        };

        final PuzzleProgress progress = PuzzleProgress.fromJson(json);

        expect(progress.puzzleId, equals('test_007'));
        expect(progress.completed, isFalse);
        expect(progress.stars, equals(0));
        expect(progress.bestMoveCount, isNull);
        expect(progress.attempts, equals(0));
        expect(progress.hintsUsed, equals(0));
        expect(progress.solutionViewed, isFalse);
        expect(progress.lastAttemptDate, isNull);
        expect(progress.completionDate, isNull);
      });

      test('round-trip serialization preserves data', () {
        final DateTime now = DateTime.now();
        final PuzzleProgress original = PuzzleProgress(
          puzzleId: 'test_008',
          completed: true,
          stars: 3,
          bestMoveCount: 12,
          attempts: 2,
          hintsUsed: 0,
          solutionViewed: false,
          lastAttemptDate: now,
          completionDate: now,
        );

        final Map<String, dynamic> json = original.toJson();
        final PuzzleProgress deserialized = PuzzleProgress.fromJson(json);

        expect(deserialized.puzzleId, equals(original.puzzleId));
        expect(deserialized.completed, equals(original.completed));
        expect(deserialized.stars, equals(original.stars));
        expect(deserialized.bestMoveCount, equals(original.bestMoveCount));
        expect(deserialized.attempts, equals(original.attempts));
        expect(deserialized.hintsUsed, equals(original.hintsUsed));
        expect(deserialized.solutionViewed, equals(original.solutionViewed));
      });
    });

    group('calculateStars', () {
      test('awards 3 stars for optimal solution without hints', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 5,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      });

      test('awards 2 stars for near-optimal without hints', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 6,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: false,
        );

        expect(stars, equals(2));
      });

      test('awards 1 star for acceptable solution without hints', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 7,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: false,
        );

        expect(stars, equals(1));
      });

      test('awards 0 stars for poor solution', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 10,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: false,
        );

        expect(stars, equals(0));
      });

      test('awards maximum 2 stars when hints used', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 5,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: true,
        );

        expect(stars, equals(2));
      });

      test('awards 1 star when hints used and near-optimal', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 6,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: true,
        );

        expect(stars, equals(1));
      });

      test('awards 0 stars when hints used and poor solution', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 10,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.medium,
          hintsUsed: true,
        );

        expect(stars, equals(0));
      });

      test('awards 0 stars when solution viewed', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 5,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.easy,
          hintsUsed: false,
          solutionViewed: true,
        );

        expect(stars, equals(0));
      });

      test('respects beginner difficulty star threshold', () {
        // Beginner allows 3 extra moves for 3 stars
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 8,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.beginner,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      });

      test('respects easy difficulty star threshold', () {
        // Easy allows 2 extra moves for 3 stars
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 7,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.easy,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      });

      test('respects hard difficulty star threshold', () {
        // Hard allows 1 extra move for 3 stars
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 6,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.hard,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      });

      test('respects expert difficulty star threshold', () {
        // Expert requires exact optimal for 3 stars
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 6,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.expert,
          hintsUsed: false,
        );

        expect(stars, equals(2));
      });

      test('respects master difficulty star threshold', () {
        // Master requires exact optimal for 3 stars
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 6,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.master,
          hintsUsed: false,
        );

        expect(stars, equals(2));
      });
    });

    group('edge cases', () {
      test('handles zero optimal move count', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 0,
          optimalMoveCount: 0,
          difficulty: PuzzleDifficulty.easy,
          hintsUsed: false,
        );

        expect(stars, equals(3));
      });

      test('handles very large move counts', () {
        final int stars = PuzzleProgress.calculateStars(
          moveCount: 1000,
          optimalMoveCount: 5,
          difficulty: PuzzleDifficulty.beginner,
          hintsUsed: false,
        );

        expect(stars, equals(0));
      });

      test('handles negative attempts in copyWith', () {
        final PuzzleProgress progress = PuzzleProgress(
          puzzleId: 'test_009',
          attempts: 5,
        );

        // This should not fail - negative attempts is allowed by the model
        final PuzzleProgress updated = progress.copyWith(attempts: -1);

        expect(updated.attempts, equals(-1));
      });

      test('handles null dates in JSON', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_010',
          'lastAttemptDate': null,
          'completionDate': null,
        };

        final PuzzleProgress progress = PuzzleProgress.fromJson(json);

        expect(progress.lastAttemptDate, isNull);
        expect(progress.completionDate, isNull);
      });
    });
  });
}
