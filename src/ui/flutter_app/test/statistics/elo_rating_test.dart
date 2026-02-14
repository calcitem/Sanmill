// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// elo_rating_test.dart

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
  // calculateNewRatings
  // ---------------------------------------------------------------------------
  group('calculateNewRatings', () {
    test('winning should increase human rating', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        50,
      );

      expect(newHuman, greaterThan(1500));
      expect(newAi, lessThan(1500));
    });

    test('losing should decrease human rating', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.opponentWin,
        50,
      );

      expect(newHuman, lessThan(1500));
      expect(newAi, greaterThan(1500));
    });

    test('draw with equal ratings should leave ratings nearly unchanged', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.draw,
        50,
      );

      // With equal ratings, expected score is ~0.5 and actual score is 0.5,
      // so the change should be 0 or very small
      expect(newHuman, closeTo(1500, 5));
      expect(newAi, closeTo(1500, 5));
    });

    test('human and AI rating changes should be symmetric', () {
      final (int newHuman, int newAi) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        50,
      );

      // The sum of rating changes should be 0
      final int humanChange = newHuman - 1500;
      final int aiChange = newAi - 1500;
      expect(humanChange + aiChange, 0);
    });

    test('beating a higher-rated player gives more points', () {
      final (int newHumanVsStrong, _) = calculateNewRatings(
        1500,
        2000,
        HumanOutcome.playerWin,
        50,
      );
      final (int newHumanVsWeak, _) = calculateNewRatings(
        1500,
        1000,
        HumanOutcome.playerWin,
        50,
      );

      final int gainVsStrong = newHumanVsStrong - 1500;
      final int gainVsWeak = newHumanVsWeak - 1500;
      expect(
        gainVsStrong,
        greaterThan(gainVsWeak),
        reason: 'More points for beating stronger opponent',
      );
    });

    test('losing to a weaker player costs more points', () {
      final (int newHumanVsWeak, _) = calculateNewRatings(
        1500,
        1000,
        HumanOutcome.opponentWin,
        50,
      );
      final (int newHumanVsStrong, _) = calculateNewRatings(
        1500,
        2000,
        HumanOutcome.opponentWin,
        50,
      );

      final int lossVsWeak = 1500 - newHumanVsWeak;
      final int lossVsStrong = 1500 - newHumanVsStrong;
      expect(
        lossVsWeak,
        greaterThan(lossVsStrong),
        reason: 'More penalty for losing to weaker opponent',
      );
    });

    test('K-factor: new player (< 30 games) gets K=40', () {
      // With few games, the change should be larger (K=40)
      final (int newHumanFew, _) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        5, // Few games
      );

      final (int newHumanMany, _) = calculateNewRatings(
        1500,
        1500,
        HumanOutcome.playerWin,
        100, // Many games
      );

      final int changeFew = newHumanFew - 1500;
      final int changeMany = newHumanMany - 1500;
      expect(
        changeFew,
        greaterThan(changeMany),
        reason: 'New player should have larger K-factor',
      );
    });

    test('K-factor: high-rated player (>= 2400) gets K=10', () {
      // Player at 2400+ should use K=10
      final (int newHighRated, _) = calculateNewRatings(
        2400,
        2400,
        HumanOutcome.playerWin,
        100,
      );

      final (int newMidRated, _) = calculateNewRatings(
        1800,
        1800,
        HumanOutcome.playerWin,
        100,
      );

      final int changeHigh = newHighRated - 2400;
      final int changeMid = newMidRated - 1800;
      expect(
        changeHigh,
        lessThan(changeMid),
        reason: 'High-rated player should have smaller K-factor',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // processGamesForHumanRating
  // ---------------------------------------------------------------------------
  group('processGamesForHumanRating', () {
    test('unrated player should get a provisional rating', () {
      final int rating = processGamesForHumanRating(
        null, // currentHumanRating
        <int>[1500], // AI ratings
        <double>[1.0], // Win
        1, // totalGamesPlayed
      );

      // Provisional rating should be bounded [1400 .. 1400 + 1*150]
      expect(rating, greaterThanOrEqualTo(1400));
      expect(rating, lessThanOrEqualTo(1550));
    });

    test('< 5 games: should use provisional rating with bounds', () {
      final int rating = processGamesForHumanRating(
        1500,
        <int>[1200],
        <double>[1.0],
        3, // totalGamesPlayed
      );

      // For 3 games, upper bound is 1400 + 3*150 = 1850
      expect(rating, greaterThanOrEqualTo(1400));
      expect(rating, lessThanOrEqualTo(1850));
    });

    test('>= 5 games: should use standard ELO update', () {
      final int rating = processGamesForHumanRating(
        1500,
        <int>[1500],
        <double>[1.0],
        10, // totalGamesPlayed >= 5
      );

      // Standard update: winning should increase rating
      expect(rating, greaterThan(1500));
    });

    test('batch processing: multiple games at once', () {
      final int rating = processGamesForHumanRating(
        1600,
        <int>[1400, 1500, 1600], // 3 AI opponents
        <double>[1.0, 0.5, 0.0], // Win, draw, loss
        20,
      );

      // With mixed results around same rating, should be close to original
      expect(rating, closeTo(1600, 50));
    });

    test('all losses should decrease provisional rating', () {
      final int rating = processGamesForHumanRating(
        null,
        <int>[1500, 1500, 1500],
        <double>[0.0, 0.0, 0.0], // All losses
        3,
      );

      // Should still be bounded at 1400 minimum
      expect(rating, greaterThanOrEqualTo(1400));
    });

    test('all wins against high-rated opponents should increase rating', () {
      final int rating = processGamesForHumanRating(
        1500,
        <int>[2000, 2000, 2000],
        <double>[1.0, 1.0, 1.0], // All wins
        50,
      );

      expect(rating, greaterThan(1500));
    });

    test('5 games exactly uses 5-game bounding for provisional', () {
      final int rating = processGamesForHumanRating(
        null,
        <int>[1500, 1500, 1500, 1500, 1500],
        <double>[1.0, 1.0, 1.0, 1.0, 1.0],
        5,
      );

      // For exactly 5 games, bounds are [1400 .. 2200]
      expect(rating, greaterThanOrEqualTo(1400));
      expect(rating, lessThanOrEqualTo(2200));
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------
  group('ELO edge cases', () {
    test('very large rating difference should be capped', () {
      // Rating difference > 400 is capped at 400
      final (int newHuman, _) = calculateNewRatings(
        3000,
        1000,
        HumanOutcome.opponentWin,
        100,
      );

      // Even with 2000 point difference, the penalty should not be extreme
      expect(newHuman, greaterThan(2800));
    });

    test('draw with large rating gap: underdog gains points', () {
      final (int newHuman, _) = calculateNewRatings(
        1200,
        2000,
        HumanOutcome.draw,
        50,
      );

      // A draw as the lower-rated player should gain rating
      expect(newHuman, greaterThan(1200));
    });

    test('draw with large rating gap: favorite loses points', () {
      final (int newHuman, _) = calculateNewRatings(
        2000,
        1200,
        HumanOutcome.draw,
        50,
      );

      // A draw as the higher-rated player should lose rating
      expect(newHuman, lessThan(2000));
    });
  });
}
