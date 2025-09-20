// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// stats_service.dart

import '../../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../statistics/model/stats_settings.dart';

part 'elo_rating_calculation.dart';

/// Game outcome from the human player's perspective
enum HumanOutcome {
  playerWin, // Human player wins
  opponentWin, // Opponent (AI or LAN) wins
  draw, // Game ends in a draw
}

/// Service class for managing ELO ratings
class EloRatingService {
  // Singleton instance
  factory EloRatingService() => _instance;
  EloRatingService._();
  static const String _logTag = "[EloService]";
  static final EloRatingService _instance = EloRatingService._();

  /// Fixed AI Elo ratings based on difficulty level
  static int getFixedAiEloRating(int level) {
    const List<int> baseRatings = <int>[
      300, // Level 1: Complete beginner, often misses captures
      500, // Level 2: Sees simple tactics but makes many mistakes
      600, // Level 3: Some awareness, still beginner stage
      700, // Level 4: Basic capture awareness, occasional traps
      800, // Level 5: Serious beginners can beat this level consistently
      900, // Level 6: Requires basic opening principles to beat
      1000, // Level 7: Basic positional understanding and simple tactics
      1100, // Level 8: Identifies threats but lacks comprehensive planning
      1200, // Level 9: Amateur level with tactical patterns
      1300, // Level 10: Average hobbyist level
      1400, // Level 11: Some opening understanding and planning
      1500, // Level 12: Club/school team level with experience
      1600, // Level 13: Improved middle and endgame ability
      1700, // Level 14: Experienced amateur with planning awareness
      1800, // Level 15: Amateur plateau level
      1900, // Level 16: Requires systematic knowledge and strong tactics
      2000, // Level 17: Semi-professional with deeper study
      2100, // Level 18: High-level amateur or low-level professional
      2200, // Level 19: Top amateur or national master
      2300, // Level 20: Entry international master level
      2350, // Level 21: Lower international master level
      2400, // Level 22: Average international master
      2450, // Level 23: Upper IM or entry GM level
      2500, // Level 24: Stable GM threshold
      2550, // Level 25: Mid-level GM with international performance
      2600, // Level 26: High-level GM competing for titles
      2650, // Level 27: Top-ranked GM with championship potential
      2700, // Level 28: Elite GM, "2700 club"
      2750, // Level 29: World-class GM competitive with champions
      2800, // Level 30: Near world champion level
    ];

    final bool levelInRange = level >= 1 && level <= baseRatings.length;
    int ret = levelInRange ? baseRatings[level - 1] : 1400;

    // Adjust rating based on game rules and settings

    // Nine Men's Morris with AI moving first
    if (DB().ruleSettings.isLikelyNineMensMorris() &&
        DB().generalSettings.aiMovesFirst) {
      ret -= 100; // Decrease AI rating as it has advantage
    }

    // Twelve Men's Morris with AI moving first
    if (DB().ruleSettings.isLikelyTwelveMensMorris() &&
        DB().generalSettings.aiMovesFirst) {
      ret += 200; // Increase AI rating as game is more complex
    }

    // Move time adjustments for higher skill levels
    if (DB().generalSettings.moveTime != 1 &&
        DB().generalSettings.skillLevel >= 15) {
      final int moveTime = DB().generalSettings.moveTime;
      if (moveTime == 0) {
        ret += 100; // Instant moves
      } else if (moveTime >= 2 && moveTime <= 5) {
        ret += 25; // Short thinking time
      } else if (moveTime >= 6 && moveTime <= 10) {
        ret += 50; // Medium thinking time
      } else if (moveTime >= 10 && moveTime <= 60) {
        ret += 75; // Longer thinking time
      }
    }

    // Shuffling disabled
    if (!DB().generalSettings.shufflingEnabled) {
      ret -= 100; // Decrease rating as AI becomes more predictable
    }

    // Mobility consideration disabled
    if (!DB().generalSettings.considerMobility) {
      ret -= 50; // Decrease rating as AI ignores mobility advantage
    }

    // Focus on blocking paths enabled
    if (DB().generalSettings.focusOnBlockingPaths) {
      ret -= 100; // Decrease rating as AI focuses on less optimal strategy
    }

    // Perfect database enabled
    if (DB().generalSettings.usePerfectDatabase) {
      ret +=
          100; // Increase rating as AI has access to perfect endgame knowledge
    }

    // Human move time adjustments
    if (DB().generalSettings.humanMoveTime != 0) {
      final int humanMoveTime = DB().generalSettings.humanMoveTime;
      if (humanMoveTime >= 1 && humanMoveTime <= 5) {
        ret += 100; // Human has very limited time
      } else if (humanMoveTime >= 6 && humanMoveTime <= 10) {
        ret += 50; // Human has limited time
      } else if (humanMoveTime >= 11 && humanMoveTime <= 30) {
        ret += 20; // Human has moderate time
      } else if (humanMoveTime >= 31 && humanMoveTime <= 60) {
        ret += 10; // Human has sufficient time
      }
    }

    // AI is lazy mode
    if (DB().generalSettings.aiIsLazy) {
      ret = ret ~/ 2; // Halve the rating as AI deliberately plays suboptimally
    }

    // MCTS algorithm with no perfect database
    if (DB().generalSettings.searchAlgorithm == SearchAlgorithm.mcts &&
        !DB().generalSettings.usePerfectDatabase) {
      ret = (ret * 0.2)
          .round(); // Significant reduction for MCTS without perfect DB
    }

    // Random algorithm with no perfect database
    if (DB().generalSettings.searchAlgorithm == SearchAlgorithm.random &&
        !DB().generalSettings.usePerfectDatabase) {
      ret = 100; // Lowest possible rating for random play
    }

    // Ensure rating is at least 100
    if (ret < 100) {
      ret = 100;
    }

    return ret;
  }

