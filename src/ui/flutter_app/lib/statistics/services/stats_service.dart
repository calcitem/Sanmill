// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// stats_service.dart

import '../../../game_page/services/mill.dart';
import '../../shared/database/database.dart';
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
    switch (level) {
      case 1:
        return 300; // Complete beginner level, often misses captures
      case 2:
        return 500; // Can see some simple tactics, but makes many mistakes
      case 3:
        return 600; // Has some awareness, still at beginner stage
      case 4:
        return 700; // Basic capture awareness, occasionally sees 1-2 move traps
      case 5:
        return 800; // Serious beginners can beat this level consistently
      case 6:
        return 900; // Requires basic opening principles to beat
      case 7:
        return 1000; // Has basic positional understanding and simple midgame tactics
      case 8:
        return 1100; // Can identify basic threats but lacks comprehensive planning
      case 9:
        return 1200; // Amateur common level with some tactical patterns
      case 10:
        return 1300; // Average hobbyist level
      case 11:
        return 1400; // Some understanding of common openings, with attack/defense ideas
      case 12:
        return 1500; // Club/school team level with some practical experience
      case 13:
        return 1600; // Improved middle and endgame ability with fewer mistakes
      case 14:
        return 1700; // "Experienced" amateur level with planning awareness
      case 15:
        return 1800; // Amateur plateau level that's difficult to surpass
      case 16:
        return 1900; // Requires systematic opening/endgame knowledge and stronger tactics
      case 17:
        return 2000; // Semi-professional level with deeper study and lower error rate
      case 18:
        return 2100; // High-level amateur or low-level professional
      case 19:
        return 2200; // Top amateur or national master level
      case 20:
        return 2300; // Entry international master level
      case 21:
        return 2350; // Lower international master level
      case 22:
        return 2400; // Average international master
      case 23:
        return 2450; // Upper IM or entry GM level
      case 24:
        return 2500; // Stable GM threshold with comprehensive skills
      case 25:
        return 2550; // Mid-level GM with competitive international performance
      case 26:
        return 2600; // High-level GM competing for titles in international tournaments
      case 27:
        return 2650; // Top-ranked GM with championship potential
      case 28:
        return 2700; // Elite GM, "2700 club" threshold
      case 29:
        return 2750; // World-class GM capable of competing with world champions
      case 30:
        return 2800; // Near world champion level
      default:
        return 1400; // Default to level 11 for any unspecified levels
    }
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
