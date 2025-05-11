// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// elo_rating_calculation.dart

part of 'stats_service.dart';

/// Official FIDE tables (8.1.1 & 8.1.2) for dp and expected score.
/// We keep them unmodified, but note we do cap rating differences at ±400.
/// Table 8.1.1: p → dp lookup table
final Map<double, int> _table_8_1_1 = <double, int>{
  1.00: 800,
  0.83: 273,
  0.66: 117,
  0.49: -7,
  0.32: -133,
  0.15: -296,
  0.99: 677,
  0.82: 262,
  0.65: 110,
  0.48: -14,
  0.31: -141,
  0.14: -309,
  0.98: 589,
  0.81: 251,
  0.64: 102,
  0.47: -21,
  0.30: -149,
  0.13: -322,
  0.97: 538,
  0.80: 240,
  0.63: 95,
  0.46: -29,
  0.29: -158,
  0.12: -336,
  0.96: 501,
  0.79: 230,
  0.62: 87,
  0.45: -36,
  0.28: -166,
  0.11: -351,
  0.95: 470,
  0.78: 220,
  0.61: 80,
  0.44: -43,
  0.27: -175,
  0.10: -366,
  0.94: 444,
  0.77: 211,
  0.60: 72,
  0.43: -50,
  0.26: -184,
  0.09: -383,
  0.93: 422,
  0.76: 202,
  0.59: 65,
  0.42: -57,
  0.25: -193,
  0.08: -401,
  0.92: 401,
  0.75: 193,
  0.58: 57,
  0.41: -65,
  0.24: -202,
  0.07: -422,
  0.91: 383,
  0.74: 184,
  0.57: 50,
  0.40: -72,
  0.23: -211,
  0.06: -444,
  0.90: 366,
  0.73: 175,
  0.56: 43,
  0.39: -80,
  0.22: -220,
  0.05: -470,
  0.89: 351,
  0.72: 166,
  0.55: 36,
  0.38: -87,
  0.21: -230,
  0.04: -501,
  0.88: 336,
  0.71: 158,
  0.54: 29,
  0.37: -95,
  0.20: -240,
  0.03: -538,
  0.87: 322,
  0.70: 149,
  0.53: 21,
  0.36: -102,
  0.19: -251,
  0.02: -589,
  0.86: 309,
  0.69: 141,
  0.52: 14,
  0.35: -110,
  0.18: -262,
  0.01: -677,
  0.85: 296,
  0.68: 133,
  0.51: 7,
  0.34: -117,
  0.17: -273,
  0.00: -800,
  0.84: 284,
  0.67: 125,
  0.50: 0,
  0.33: -125,
  0.16: -284,
};

/// Table 8.1.2: Rating difference → Expected score (PD) lookup data
/// Format: [min_diff, max_diff, higher_rating_expectation, lower_rating_expectation]
final List<List<num>> _table_8_1_2 = <List<num>>[
  <num>[0, 3, 0.50, 0.50],
  <num>[92, 98, 0.63, 0.37],
  <num>[198, 206, 0.76, 0.24],
  <num>[345, 357, 0.89, 0.11],
  <num>[4, 10, 0.51, 0.49],
  <num>[99, 106, 0.64, 0.36],
  <num>[207, 215, 0.77, 0.23],
  <num>[358, 374, 0.90, 0.10],
  <num>[11, 17, 0.52, 0.48],
  <num>[107, 113, 0.65, 0.35],
  <num>[216, 225, 0.78, 0.22],
  <num>[375, 391, 0.91, 0.09],
  <num>[18, 25, 0.53, 0.47],
  <num>[114, 121, 0.66, 0.34],
  <num>[226, 235, 0.79, 0.21],
  <num>[392, 411, 0.92, 0.08],
  <num>[26, 32, 0.54, 0.46],
  <num>[122, 129, 0.67, 0.33],
  <num>[236, 245, 0.80, 0.20],
  <num>[412, 432, 0.93, 0.07],
  <num>[33, 39, 0.55, 0.45],
  <num>[130, 137, 0.68, 0.32],
  <num>[246, 256, 0.81, 0.19],
  <num>[433, 456, 0.94, 0.06],
  <num>[40, 46, 0.56, 0.44],
  <num>[138, 145, 0.69, 0.31],
  <num>[257, 267, 0.82, 0.18],
  <num>[457, 484, 0.95, 0.05],
  <num>[47, 53, 0.57, 0.43],
  <num>[146, 153, 0.70, 0.30],
  <num>[268, 278, 0.83, 0.17],
  <num>[485, 517, 0.96, 0.04],
  <num>[54, 61, 0.58, 0.42],
  <num>[154, 162, 0.71, 0.29],
  <num>[279, 290, 0.84, 0.16],
  <num>[518, 559, 0.97, 0.03],
  <num>[62, 68, 0.59, 0.41],
  <num>[163, 170, 0.72, 0.28],
  <num>[291, 302, 0.85, 0.15],
  <num>[560, 619, 0.98, 0.02],
  <num>[69, 76, 0.60, 0.40],
  <num>[171, 179, 0.73, 0.27],
  <num>[303, 315, 0.86, 0.14],
  <num>[620, 735, 0.99, 0.01],
  <num>[77, 83, 0.61, 0.39],
  <num>[180, 188, 0.74, 0.26],
  <num>[316, 328, 0.87, 0.13],
  <num>[736, 9999, 1.00, 0.00],
  <num>[84, 91, 0.62, 0.38],
  <num>[189, 197, 0.75, 0.25],
  <num>[329, 344, 0.88, 0.12],
];