  // Returns a Stats object for the given AI level with appropriate statistics
  PlayerStats getAiDifficultyStats(int level) {
    // Get the stored AI rating to preserve game statistics
    final StatsSettings settings = DB().statsSettings;
    final PlayerStats aiDifficultyStats = settings.getAiDifficultyStats(level);

    // Create a new rating object with the fixed rating but preserving statistics
    return PlayerStats(
      rating: getFixedAiEloRating(level),
      gamesPlayed: aiDifficultyStats.gamesPlayed,
      wins: aiDifficultyStats.wins,
      losses: aiDifficultyStats.losses,
      draws: aiDifficultyStats.draws,
      lastUpdated: aiDifficultyStats.lastUpdated,
      whiteGamesPlayed: aiDifficultyStats.whiteGamesPlayed,
      whiteWins: aiDifficultyStats.whiteWins,
      whiteLosses: aiDifficultyStats.whiteLosses,
      whiteDraws: aiDifficultyStats.whiteDraws,
      blackGamesPlayed: aiDifficultyStats.blackGamesPlayed,
      blackWins: aiDifficultyStats.blackWins,
      blackLosses: aiDifficultyStats.blackLosses,
      blackDraws: aiDifficultyStats.blackDraws,
    );
  }

  /// Updates player stats based on game outcome
  void updateStats(PieceColor winnerColor, GameMode gameMode) {
    try {
      final StatsSettings settings = DB().statsSettings;

      // If stats are disabled, don't update
      if (!settings.isStatsEnabled) {
        logger.i("$_logTag Stats disabled, not updating");
        return;
      }

      if (!EnvironmentConfig.devMode && GameController().disableStats == true) {
        logger.i(
            "$_logTag Stats disabled because of taking-back etc., not updating");
        return;
      }

      switch (gameMode) {
        case GameMode.humanVsAi:
          _updateHumanVsAiStats(winnerColor, settings);
          break;
        case GameMode.humanVsHuman:
          // No update needed for local human vs human games
          logger.i("$_logTag Human vs Human game, not updating stats");
          break;
        case GameMode.humanVsLAN:
          // LAN games don't update stats
          logger.i("$_logTag Human vs LAN game, not updating stats");
          break;
        case GameMode.humanVsCloud:
          // Currently treated same as Human vs AI (could be updated later)
          _updateHumanVsAiStats(winnerColor, settings);
          break;
        case GameMode.aiVsAi:
          // AI vs AI ratings not tracked
          logger.i("$_logTag AI vs AI game, not updating stats");
          break;
        case GameMode.setupPosition:
          // Setup position mode ratings not tracked
          logger.i("$_logTag Setup position mode, not updating stats");
          break;
        case GameMode.testViaLAN:
          // LAN games don't update stats
          logger.i("$_logTag Test via LAN game, not updating stats");
          break;
      }
    } catch (e) {
      logger.e("$_logTag Error updating stats: $e");
    }
  }

