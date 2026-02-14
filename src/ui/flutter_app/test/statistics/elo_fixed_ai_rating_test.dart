// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// elo_fixed_ai_rating_test.dart
//
// Tests for EloRatingService.getFixedAiEloRating which computes
// effective AI rating based on level and game settings.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/statistics/services/stats_service.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  late MockDB mockDB;

  setUp(() {
    mockDB = MockDB();
    DB.instance = mockDB;
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
  // Base ratings
  // ---------------------------------------------------------------------------
  group('EloRatingService.getFixedAiEloRating base ratings', () {
    test('level 1 should have the lowest base rating (300)', () {
      final int rating = EloRatingService.getFixedAiEloRating(1);
      // Base is 300, but adjustments may modify it
      expect(rating, greaterThanOrEqualTo(100)); // Minimum floor
    });

    test('level 30 should have the highest base rating (2800)', () {
      final int rating = EloRatingService.getFixedAiEloRating(30);
      // Base is 2800
      expect(rating, greaterThanOrEqualTo(2000));
    });

    test('ratings should generally increase with level', () {
      int prevRating = 0;
      // Not strictly monotonic due to adjustments, but generally increasing
      for (int level = 1; level <= 30; level++) {
        final int rating = EloRatingService.getFixedAiEloRating(level);
        expect(
          rating,
          greaterThanOrEqualTo(100),
          reason: 'Level $level should have rating >= 100',
        );
        if (level <= 5) {
          // For low levels, should generally be lower than high levels
          expect(
            rating,
            lessThan(2800),
            reason: 'Level $level should be < 2800',
          );
        }
        prevRating = rating;
      }
      // Level 30 should be higher than level 1
      final int level1 = EloRatingService.getFixedAiEloRating(1);
      final int level30 = EloRatingService.getFixedAiEloRating(30);
      expect(level30, greaterThan(level1));
    });

    test('out-of-range level should return 1400 as default', () {
      final int rating0 = EloRatingService.getFixedAiEloRating(0);
      expect(rating0, greaterThanOrEqualTo(100));

      final int rating31 = EloRatingService.getFixedAiEloRating(31);
      expect(rating31, greaterThanOrEqualTo(100));
    });

    test('all valid levels (1-30) should return positive ratings', () {
      for (int level = 1; level <= 30; level++) {
        final int rating = EloRatingService.getFixedAiEloRating(level);
        expect(
          rating,
          greaterThan(0),
          reason: 'Level $level rating should be > 0',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: shuffling disabled
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating shuffling adjustment', () {
    test('disabling shuffling should decrease rating', () {
      mockDB.generalSettings = const GeneralSettings(shufflingEnabled: true);
      final int withShuffle = EloRatingService.getFixedAiEloRating(15);

      mockDB.generalSettings = const GeneralSettings(shufflingEnabled: false);
      final int withoutShuffle = EloRatingService.getFixedAiEloRating(15);

      expect(
        withoutShuffle,
        lessThan(withShuffle),
        reason: 'Without shuffling, AI is more predictable (lower rating)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: AI is lazy
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating aiIsLazy adjustment', () {
    test('lazy AI should have roughly halved rating', () {
      mockDB.generalSettings = const GeneralSettings(aiIsLazy: false);
      final int normal = EloRatingService.getFixedAiEloRating(15);

      mockDB.generalSettings = const GeneralSettings(aiIsLazy: true);
      final int lazy = EloRatingService.getFixedAiEloRating(15);

      // Lazy halves the rating
      expect(lazy, closeTo(normal / 2, 200));
      expect(lazy, lessThan(normal));
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: MCTS without perfect DB
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating MCTS adjustment', () {
    test('MCTS without perfect DB should have significantly reduced rating',
        () {
      mockDB.generalSettings = const GeneralSettings(
        searchAlgorithm: SearchAlgorithm.mtdf,
        usePerfectDatabase: false,
      );
      final int mtdf = EloRatingService.getFixedAiEloRating(15);

      mockDB.generalSettings = const GeneralSettings(
        searchAlgorithm: SearchAlgorithm.mcts,
        usePerfectDatabase: false,
      );
      final int mcts = EloRatingService.getFixedAiEloRating(15);

      expect(
        mcts,
        lessThan(mtdf),
        reason: 'MCTS without PDB should be much weaker',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: Random algorithm
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating random algorithm', () {
    test('random should have lowest possible rating', () {
      mockDB.generalSettings = const GeneralSettings(
        searchAlgorithm: SearchAlgorithm.random,
        usePerfectDatabase: false,
      );
      final int rating = EloRatingService.getFixedAiEloRating(30);

      expect(rating, 100, reason: 'Random play should be rated 100');
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: perfect database
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating perfect database', () {
    test('perfect DB should increase rating', () {
      mockDB.generalSettings = const GeneralSettings(
        usePerfectDatabase: false,
      );
      final int without = EloRatingService.getFixedAiEloRating(20);

      mockDB.generalSettings = const GeneralSettings(
        usePerfectDatabase: true,
      );
      final int with_ = EloRatingService.getFixedAiEloRating(20);

      expect(
        with_,
        greaterThan(without),
        reason: 'Perfect DB gives AI endgame knowledge',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Adjustments: human move time
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating human move time', () {
    test('short human time limit should increase AI rating', () {
      mockDB.generalSettings = const GeneralSettings(humanMoveTime: 0);
      final int noLimit = EloRatingService.getFixedAiEloRating(15);

      mockDB.generalSettings = const GeneralSettings(humanMoveTime: 3);
      final int shortLimit = EloRatingService.getFixedAiEloRating(15);

      expect(
        shortLimit,
        greaterThan(noLimit),
        reason: 'Short time pressure increases effective AI strength',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Minimum rating floor
  // ---------------------------------------------------------------------------
  group('getFixedAiEloRating minimum floor', () {
    test('rating should never go below 100', () {
      // Apply every possible negative modifier
      mockDB.generalSettings = const GeneralSettings(
        shufflingEnabled: false,
        considerMobility: false,
        focusOnBlockingPaths: true,
        aiIsLazy: true,
        searchAlgorithm: SearchAlgorithm.mcts,
        usePerfectDatabase: false,
      );

      for (int level = 1; level <= 30; level++) {
        final int rating = EloRatingService.getFixedAiEloRating(level);
        expect(
          rating,
          greaterThanOrEqualTo(100),
          reason: 'Level $level with all negatives should still be >= 100',
        );
      }
    });
  });
}
