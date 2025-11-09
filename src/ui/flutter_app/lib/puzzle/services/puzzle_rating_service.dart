// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_rating_service.dart
//
// Service for managing puzzle rating (ELO-based system)

import 'dart:math';

import '../models/puzzle_models.dart';
import '../../shared/services/logger.dart';

/// User's puzzle rating and statistics
class PuzzleRating {
  PuzzleRating({
    required this.rating,
    required this.gamesPlayed,
    required this.provisionalGames,
    required this.ratingDeviation,
  });

  int rating;
  int gamesPlayed;
  int provisionalGames; // First N games are provisional
  double ratingDeviation; // Uncertainty in rating

  bool get isProvisional => gamesPlayed < provisionalGames;
}

/// Result of a puzzle attempt
class PuzzleAttemptResult {
  PuzzleAttemptResult({
    required this.puzzleId,
    required this.success,
    required this.timeSpent,
    required this.hintsUsed,
    required this.movesPlayed,
    required this.timestamp,
    this.oldRating,
    this.newRating,
    this.ratingChange,
  });

  final String puzzleId;
  final bool success;
  final Duration timeSpent;
  final int hintsUsed;
  final int movesPlayed;
  final DateTime timestamp;
  int? oldRating;
  int? newRating;
  int? ratingChange;
}

/// Service for managing puzzle ratings
class PuzzleRatingService {
  factory PuzzleRatingService() => _instance;

  PuzzleRatingService._internal();

  static final PuzzleRatingService _instance = PuzzleRatingService._internal();

  static const String _tag = "[PuzzleRatingService]";

  // Rating constants
  static const int _initialRating = 1500;
  static const int _provisionalGames = 10;
  static const double _initialRD = 350.0; // Initial rating deviation
  static const double _minRD = 50.0; // Minimum rating deviation
  static const double _kFactorProvisional = 40.0;
  static const double _kFactorNormal = 20.0;

  /// Get user's current puzzle rating
  PuzzleRating getUserRating() {
    // TODO: Load from database
    return PuzzleRating(
      rating: _initialRating,
      gamesPlayed: 0,
      provisionalGames: _provisionalGames,
      ratingDeviation: _initialRD,
    );
  }

  /// Update rating based on puzzle result
  PuzzleAttemptResult updateRating({
    required String puzzleId,
    required PuzzleInfo puzzle,
    required bool success,
    required Duration timeSpent,
    required int hintsUsed,
    required int movesPlayed,
  }) {
    final PuzzleRating userRating = getUserRating();
    final int oldRating = userRating.rating;

    // Calculate rating change using modified ELO formula
    final int ratingChange = _calculateRatingChange(
      userRating: userRating,
      puzzleRating: puzzle.rating ?? _initialRating,
      success: success,
      timeSpent: timeSpent,
      hintsUsed: hintsUsed,
    );

    // Update user rating
    userRating.rating += ratingChange;
    userRating.gamesPlayed++;

    // Reduce rating deviation as user plays more
    if (userRating.ratingDeviation > _minRD) {
      userRating.ratingDeviation = max(
        _minRD,
        userRating.ratingDeviation - 5.0,
      );
    }

    _saveUserRating(userRating);

    final PuzzleAttemptResult result = PuzzleAttemptResult(
      puzzleId: puzzleId,
      success: success,
      timeSpent: timeSpent,
      hintsUsed: hintsUsed,
      movesPlayed: movesPlayed,
      timestamp: DateTime.now(),
      oldRating: oldRating,
      newRating: userRating.rating,
      ratingChange: ratingChange,
    );

    _saveAttemptResult(result);

    logger.i("$_tag Rating updated: $oldRating -> ${userRating.rating} (${ratingChange >= 0 ? '+' : ''}$ratingChange)");

    return result;
  }