/// Look up the performance difference (dp) for a given score percentage (p).
int _lookupDp(double p) {
  // Find the closest match in the table (by absolute difference).
  int? closestDp;
  double minDiff = double.infinity;

  for (final MapEntry<double, int> entry in _table_8_1_1.entries) {
    final double diff = (entry.key - p).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closestDp = entry.value;
    }
  }

  return closestDp ?? 0;
}

/// Look up expected score (PD) based on rating difference, ignoring differences >400.
double _lookupPD(int absDiff, bool isHumanHigher) {
  for (final List<num> range in _table_8_1_2) {
    if (absDiff >= range[0] && absDiff <= range[1]) {
      return isHumanHigher ? range[2].toDouble() : range[3].toDouble();
    }
  }
  // If diff > 735, PD is effectively 1.0 or 0.0
  return isHumanHigher ? 1.0 : 0.0;
}

/// Compute expected score for human vs. AI, capping rating difference at ±400.
double _computeExpected(int humanRating, int aiRating) {
  int diff = humanRating - aiRating;

  // Cap difference at 400
  if (diff > 400) {
    diff = 400;
  } else if (diff < -400) {
    diff = -400;
  }

  final bool isHumanHigher = humanRating >= aiRating;
  final int absDiff = diff.abs();

  return _lookupPD(absDiff, isHumanHigher);
}

/// Select appropriate K-factor based on player experience (games) and current rating.
/// CUSTOMIZATION: We do *not* use the under-18 rule or a permanent K=10 once 2400 is reached.
/// We only use current rating for deciding K=20 or K=10, reverting if rating dips below 2400.
int _selectK(int totalGamesPlayed, int humanRating, int gamesThisPeriod) {
  int k;
  // FIDE rule: K=40 if fewer than 30 total games (a “new” player).
  if (totalGamesPlayed < 30) {
    k = 40;
  }
  // If rating <2400 => K=20, else K=10
  else if (humanRating < 2400) {
    k = 20;
  } else {
    k = 10;
  }

  // Ensure K × n ≤ 700 (FIDE 8.3.3 last paragraph).
  if (gamesThisPeriod * k > 700) {
    k = 700 ~/ gamesThisPeriod;
  }

  return k;
}

