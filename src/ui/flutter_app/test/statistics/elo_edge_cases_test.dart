// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// elo_edge_cases_test.dart
//
// Additional edge-case tests for ELO rating calculation functions.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/statistics/services/stats_service.dart';

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
  // calculateNewRatings - edge cases
  // ---------------------------------------------------------------------------
  group('calculateNewRatings edge cases', () {
    test('minimum valid rating difference', () {
      // Same rating, win should still produce a change
      final (int newHuman, int newAi) = calculateNewRatings(
        1000,
        1000,
        HumanOutcome.playerWin,
        30,
      );

      expect(newHuman, greaterThan(1000));
      expect(newAi, lessThan(1000));
    });

    test('maximum K-factor scenario (new player < 30 games)', () {
      // With K=40, change should be about 20 for 50% expected
      final (int newHuman, _) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        1, // Very few games
      );

      final int change = newHuman - 1500;
      expect(change, greaterThanOrEqualTo(15));
      expect(change, lessThanOrEqualTo(25));
    });

    test('K-factor transition at exactly 30 games', () {
      final (int newHumanAt29, _) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        29, // Just under 30 → K=40
      );
      final (int newHumanAt30, _) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        30, // At 30 → K=20
      );

      final int changeAt29 = newHumanAt29 - 1500;
      final int changeAt30 = newHumanAt30 - 1500;
      expect(
        changeAt29,
        greaterThan(changeAt30),
        reason: 'K=40 at 29 games should produce larger change than K=20 at 30',
      );
    });

    test('K-factor transition at 2400 rating', () {
      final (int newHumanBelow, _) = calculateNewRatings(
        2399,
        2399,
        HumanOutcome.playerWin,
        100,
      );
      final (int newHumanAtOrAbove, _) = calculateNewRatings(
        2400,
        2400,
        HumanOutcome.playerWin,
        100,
      );

      final int changeBelow = newHumanBelow - 2399;
      final int changeAtOrAbove = newHumanAtOrAbove - 2400;
      expect(
        changeBelow,
        greaterThan(changeAtOrAbove),
        reason:
            'K=20 below 2400 should produce larger change than K=10 at 2400',
      );
    });

    test('draw against same-rated opponent should give 0 change', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.draw,
        100,
      );

      expect(newHuman, 1500);
      expect(newAi, 1500);
    });

    test('rating changes should sum to zero', () {
      // The sum of human and AI rating changes must be zero
      for (final HumanOutcome outcome in HumanOutcome.values) {
        final (int newHuman, int newAi) = calculateNewRatings(
          1500,
          1700,
          outcome,
          50,
        );

        final int humanChange = newHuman - 1500;
        final int aiChange = newAi - 1700;
        expect(
          humanChange + aiChange,
          0,
          reason: 'Changes should sum to zero for $outcome',
        );
      }
    });

    test('very low ratings should still work', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        100,
        100,
        HumanOutcome.playerWin,
        50,
      );

      expect(newHuman, greaterThan(100));
      expect(newAi, lessThan(100));
    });

    test('very high ratings should still work', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        3000,
        3000,
        HumanOutcome.playerWin,
        100,
      );

      expect(newHuman, greaterThan(3000));
      expect(newAi, lessThan(3000));
    });
  });

  // ---------------------------------------------------------------------------
  // processGamesForHumanRating - edge cases
  // ---------------------------------------------------------------------------
  group('processGamesForHumanRating edge cases', () {
    test('single game win as unrated player', () {
      final int rating = processGamesForHumanRating(
        null,
        <int>[1500],
        <double>[1.0],
        1,
      );

      // Should be in provisional bounds [1400 .. 1550]
      expect(rating, greaterThanOrEqualTo(1400));
      expect(rating, lessThanOrEqualTo(1550));
    });

    test('single game loss as unrated player', () {
      final int rating = processGamesForHumanRating(
        null,
        <int>[1500],
        <double>[0.0],
        1,
      );

      // Should be at minimum bound
      expect(rating, greaterThanOrEqualTo(1400));
    });

    test('exactly 4 games uses n*150 upper bound', () {
      final int rating = processGamesForHumanRating(
        null,
        <int>[1500, 1500, 1500, 1500],
        <double>[1.0, 1.0, 1.0, 1.0], // All wins
        4,
      );

      // For 4 games, upper bound = 1400 + 4*150 = 2000
      expect(rating, lessThanOrEqualTo(2000));
      expect(rating, greaterThanOrEqualTo(1400));
    });

    test('transition from provisional to standard at game 5', () {
      // At exactly 5 total games, should use standard update
      final int ratingStandard = processGamesForHumanRating(
        1500,
        <int>[1500],
        <double>[1.0],
        5,
      );

      expect(ratingStandard, greaterThan(1500));
    });

    test('large batch of games', () {
      // 10 games at once, mixed results
      final int rating = processGamesForHumanRating(
        1500,
        List<int>.filled(10, 1500),
        <double>[1.0, 0.0, 1.0, 0.5, 0.0, 1.0, 0.5, 1.0, 0.0, 0.5],
        20,
      );

      // With 5.5/10 against equal opponents, should be slightly above 1500
      expect(rating, closeTo(1500, 50));
    });

    test('all wins against very weak opponents', () {
      final int rating = processGamesForHumanRating(
        2000,
        <int>[500, 500, 500],
        <double>[1.0, 1.0, 1.0],
        50,
      );

      // Should increase only slightly (beating much weaker opponents)
      expect(rating, greaterThan(2000));
      final int change = rating - 2000;
      expect(
        change,
        lessThan(20),
        reason: 'Small gain for beating much weaker opponents',
      );
    });

    test('all losses against very strong opponents', () {
      final int rating = processGamesForHumanRating(
        1000,
        <int>[2500, 2500, 2500],
        <double>[0.0, 0.0, 0.0],
        50,
      );

      // Should decrease only slightly (losing to much stronger opponents)
      expect(rating, lessThan(1000));
      final int change = 1000 - rating;
      expect(
        change,
        lessThan(20),
        reason: 'Small loss against much stronger opponents',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // HumanOutcome enum
  // ---------------------------------------------------------------------------
  group('HumanOutcome', () {
    test('should have three values', () {
      expect(HumanOutcome.values.length, 3);
    });

    test('should include all expected outcomes', () {
      expect(
        HumanOutcome.values,
        containsAll(<HumanOutcome>[
          HumanOutcome.playerWin,
          HumanOutcome.opponentWin,
          HumanOutcome.draw,
        ]),
      );
    });
  });
}