  /// Calculate rating change using ELO formula with modifiers
  int _calculateRatingChange({
    required PuzzleRating userRating,
    required int puzzleRating,
    required bool success,
    required Duration timeSpent,
    required int hintsUsed,
  }) {
    // K-factor (how much rating can change per game)
    final double kFactor = userRating.isProvisional
        ? _kFactorProvisional
        : _kFactorNormal;

    // Expected score based on rating difference
    final double expectedScore = 1.0 / (1.0 + pow(10.0, (puzzleRating - userRating.rating) / 400.0));

    // Actual score (1 for success, 0 for failure)
    final double actualScore = success ? 1.0 : 0.0;

    // Base rating change
    double ratingChange = kFactor * (actualScore - expectedScore);

    // Time bonus/penalty (faster = more points, slower = less points)
    if (success) {
      // Reward fast solves (under 30 seconds = bonus, over 2 minutes = penalty)
      final int seconds = timeSpent.inSeconds;
      if (seconds < 30) {
        ratingChange *= 1.2; // 20% bonus for very fast solves
      } else if (seconds > 120) {
        ratingChange *= 0.9; // 10% penalty for slow solves
      }
    }

    // Hint penalty (each hint reduces rating gain)
    if (hintsUsed > 0) {
      ratingChange *= pow(0.8, hintsUsed.toDouble()); // -20% per hint
    }

    return ratingChange.round();
  }

  /// Get recommended puzzles based on user rating
  List<PuzzleInfo> getRecommendedPuzzles(
    List<PuzzleInfo> allPuzzles, {
    int count = 10,
  }) {
    final PuzzleRating userRating = getUserRating();
    final int targetRating = userRating.rating;
    final double rd = userRating.ratingDeviation;

    // Calculate acceptable rating range (within 2 RD)
    final int minRating = (targetRating - 2 * rd).round();
    final int maxRating = (targetRating + 2 * rd).round();

    // Filter puzzles within rating range
    final List<PuzzleInfo> suitable = allPuzzles.where((PuzzleInfo puzzle) {
      final int puzzleRating = puzzle.rating ?? _initialRating;
      return puzzleRating >= minRating && puzzleRating <= maxRating;
    }).toList();

    // Shuffle and take requested count
    suitable.shuffle();
    return suitable.take(count).toList();
  }

  /// Get puzzle attempt history
  List<PuzzleAttemptResult> getAttemptHistory({int limit = 50}) {
    // TODO: Load from database
    return <PuzzleAttemptResult>[];
  }

  /// Get rating history over time
  List<MapEntry<DateTime, int>> getRatingHistory() {
    // TODO: Load from database
    return <MapEntry<DateTime, int>>[];
  }

  /// Calculate various statistics
  Map<String, dynamic> getStatistics() {
    final PuzzleRating rating = getUserRating();
    final List<PuzzleAttemptResult> history = getAttemptHistory();

    final int totalAttempts = history.length;
    final int successCount = history.where((PuzzleAttemptResult r) => r.success).length;
    final double successRate = totalAttempts > 0 ? (successCount / totalAttempts) * 100 : 0.0;

    // Calculate average solve time (successful puzzles only)
    final List<PuzzleAttemptResult> successful = history.where((PuzzleAttemptResult r) => r.success).toList();
    final Duration avgTime = successful.isEmpty
        ? Duration.zero
        : Duration(
            seconds: successful
                    .map((PuzzleAttemptResult r) => r.timeSpent.inSeconds)
                    .reduce((int a, int b) => a + b) ~/
                successful.length,
          );

    return <String, dynamic>{
      'rating': rating.rating,
      'gamesPlayed': rating.gamesPlayed,
      'isProvisional': rating.isProvisional,
      'totalAttempts': totalAttempts,
      'successCount': successCount,
      'failCount': totalAttempts - successCount,
      'successRate': successRate,
      'averageTime': avgTime.inSeconds,
    };
  }

  /// Save user rating
  void _saveUserRating(PuzzleRating rating) {
    // TODO: Save to database
    logger.i("$_tag Saved user rating: ${rating.rating}");
  }

  /// Save attempt result
  void _saveAttemptResult(PuzzleAttemptResult result) {
    // TODO: Save to database
    logger.i("$_tag Saved attempt result: ${result.puzzleId}");
  }
}