  /// Updates stats for Human vs AI games
  void _updateHumanVsAiStats(PieceColor winnerColor, StatsSettings settings) {
    // Get AI difficulty level
    final int aiDifficulty = DB().generalSettings.skillLevel;

    // Get current stats
    final PlayerStats humanStats = settings.humanStats;

    // Get AI rating using the fixed rating table
    final PlayerStats aiDifficultyStats = getAiDifficultyStats(aiDifficulty);

    // Determine if AI plays as white
    final bool isAiWhite = DB().generalSettings.aiMovesFirst;

    // Determine game outcome
    HumanOutcome outcome;
    if (winnerColor == PieceColor.draw || winnerColor == PieceColor.none) {
      outcome = HumanOutcome.draw;
    } else if ((winnerColor == PieceColor.white && !isAiWhite) ||
        (winnerColor == PieceColor.black && isAiWhite)) {
      // Human won
      outcome = HumanOutcome.playerWin;
    } else {
      // AI won
      outcome = HumanOutcome.opponentWin;
    }

    // Convert outcome to score (1.0 for win, 0.5 for draw, 0.0 for loss)
    double score;
    switch (outcome) {
      case HumanOutcome.playerWin:
        score = 1.0;
        break;
      case HumanOutcome.opponentWin:
        score = 0.0;
        break;
      case HumanOutcome.draw:
        score = 0.5;
        break;
    }

    // Prepare ratings list and results list for this single game
    final List<int> aiRatingsList = <int>[aiDifficultyStats.rating];
    final List<double> resultsList = <double>[score];

    // Determine new rating using relaxed rules for <5 total games
    final int gamesAfterThis = humanStats.gamesPlayed + 1;
    int newHumanRating;

    // IMPORTANT NOTE (CUSTOMIZATION):
    // Official FIDE rules require 5+ rated games total before publishing
    // a formal rating, and to ignore a 0-score first event, etc.
    // Here we allow an immediate rating for <5 games with bounding logic.
    if (gamesAfterThis < 5) {
      // Provisional rating with custom bounds
      newHumanRating = _calculateInitialRating(aiRatingsList, resultsList);
    } else {
      // Standard update once the player has 5 or more games
      newHumanRating = _updateRating(
        humanStats.rating,
        aiRatingsList,
        resultsList,
        gamesAfterThis,
      );
    }

    // For AI, we don't update the actual rating (it's fixed by level),
    // but do update their statistics

    // Update human color-specific stats
    int humanWhiteGamesPlayed = humanStats.whiteGamesPlayed;
    int humanWhiteWins = humanStats.whiteWins;
    int humanWhiteLosses = humanStats.whiteLosses;
    int humanWhiteDraws = humanStats.whiteDraws;
    int humanBlackGamesPlayed = humanStats.blackGamesPlayed;
    int humanBlackWins = humanStats.blackWins;
    int humanBlackLosses = humanStats.blackLosses;
    int humanBlackDraws = humanStats.blackDraws;

    // AI color-specific stats
    int aiWhiteGamesPlayed = aiDifficultyStats.whiteGamesPlayed;
    int aiWhiteWins = aiDifficultyStats.whiteWins;
    int aiWhiteLosses = aiDifficultyStats.whiteLosses;
    int aiWhiteDraws = aiDifficultyStats.whiteDraws;
    int aiBlackGamesPlayed = aiDifficultyStats.blackGamesPlayed;
    int aiBlackWins = aiDifficultyStats.blackWins;
    int aiBlackLosses = aiDifficultyStats.blackLosses;
    int aiBlackDraws = aiDifficultyStats.blackDraws;

    // Update color-specific stats based on who played which color
    if (isAiWhite) {
      // AI played as white, human played as black
      aiWhiteGamesPlayed++;
      humanBlackGamesPlayed++;

      if (outcome == HumanOutcome.playerWin) {
        // Human won
        aiWhiteLosses++;
        humanBlackWins++;
      } else if (outcome == HumanOutcome.opponentWin) {
        // AI won
        aiWhiteWins++;
        humanBlackLosses++;
      } else {
        // Draw
        aiWhiteDraws++;
        humanBlackDraws++;
      }
    } else {
      // Human played as white, AI played as black
      humanWhiteGamesPlayed++;
      aiBlackGamesPlayed++;

      if (outcome == HumanOutcome.playerWin) {
        // Human won
        humanWhiteWins++;
        aiBlackLosses++;
      } else if (outcome == HumanOutcome.opponentWin) {
        // AI won
        humanWhiteLosses++;
        aiBlackWins++;
      } else {
        // Draw
        humanWhiteDraws++;
        aiBlackDraws++;
      }
    }

    // Update human rating and stats
    final PlayerStats newHumanStatsObject = humanStats.copyWith(
      rating: newHumanRating,
      gamesPlayed: humanStats.gamesPlayed + 1,
      wins: outcome == HumanOutcome.playerWin
          ? humanStats.wins + 1
          : humanStats.wins,
      losses: outcome == HumanOutcome.opponentWin
          ? humanStats.losses + 1
          : humanStats.losses,
      draws: outcome == HumanOutcome.draw
          ? humanStats.draws + 1
          : humanStats.draws,
      lastUpdated: DateTime.now(),
      whiteGamesPlayed: humanWhiteGamesPlayed,
      whiteWins: humanWhiteWins,
      whiteLosses: humanWhiteLosses,
      whiteDraws: humanWhiteDraws,
      blackGamesPlayed: humanBlackGamesPlayed,
      blackWins: humanBlackWins,
      blackLosses: humanBlackLosses,
      blackDraws: humanBlackDraws,
    );

    // Update AI statistics (rating remains fixed)
    final PlayerStats newAiDifficultyStatsObject =
        settings.getAiDifficultyStats(aiDifficulty).copyWith(
              // Keep the original rating from the settings, as we don't update AI ratings
              gamesPlayed: aiDifficultyStats.gamesPlayed + 1,
              wins: outcome == HumanOutcome.opponentWin
                  ? aiDifficultyStats.wins + 1
                  : aiDifficultyStats.wins,
              losses: outcome == HumanOutcome.playerWin
                  ? aiDifficultyStats.losses + 1
                  : aiDifficultyStats.losses,
              draws: outcome == HumanOutcome.draw
                  ? aiDifficultyStats.draws + 1
                  : aiDifficultyStats.draws,
              lastUpdated: DateTime.now(),
              whiteGamesPlayed: aiWhiteGamesPlayed,
              whiteWins: aiWhiteWins,
              whiteLosses: aiWhiteLosses,
              whiteDraws: aiWhiteDraws,
              blackGamesPlayed: aiBlackGamesPlayed,
              blackWins: aiBlackWins,
              blackLosses: aiBlackLosses,
              blackDraws: aiBlackDraws,
            );

    // Save updated ratings
    final StatsSettings newSettings = settings.copyWith(
      humanStats: newHumanStatsObject,
    );

    // Update AI stats in the settings
    DB().statsSettings = newSettings.updateAiDifficultyStats(
        aiDifficulty, newAiDifficultyStatsObject);

    logger.i(
        "$_logTag Updated Human rating: ${humanStats.rating} -> $newHumanRating");
    logger.i(
        "$_logTag AI Level $aiDifficulty rating: ${aiDifficultyStats.rating} (fixed)");
  }
}
