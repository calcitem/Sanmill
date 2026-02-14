// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_attempt_result_test.dart
//
// Tests for PuzzleAttemptResult, PuzzleRating, and HintType.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/services/puzzle_hint_service.dart';
import 'package:sanmill/puzzle/services/puzzle_rating_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PuzzleAttemptResult
  // ---------------------------------------------------------------------------
  group('PuzzleAttemptResult', () {
    group('constructor', () {
      test('should store all required fields', () {
        final DateTime now = DateTime(2026, 2, 14, 12, 0, 0);
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'puzzle-1',
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 1,
          movesPlayed: 5,
          timestamp: now,
        );

        expect(result.puzzleId, 'puzzle-1');
        expect(result.success, isTrue);
        expect(result.timeSpent, const Duration(seconds: 30));
        expect(result.hintsUsed, 1);
        expect(result.movesPlayed, 5);
        expect(result.timestamp, now);
        expect(result.oldRating, isNull);
        expect(result.newRating, isNull);
        expect(result.ratingChange, isNull);
      });

      test('should accept optional rating fields', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'puzzle-1',
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 0,
          movesPlayed: 3,
          timestamp: DateTime(2026, 1, 1),
          oldRating: 1500,
          newRating: 1520,
          ratingChange: 20,
        );

        expect(result.oldRating, 1500);
        expect(result.newRating, 1520);
        expect(result.ratingChange, 20);
      });
    });

    group('toJson', () {
      test('should include all required fields', () {
        final DateTime now = DateTime(2026, 2, 14, 12, 0, 0);
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'puzzle-1',
          success: true,
          timeSpent: const Duration(seconds: 45),
          hintsUsed: 2,
          movesPlayed: 7,
          timestamp: now,
        );

        final Map<String, dynamic> json = result.toJson();

        expect(json['puzzleId'], 'puzzle-1');
        expect(json['success'], isTrue);
        expect(json['timeSpentMs'], 45000);
        expect(json['hintsUsed'], 2);
        expect(json['movesPlayed'], 7);
        expect(json['timestamp'], now.toIso8601String());
      });

      test('should include optional rating fields when present', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'puzzle-1',
          success: false,
          timeSpent: const Duration(minutes: 2),
          hintsUsed: 0,
          movesPlayed: 10,
          timestamp: DateTime(2026, 1, 1),
          oldRating: 1500,
          newRating: 1480,
          ratingChange: -20,
        );

        final Map<String, dynamic> json = result.toJson();

        expect(json['oldRating'], 1500);
        expect(json['newRating'], 1480);
        expect(json['ratingChange'], -20);
      });

      test('should omit optional fields when null', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'puzzle-1',
          success: true,
          timeSpent: Duration.zero,
          hintsUsed: 0,
          movesPlayed: 0,
          timestamp: DateTime(2026, 1, 1),
        );

        final Map<String, dynamic> json = result.toJson();

        expect(json.containsKey('oldRating'), isFalse);
        expect(json.containsKey('newRating'), isFalse);
        expect(json.containsKey('ratingChange'), isFalse);
      });
    });

    group('fromJson', () {
      test('should parse all fields correctly', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'puzzle-42',
          'success': true,
          'timeSpentMs': 60000,
          'hintsUsed': 1,
          'movesPlayed': 5,
          'timestamp': '2026-02-14T12:00:00.000',
          'oldRating': 1500,
          'newRating': 1525,
          'ratingChange': 25,
        };

        final PuzzleAttemptResult result = PuzzleAttemptResult.fromJson(json);

        expect(result.puzzleId, 'puzzle-42');
        expect(result.success, isTrue);
        expect(result.timeSpent.inMilliseconds, 60000);
        expect(result.hintsUsed, 1);
        expect(result.movesPlayed, 5);
        expect(result.oldRating, 1500);
        expect(result.newRating, 1525);
        expect(result.ratingChange, 25);
      });

      test('should use defaults for missing fields', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'timestamp': '2026-01-01T00:00:00.000',
        };

        final PuzzleAttemptResult result = PuzzleAttemptResult.fromJson(json);

        expect(result.puzzleId, '');
        expect(result.success, isFalse);
        expect(result.timeSpent.inMilliseconds, 0);
        expect(result.hintsUsed, 0);
        expect(result.movesPlayed, 0);
      });
    });

    group('toJson / fromJson round-trip', () {
      test('should preserve all data through round-trip', () {
        final DateTime now = DateTime(2026, 2, 14, 12, 0, 0);
        final PuzzleAttemptResult original = PuzzleAttemptResult(
          puzzleId: 'puzzle-99',
          success: false,
          timeSpent: const Duration(seconds: 90),
          hintsUsed: 3,
          movesPlayed: 12,
          timestamp: now,
          oldRating: 1600,
          newRating: 1575,
          ratingChange: -25,
        );

        final Map<String, dynamic> json = original.toJson();
        final PuzzleAttemptResult restored = PuzzleAttemptResult.fromJson(json);

        expect(restored.puzzleId, original.puzzleId);
        expect(restored.success, original.success);
        expect(
          restored.timeSpent.inMilliseconds,
          original.timeSpent.inMilliseconds,
        );
        expect(restored.hintsUsed, original.hintsUsed);
        expect(restored.movesPlayed, original.movesPlayed);
        expect(restored.oldRating, original.oldRating);
        expect(restored.newRating, original.newRating);
        expect(restored.ratingChange, original.ratingChange);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleRating
  // ---------------------------------------------------------------------------
  group('PuzzleRating', () {
    test('should be provisional when gamesPlayed < provisionalGames', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1500,
        gamesPlayed: 5,
        provisionalGames: 10,
        ratingDeviation: 350.0,
      );

      expect(rating.isProvisional, isTrue);
    });

    test('should not be provisional when gamesPlayed >= provisionalGames', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1600,
        gamesPlayed: 10,
        provisionalGames: 10,
        ratingDeviation: 50.0,
      );

      expect(rating.isProvisional, isFalse);
    });

    test('should not be provisional when gamesPlayed > provisionalGames', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1700,
        gamesPlayed: 50,
        provisionalGames: 10,
        ratingDeviation: 50.0,
      );

      expect(rating.isProvisional, isFalse);
    });

    test('should be mutable for rating updates', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1500,
        gamesPlayed: 0,
        provisionalGames: 10,
        ratingDeviation: 350.0,
      );

      rating.rating = 1520;
      rating.gamesPlayed = 1;

      expect(rating.rating, 1520);
      expect(rating.gamesPlayed, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // HintType enum
  // ---------------------------------------------------------------------------
  group('HintType', () {
    test('should have four hint types', () {
      expect(HintType.values.length, 4);
    });

    test('should include all expected types', () {
      expect(
        HintType.values,
        containsAll(<HintType>[
          HintType.textual,
          HintType.nextMove,
          HintType.highlight,
          HintType.showSolution,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PuzzleHint
  // ---------------------------------------------------------------------------
  group('PuzzleHint', () {
    test('should store type and content', () {
      const PuzzleHint hint = PuzzleHint(
        type: HintType.textual,
        content: 'Try forming a mill on the left side',
      );

      expect(hint.type, HintType.textual);
      expect(hint.content, 'Try forming a mill on the left side');
      expect(hint.moveIndex, isNull);
      expect(hint.highlightSquares, isNull);
    });

    test('should store optional moveIndex', () {
      const PuzzleHint hint = PuzzleHint(
        type: HintType.nextMove,
        content: 'd6',
        moveIndex: 3,
      );

      expect(hint.moveIndex, 3);
    });

    test('should store optional highlightSquares', () {
      const PuzzleHint hint = PuzzleHint(
        type: HintType.highlight,
        content: 'These squares form a mill',
        highlightSquares: <int>[8, 9, 10],
      );

      expect(hint.highlightSquares, <int>[8, 9, 10]);
    });
  });
}
