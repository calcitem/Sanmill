// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// stats_settings_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/statistics/model/stats_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PlayerStats
  // ---------------------------------------------------------------------------
  group('PlayerStats', () {
    group('constructor defaults', () {
      test('should have sensible default values', () {
        const PlayerStats stats = PlayerStats();

        expect(stats.rating, 1400);
        expect(stats.gamesPlayed, 0);
        expect(stats.wins, 0);
        expect(stats.losses, 0);
        expect(stats.draws, 0);
        expect(stats.lastUpdated, isNull);
        expect(stats.whiteGamesPlayed, 0);
        expect(stats.whiteWins, 0);
        expect(stats.whiteLosses, 0);
        expect(stats.whiteDraws, 0);
        expect(stats.blackGamesPlayed, 0);
        expect(stats.blackWins, 0);
        expect(stats.blackLosses, 0);
        expect(stats.blackDraws, 0);
        expect(stats.consecutiveLossesAtLevel1NonMcts, 0);
      });
    });

    group('fromJson / toJson round-trip', () {
      test('should survive a full round-trip with all fields populated', () {
        final DateTime now = DateTime(2026, 2, 14, 12, 0, 0);
        final PlayerStats original = PlayerStats(
          rating: 1800,
          gamesPlayed: 50,
          wins: 20,
          losses: 15,
          draws: 15,
          lastUpdated: now,
          whiteGamesPlayed: 25,
          whiteWins: 12,
          whiteLosses: 7,
          whiteDraws: 6,
          blackGamesPlayed: 25,
          blackWins: 8,
          blackLosses: 8,
          blackDraws: 9,
          consecutiveLossesAtLevel1NonMcts: 3,
        );

        final Map<String, dynamic> json = original.toJson();
        final PlayerStats restored = PlayerStats.fromJson(json);

        expect(restored.rating, original.rating);
        expect(restored.gamesPlayed, original.gamesPlayed);
        expect(restored.wins, original.wins);
        expect(restored.losses, original.losses);
        expect(restored.draws, original.draws);
        expect(
          restored.lastUpdated?.millisecondsSinceEpoch,
          original.lastUpdated?.millisecondsSinceEpoch,
        );
        expect(restored.whiteGamesPlayed, original.whiteGamesPlayed);
        expect(restored.whiteWins, original.whiteWins);
        expect(restored.whiteLosses, original.whiteLosses);
        expect(restored.whiteDraws, original.whiteDraws);
        expect(restored.blackGamesPlayed, original.blackGamesPlayed);
        expect(restored.blackWins, original.blackWins);
        expect(restored.blackLosses, original.blackLosses);
        expect(restored.blackDraws, original.blackDraws);
        expect(
          restored.consecutiveLossesAtLevel1NonMcts,
          original.consecutiveLossesAtLevel1NonMcts,
        );
      });

      test('should handle null lastUpdated', () {
        const PlayerStats original = PlayerStats();
        final Map<String, dynamic> json = original.toJson();
        final PlayerStats restored = PlayerStats.fromJson(json);

        expect(restored.lastUpdated, isNull);
      });

      test('should use defaults for missing JSON keys', () {
        final PlayerStats restored = PlayerStats.fromJson(
          const <String, dynamic>{},
        );

        expect(restored.rating, 1400);
        expect(restored.gamesPlayed, 0);
        expect(restored.wins, 0);
        expect(restored.losses, 0);
        expect(restored.draws, 0);
        expect(restored.consecutiveLossesAtLevel1NonMcts, 0);
      });
    });

    group('copyWith', () {
      test('should copy with no changes when no arguments are given', () {
        const PlayerStats original = PlayerStats(
          rating: 2000,
          gamesPlayed: 100,
          wins: 50,
        );
        final PlayerStats copy = original.copyWith();

        expect(copy.rating, original.rating);
        expect(copy.gamesPlayed, original.gamesPlayed);
        expect(copy.wins, original.wins);
      });

      test('should override only the specified fields', () {
        const PlayerStats original = PlayerStats(
          rating: 1500,
          gamesPlayed: 10,
          wins: 5,
          losses: 3,
          draws: 2,
        );

        final PlayerStats updated = original.copyWith(
          rating: 1600,
          wins: 6,
        );

        expect(updated.rating, 1600);
        expect(updated.wins, 6);
        // Unchanged fields
        expect(updated.gamesPlayed, 10);
        expect(updated.losses, 3);
        expect(updated.draws, 2);
      });

      test('should allow updating color-specific stats independently', () {
        const PlayerStats original = PlayerStats();
        final PlayerStats updated = original.copyWith(
          whiteGamesPlayed: 10,
          whiteWins: 7,
          blackGamesPlayed: 5,
          blackLosses: 2,
        );

        expect(updated.whiteGamesPlayed, 10);
        expect(updated.whiteWins, 7);
        expect(updated.blackGamesPlayed, 5);
        expect(updated.blackLosses, 2);
        // Unchanged color stats
        expect(updated.whiteLosses, 0);
        expect(updated.whiteDraws, 0);
        expect(updated.blackWins, 0);
        expect(updated.blackDraws, 0);
      });

      test('should allow updating consecutiveLossesAtLevel1NonMcts', () {
        const PlayerStats original = PlayerStats();
        final PlayerStats updated = original.copyWith(
          consecutiveLossesAtLevel1NonMcts: 5,
        );

        expect(updated.consecutiveLossesAtLevel1NonMcts, 5);
      });
    });

    group('toJson field mapping', () {
      test('should include all fields in JSON output', () {
        final DateTime now = DateTime(2026, 1, 1);
        final PlayerStats stats = PlayerStats(
          rating: 1500,
          gamesPlayed: 10,
          wins: 5,
          losses: 3,
          draws: 2,
          lastUpdated: now,
          whiteGamesPlayed: 5,
          whiteWins: 3,
          whiteLosses: 1,
          whiteDraws: 1,
          blackGamesPlayed: 5,
          blackWins: 2,
          blackLosses: 2,
          blackDraws: 1,
          consecutiveLossesAtLevel1NonMcts: 1,
        );

        final Map<String, dynamic> json = stats.toJson();

        expect(json.containsKey('rating'), isTrue);
        expect(json.containsKey('gamesPlayed'), isTrue);
        expect(json.containsKey('wins'), isTrue);
        expect(json.containsKey('losses'), isTrue);
        expect(json.containsKey('draws'), isTrue);
        expect(json.containsKey('lastUpdated'), isTrue);
        expect(json.containsKey('whiteGamesPlayed'), isTrue);
        expect(json.containsKey('whiteWins'), isTrue);
        expect(json.containsKey('whiteLosses'), isTrue);
        expect(json.containsKey('whiteDraws'), isTrue);
        expect(json.containsKey('blackGamesPlayed'), isTrue);
        expect(json.containsKey('blackWins'), isTrue);
        expect(json.containsKey('blackLosses'), isTrue);
        expect(json.containsKey('blackDraws'), isTrue);
        expect(json.containsKey('consecutiveLossesAtLevel1NonMcts'), isTrue);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // StatsSettings
  // ---------------------------------------------------------------------------
  group('StatsSettings', () {
    group('constructor defaults', () {
      test('should have sensible default values', () {
        const StatsSettings settings = StatsSettings();

        expect(settings.isStatsEnabled, isTrue);
        expect(settings.humanStats.rating, 1400);
        expect(settings.aiDifficultyStatsMap, isEmpty);
        expect(settings.shouldSuggestMctsSwitch, isFalse);
        expect(settings.shouldSuggestMtdfSwitch, isFalse);
      });
    });

    group('fromJson / toJson round-trip', () {
      test('should survive a full round-trip', () {
        final StatsSettings original = StatsSettings(
          isStatsEnabled: true,
          humanStats: const PlayerStats(rating: 1800, gamesPlayed: 42),
          aiDifficultyStatsMap: <int, PlayerStats>{
            1: const PlayerStats(rating: 300, gamesPlayed: 10, wins: 7),
            15: const PlayerStats(rating: 1900, gamesPlayed: 5),
          },
          shouldSuggestMctsSwitch: true,
          shouldSuggestMtdfSwitch: false,
        );

        final Map<String, dynamic> json = original.toJson();
        final StatsSettings restored = StatsSettings.fromJson(json);

        expect(restored.isStatsEnabled, original.isStatsEnabled);
        expect(restored.humanStats.rating, original.humanStats.rating);
        expect(
          restored.humanStats.gamesPlayed,
          original.humanStats.gamesPlayed,
        );
        expect(
          restored.shouldSuggestMctsSwitch,
          original.shouldSuggestMctsSwitch,
        );
        expect(
          restored.shouldSuggestMtdfSwitch,
          original.shouldSuggestMtdfSwitch,
        );
        expect(restored.aiDifficultyStatsMap.length, 2);
        expect(restored.aiDifficultyStatsMap[1]?.rating, 300);
        expect(restored.aiDifficultyStatsMap[1]?.wins, 7);
        expect(restored.aiDifficultyStatsMap[15]?.rating, 1900);
      });

      test('should handle empty JSON gracefully', () {
        final StatsSettings restored = StatsSettings.fromJson(
          const <String, dynamic>{},
        );

        expect(restored.isStatsEnabled, isTrue);
        expect(restored.humanStats.rating, 1400);
        expect(restored.aiDifficultyStatsMap, isEmpty);
      });
    });

    group('getAiDifficultyStats', () {
      test('should return stored stats for existing level', () {
        const StatsSettings settings = StatsSettings(
          aiDifficultyStatsMap: <int, PlayerStats>{
            5: PlayerStats(rating: 800, gamesPlayed: 20),
          },
        );

        final PlayerStats stats = settings.getAiDifficultyStats(5);
        expect(stats.rating, 800);
        expect(stats.gamesPlayed, 20);
      });

      test('should return default PlayerStats for non-existing level', () {
        const StatsSettings settings = StatsSettings();

        final PlayerStats stats = settings.getAiDifficultyStats(99);
        expect(stats.rating, 1400);
        expect(stats.gamesPlayed, 0);
      });
    });

    group('updateAiDifficultyStats', () {
      test('should add new level stats', () {
        const StatsSettings settings = StatsSettings();
        const PlayerStats newStats = PlayerStats(
          rating: 500,
          gamesPlayed: 3,
        );

        final StatsSettings updated = settings.updateAiDifficultyStats(
          2,
          newStats,
        );

        expect(updated.aiDifficultyStatsMap[2]?.rating, 500);
        expect(updated.aiDifficultyStatsMap[2]?.gamesPlayed, 3);
      });

      test('should overwrite existing level stats', () {
        const StatsSettings settings = StatsSettings(
          aiDifficultyStatsMap: <int, PlayerStats>{
            2: PlayerStats(rating: 500, gamesPlayed: 3),
          },
        );

        const PlayerStats newStats = PlayerStats(
          rating: 600,
          gamesPlayed: 10,
        );
        final StatsSettings updated = settings.updateAiDifficultyStats(
          2,
          newStats,
        );

        expect(updated.aiDifficultyStatsMap[2]?.rating, 600);
        expect(updated.aiDifficultyStatsMap[2]?.gamesPlayed, 10);
      });

      test('should not modify existing levels when adding a new one', () {
        const StatsSettings settings = StatsSettings(
          aiDifficultyStatsMap: <int, PlayerStats>{
            1: PlayerStats(rating: 300),
          },
        );

        final StatsSettings updated = settings.updateAiDifficultyStats(
          2,
          const PlayerStats(rating: 500),
        );

        expect(updated.aiDifficultyStatsMap[1]?.rating, 300);
        expect(updated.aiDifficultyStatsMap[2]?.rating, 500);
        expect(updated.aiDifficultyStatsMap.length, 2);
      });
    });

    group('copyWith', () {
      test('should copy with no changes when no arguments are given', () {
        const StatsSettings original = StatsSettings(
          isStatsEnabled: false,
          shouldSuggestMctsSwitch: true,
        );

        final StatsSettings copy = original.copyWith();

        expect(copy.isStatsEnabled, original.isStatsEnabled);
        expect(
          copy.shouldSuggestMctsSwitch,
          original.shouldSuggestMctsSwitch,
        );
      });

      test('should override only specified fields', () {
        const StatsSettings original = StatsSettings();
        final StatsSettings updated = original.copyWith(
          isStatsEnabled: false,
          shouldSuggestMtdfSwitch: true,
        );

        expect(updated.isStatsEnabled, isFalse);
        expect(updated.shouldSuggestMtdfSwitch, isTrue);
        // Unchanged
        expect(updated.shouldSuggestMctsSwitch, isFalse);
        expect(updated.humanStats.rating, 1400);
      });

      test('should allow replacing humanStats', () {
        const StatsSettings original = StatsSettings();
        final StatsSettings updated = original.copyWith(
          humanStats: const PlayerStats(rating: 2200),
        );

        expect(updated.humanStats.rating, 2200);
      });
    });
  });
}