/// Calculate a provisional (initial) rating for an unrated or <5-games player.
/// CUSTOMIZATION: We do *not* ignore an all-loss (0 score) event.
/// We do bound the result as per your custom logic:
///  - For 1–4 total games: [1400 .. (1400 + n*150)]
///  - For exactly 5 games: [1400 .. 2200]
///
/// We also add two hypothetical 1800-rated opponents with 0.5 score each (FIDE 8.2.2).
int _calculateInitialRating(List<int> aiRatingsList, List<double> resultsList) {
  final int n = resultsList.length;

  // Add two virtual opponents rated 1800 with 0.5 score each
  final List<int> ratingsExtended = List<int>.from(aiRatingsList)
    ..addAll(<int>[1800, 1800]);
  final List<double> resultsExtended = List<double>.from(resultsList)
    ..addAll(<double>[0.5, 0.5]);

  final int effectiveN = ratingsExtended.length;
  final double ra =
      ratingsExtended.reduce((int a, int b) => a + b) / effectiveN;
  final double p =
      resultsExtended.reduce((double a, double b) => a + b) / effectiveN;

  final int dp = _lookupDp(p);
  int ru = (ra + dp).round();

  // IMPORTANT NOTE (CUSTOMIZATION):
  // Official FIDE (8.2.1–8.2.4) requires at least 5 total rated games
  // before publishing an initial rating and discarding a 0-score first event.
  // We skip that, giving immediate rating:
  //   * 1–4 total games => provisional bounding 1400..(1400 + n*150)
  //   * exactly 5 => bounding 1400..2200.
  int lowerBound;
  int upperBound;

  if (n >= 5) {
    // For 5 or more games in the single batch, treat as "5th game" bounding.
    lowerBound = 1400;
    upperBound = 2200;
  } else {
    // Provisional bounds for 1–4 games
    lowerBound = 1400;
    upperBound = 1400 + n * 150;
  }

  if (ru < lowerBound) {
    ru = lowerBound;
  } else if (ru > upperBound) {
    ru = upperBound;
  }

  return ru;
}

/// Standard ELO update for players who already have a rating and >=5 total games.
int _updateRating(
  int humanRating,
  List<int> aiRatingsList,
  List<double> resultsList,
  int totalGamesPlayed,
) {
  final int n = resultsList.length;
  double sumDelta = 0;

  // sumDelta = Σ (score_i - expected_i)
  for (int i = 0; i < n; i++) {
    final double expected = _computeExpected(humanRating, aiRatingsList[i]);
    final double delta = resultsList[i] - expected;
    sumDelta += delta;
  }

  // Apply K factor
  final int k = _selectK(totalGamesPlayed, humanRating, n);

  // Continuous rating change
  final double continuousChange = k * sumDelta;

  // Round away from zero
  int ratingChange;
  if (continuousChange >= 0) {
    ratingChange = (continuousChange + 0.5).floor();
  } else {
    ratingChange = (continuousChange - 0.5).ceil();
  }

  return humanRating + ratingChange;
}

/// Calculate new ELO ratings from a single game result, ignoring the "fewer than 5 games" logic.
/// This is just a helper if you need a direct calculation for one game.
(int, int) calculateNewRatings(
  int humanRating,
  int aiRating,
  HumanOutcome result,
  int totalGamesPlayed,
) {
  double actualScore;
  switch (result) {
    case HumanOutcome.playerWin:
      actualScore = 1.0;
      break;
    case HumanOutcome.opponentWin:
      actualScore = 0.0;
      break;
    case HumanOutcome.draw:
      actualScore = 0.5;
      break;
  }

  // For single game calculation, use _computeExpected for expected score
  final double expectedScore = _computeExpected(humanRating, aiRating);

  // Select appropriate K factor based on player experience and rating
  final int k = _selectK(totalGamesPlayed, humanRating, 1);

  // Calculate rating change using calculated K factor
  final double continuousChange = k * (actualScore - expectedScore);

  // Round away from zero
  int ratingChange;
  if (continuousChange >= 0) {
    ratingChange = (continuousChange + 0.5).floor();
  } else {
    ratingChange = (continuousChange - 0.5).ceil();
  }

  // Return new ratings
  return (humanRating + ratingChange, aiRating - ratingChange);
}

/// Process multiple games in a batch.
/// CUSTOMIZATION: If total < 5, use `_calculateInitialRating` with bounding; else `_updateRating`.
int processGamesForHumanRating(
  int? currentHumanRating,
  List<int> aiRatingsList,
  List<double> resultsList,
  int totalGamesPlayed,
) {
  // If unrated or fewer than 5 total games => treat as provisional.
  if (currentHumanRating == null || totalGamesPlayed < 5) {
    return _calculateInitialRating(aiRatingsList, resultsList);
  }

  // Otherwise standard ELO update.
  return _updateRating(
      currentHumanRating, aiRatingsList, resultsList, totalGamesPlayed);
}
