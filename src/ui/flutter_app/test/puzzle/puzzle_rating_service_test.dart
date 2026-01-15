// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/puzzle/services/puzzle_rating_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel =
      MethodChannel('com.calcitem.sanmill/engine');
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');

  late Directory appDocDir;

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
    appDocDir = Directory.systemTemp.createTempSync('sanmill_rating_test_');
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
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    // Clean up test directory
    if (appDocDir.existsSync()) {
      appDocDir.deleteSync(recursive: true);
    }
  });

  group('PuzzleRating', () {
    test('creates with all properties', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1500,
        gamesPlayed: 10,
        provisionalGames: 20,
        ratingDeviation: 150.0,
      );

      expect(rating.rating, equals(1500));
      expect(rating.gamesPlayed, equals(10));
      expect(rating.provisionalGames, equals(20));
      expect(rating.ratingDeviation, equals(150.0));
    });

    test('isProvisional returns true when under threshold', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1500,
        gamesPlayed: 5,
        provisionalGames: 20,
        ratingDeviation: 200.0,
      );

      expect(rating.isProvisional, isTrue);
    });

    test('isProvisional returns false when at or above threshold', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1500,
        gamesPlayed: 20,
        provisionalGames: 20,
        ratingDeviation: 100.0,
      );

      expect(rating.isProvisional, isFalse);
    });

    test('isProvisional returns false when exceeded threshold', () {
      final PuzzleRating rating = PuzzleRating(
        rating: 1600,
        gamesPlayed: 50,
        provisionalGames: 20,
        ratingDeviation: 50.0,
      );

      expect(rating.isProvisional, isFalse);
    });
  });

  group('PuzzleAttemptResult', () {
    group('constructor and basic properties', () {
      test('creates with all fields', () {
        final DateTime now = DateTime.now();
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_001',
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 1,
          movesPlayed: 5,
          timestamp: now,
          oldRating: 1500,
          newRating: 1520,
          ratingChange: 20,
        );

        expect(result.puzzleId, equals('test_001'));
        expect(result.success, isTrue);
        expect(result.timeSpent, equals(const Duration(seconds: 30)));
        expect(result.hintsUsed, equals(1));
        expect(result.movesPlayed, equals(5));
        expect(result.timestamp, equals(now));
        expect(result.oldRating, equals(1500));
        expect(result.newRating, equals(1520));
        expect(result.ratingChange, equals(20));
      });

      test('creates with null rating fields', () {
        final DateTime now = DateTime.now();
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_002',
          success: false,
          timeSpent: const Duration(minutes: 2),
          hintsUsed: 0,
          movesPlayed: 10,
          timestamp: now,
        );

        expect(result.oldRating, isNull);
        expect(result.newRating, isNull);
        expect(result.ratingChange, isNull);
      });
    });

    group('JSON serialization', () {
      test('toJson serializes all fields correctly', () {
        final DateTime timestamp = DateTime.utc(2026, 1, 15, 10, 30);
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_003',
          success: true,
          timeSpent: const Duration(seconds: 45),
          hintsUsed: 2,
          movesPlayed: 7,
          timestamp: timestamp,
          oldRating: 1400,
          newRating: 1430,
          ratingChange: 30,
        );

        final Map<String, dynamic> json = result.toJson();

        expect(json['puzzleId'], equals('test_003'));
        expect(json['success'], isTrue);
        expect(json['timeSpentMs'], equals(45000));
        expect(json['hintsUsed'], equals(2));
        expect(json['movesPlayed'], equals(7));
        expect(json['timestamp'], equals(timestamp.toIso8601String()));
        expect(json['oldRating'], equals(1400));
        expect(json['newRating'], equals(1430));
        expect(json['ratingChange'], equals(30));
      });

      test('toJson omits null rating fields', () {
        final DateTime timestamp = DateTime.now();
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_004',
          success: false,
          timeSpent: const Duration(seconds: 60),
          hintsUsed: 0,
          movesPlayed: 8,
          timestamp: timestamp,
        );

        final Map<String, dynamic> json = result.toJson();

        expect(json.containsKey('puzzleId'), isTrue);
        expect(json.containsKey('success'), isTrue);
        expect(json.containsKey('oldRating'), isFalse);
        expect(json.containsKey('newRating'), isFalse);
        expect(json.containsKey('ratingChange'), isFalse);
      });

      test('fromJson deserializes all fields correctly', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_005',
          'success': true,
          'timeSpentMs': 120000,
          'hintsUsed': 3,
          'movesPlayed': 12,
          'timestamp': '2026-01-15T14:30:00.000Z',
          'oldRating': 1550,
          'newRating': 1540,
          'ratingChange': -10,
        };

        final PuzzleAttemptResult result = PuzzleAttemptResult.fromJson(json);

        expect(result.puzzleId, equals('test_005'));
        expect(result.success, isTrue);
        expect(result.timeSpent, equals(const Duration(milliseconds: 120000)));
        expect(result.hintsUsed, equals(3));
        expect(result.movesPlayed, equals(12));
        expect(result.timestamp, isNotNull);
        expect(result.oldRating, equals(1550));
        expect(result.newRating, equals(1540));
        expect(result.ratingChange, equals(-10));
      });

      test('fromJson handles missing optional fields', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_006',
          'timestamp': '2026-01-15T10:00:00.000Z',
        };

        final PuzzleAttemptResult result = PuzzleAttemptResult.fromJson(json);

        expect(result.puzzleId, equals('test_006'));
        expect(result.success, isFalse);
        expect(result.timeSpent, equals(Duration.zero));
        expect(result.hintsUsed, equals(0));
        expect(result.movesPlayed, equals(0));
        expect(result.oldRating, isNull);
        expect(result.newRating, isNull);
        expect(result.ratingChange, isNull);
      });

      test('round-trip serialization preserves data', () {
        final DateTime timestamp = DateTime.utc(2026, 1, 15, 12, 0);
        final PuzzleAttemptResult original = PuzzleAttemptResult(
          puzzleId: 'test_007',
          success: true,
          timeSpent: const Duration(seconds: 90),
          hintsUsed: 1,
          movesPlayed: 6,
          timestamp: timestamp,
          oldRating: 1600,
          newRating: 1625,
          ratingChange: 25,
        );

        final Map<String, dynamic> json = original.toJson();
        final PuzzleAttemptResult deserialized =
            PuzzleAttemptResult.fromJson(json);

        expect(deserialized.puzzleId, equals(original.puzzleId));
        expect(deserialized.success, equals(original.success));
        expect(deserialized.timeSpent, equals(original.timeSpent));
        expect(deserialized.hintsUsed, equals(original.hintsUsed));
        expect(deserialized.movesPlayed, equals(original.movesPlayed));
        expect(deserialized.oldRating, equals(original.oldRating));
        expect(deserialized.newRating, equals(original.newRating));
        expect(deserialized.ratingChange, equals(original.ratingChange));
      });
    });

    group('edge cases', () {
      test('handles zero duration', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_008',
          success: true,
          timeSpent: Duration.zero,
          hintsUsed: 0,
          movesPlayed: 3,
          timestamp: DateTime.now(),
        );

        expect(result.timeSpent, equals(Duration.zero));

        final Map<String, dynamic> json = result.toJson();
        expect(json['timeSpentMs'], equals(0));
      });

      test('handles very long duration', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_009',
          success: false,
          timeSpent: const Duration(hours: 24),
          hintsUsed: 5,
          movesPlayed: 20,
          timestamp: DateTime.now(),
        );

        expect(result.timeSpent, equals(const Duration(hours: 24)));

        final Map<String, dynamic> json = result.toJson();
        expect(json['timeSpentMs'], equals(86400000));
      });

      test('handles negative rating change', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_010',
          success: false,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 0,
          movesPlayed: 15,
          timestamp: DateTime.now(),
          oldRating: 1600,
          newRating: 1570,
          ratingChange: -30,
        );

        expect(result.ratingChange, equals(-30));

        final Map<String, dynamic> json = result.toJson();
        final PuzzleAttemptResult deserialized =
            PuzzleAttemptResult.fromJson(json);

        expect(deserialized.ratingChange, equals(-30));
      });

      test('handles large rating values', () {
        final PuzzleAttemptResult result = PuzzleAttemptResult(
          puzzleId: 'test_011',
          success: true,
          timeSpent: const Duration(seconds: 15),
          hintsUsed: 0,
          movesPlayed: 4,
          timestamp: DateTime.now(),
          oldRating: 2800,
          newRating: 2850,
          ratingChange: 50,
        );

        expect(result.oldRating, equals(2800));
        expect(result.newRating, equals(2850));
      });

      test('handles invalid timestamp in JSON gracefully', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_012',
          'timestamp': 'invalid-timestamp',
        };

        // Should assert in debug mode but we're testing the behavior
        expect(
          () => PuzzleAttemptResult.fromJson(json),
          throwsAssertionError,
        );
      });

      test('handles null timestamp in JSON', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'puzzleId': 'test_013',
          'timestamp': null,
        };

        // Should assert because timestamp is null
        expect(
          () => PuzzleAttemptResult.fromJson(json),
          throwsAssertionError,
        );
      });
    });
  });

  group('PuzzleRatingService', () {
    late PuzzleRatingService service;

    setUp(() {
      service = PuzzleRatingService();
    });

    group('singleton pattern', () {
      test('returns same instance', () {
        final PuzzleRatingService instance1 = PuzzleRatingService();
        final PuzzleRatingService instance2 = PuzzleRatingService();

        expect(identical(instance1, instance2), isTrue);
      });
    });

    group('initial state', () {
      test('has default initial rating', () {
        final PuzzleRating rating = service.getCurrentRating();

        expect(rating.rating, greaterThan(0));
        expect(rating.gamesPlayed, greaterThanOrEqualTo(0));
      });

      test('starts with empty history', () {
        final List<PuzzleAttemptResult> history = service.getHistory();

        expect(history, isEmpty);
      });
    });

    group('recording attempts', () {
      test('records successful attempt without hints', () {
        final DateTime before = DateTime.now();
        service.recordAttempt(
          puzzleId: 'record_001',
          puzzleRating: 1500,
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 0,
          movesPlayed: 5,
        );
        final DateTime after = DateTime.now();

        final List<PuzzleAttemptResult> history = service.getHistory();

        expect(history.length, equals(1));
        expect(history.first.puzzleId, equals('record_001'));
        expect(history.first.success, isTrue);
        expect(history.first.hintsUsed, equals(0));
        expect(
          history.first.timestamp.isAfter(before.subtract(
            const Duration(seconds: 1),
          )),
          isTrue,
        );
        expect(
          history.first.timestamp.isBefore(after.add(
            const Duration(seconds: 1),
          )),
          isTrue,
        );
      });

      test('records failed attempt', () {
        service.recordAttempt(
          puzzleId: 'record_002',
          puzzleRating: 1600,
          success: false,
          timeSpent: const Duration(seconds: 60),
          hintsUsed: 2,
          movesPlayed: 10,
        );

        final List<PuzzleAttemptResult> history = service.getHistory();

        expect(history.last.puzzleId, equals('record_002'));
        expect(history.last.success, isFalse);
        expect(history.last.hintsUsed, equals(2));
      });

      test('records multiple attempts', () {
        service.recordAttempt(
          puzzleId: 'record_003',
          puzzleRating: 1400,
          success: true,
          timeSpent: const Duration(seconds: 20),
          hintsUsed: 0,
          movesPlayed: 4,
        );

        service.recordAttempt(
          puzzleId: 'record_004',
          puzzleRating: 1500,
          success: false,
          timeSpent: const Duration(seconds: 40),
          hintsUsed: 1,
          movesPlayed: 8,
        );

        final List<PuzzleAttemptResult> history = service.getHistory();

        expect(history.length, greaterThanOrEqualTo(2));
      });
    });

    group('rating updates', () {
      test('rating increases after successful attempt', () {
        final int initialRating = service.getCurrentRating().rating;

        service.recordAttempt(
          puzzleId: 'rating_001',
          puzzleRating: initialRating - 100,
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 0,
          movesPlayed: 5,
        );

        final int newRating = service.getCurrentRating().rating;

        expect(newRating, greaterThanOrEqualTo(initialRating));
      });

      test('rating decreases after failed attempt', () {
        final int initialRating = service.getCurrentRating().rating;

        service.recordAttempt(
          puzzleId: 'rating_002',
          puzzleRating: initialRating + 100,
          success: false,
          timeSpent: const Duration(seconds: 60),
          hintsUsed: 0,
          movesPlayed: 10,
        );

        final int newRating = service.getCurrentRating().rating;

        expect(newRating, lessThanOrEqualTo(initialRating));
      });
    });

    group('statistics', () {
      test('calculates total attempts', () {
        service.recordAttempt(
          puzzleId: 'stats_001',
          puzzleRating: 1500,
          success: true,
          timeSpent: const Duration(seconds: 30),
          hintsUsed: 0,
          movesPlayed: 5,
        );

        service.recordAttempt(
          puzzleId: 'stats_002',
          puzzleRating: 1500,
          success: false,
          timeSpent: const Duration(seconds: 40),
          hintsUsed: 1,
          movesPlayed: 8,
        );

        final PuzzleRating rating = service.getCurrentRating();

        expect(rating.gamesPlayed, greaterThanOrEqualTo(2));
      });
    });

    group('edge cases', () {
      test('handles very high puzzle rating', () {
        expect(
          () => service.recordAttempt(
            puzzleId: 'edge_001',
            puzzleRating: 3000,
            success: true,
            timeSpent: const Duration(seconds: 30),
            hintsUsed: 0,
            movesPlayed: 5,
          ),
          returnsNormally,
        );
      });

      test('handles very low puzzle rating', () {
        expect(
          () => service.recordAttempt(
            puzzleId: 'edge_002',
            puzzleRating: 100,
            success: false,
            timeSpent: const Duration(seconds: 30),
            hintsUsed: 0,
            movesPlayed: 5,
          ),
          returnsNormally,
        );
      });

      test('handles zero time spent', () {
        expect(
          () => service.recordAttempt(
            puzzleId: 'edge_003',
            puzzleRating: 1500,
            success: true,
            timeSpent: Duration.zero,
            hintsUsed: 0,
            movesPlayed: 3,
          ),
          returnsNormally,
        );
      });
    });
  });
}
