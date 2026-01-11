// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_progress.dart

part of 'puzzle_models.dart';

/// Represents user's progress on a specific puzzle
@HiveType(typeId: 31)
class PuzzleProgress {
  PuzzleProgress({
    required this.puzzleId,
    this.completed = false,
    this.stars = 0,
    this.bestMoveCount,
    this.attempts = 0,
    this.hintsUsed = 0,
    this.solutionViewed = false,
    this.lastAttemptDate,
    this.completionDate,
  });

  /// Create from JSON
  factory PuzzleProgress.fromJson(Map<String, dynamic> json) {
    return PuzzleProgress(
      puzzleId: json['puzzleId'] as String,
      completed: json['completed'] as bool? ?? false,
      stars: json['stars'] as int? ?? 0,
      bestMoveCount: json['bestMoveCount'] as int?,
      attempts: json['attempts'] as int? ?? 0,
      hintsUsed: json['hintsUsed'] as int? ?? 0,
      solutionViewed: json['solutionViewed'] as bool? ?? false,
      lastAttemptDate: json['lastAttemptDate'] != null
          ? DateTime.parse(json['lastAttemptDate'] as String)
          : null,
      completionDate: json['completionDate'] != null
          ? DateTime.parse(json['completionDate'] as String)
          : null,
    );
  }

  /// Puzzle ID this progress belongs to
  @HiveField(0)
  final String puzzleId;

  /// Whether the puzzle has been completed successfully
  @HiveField(1)
  final bool completed;

  /// Star rating (0-3 stars based on performance)
  @HiveField(2)
  final int stars;

  /// Best (minimum) number of moves to solve
  @HiveField(3)
  final int? bestMoveCount;

  /// Number of attempts made
  @HiveField(4)
  final int attempts;

  /// Number of hints used
  @HiveField(5)
  final int hintsUsed;

  /// Whether the user has viewed the solution
  @HiveField(8)
  final bool solutionViewed;

  /// Date of last attempt
  @HiveField(6)
  final DateTime? lastAttemptDate;

  /// Date when first completed
  @HiveField(7)
  final DateTime? completionDate;

  /// Creates a copy with updated fields
  PuzzleProgress copyWith({
    String? puzzleId,
    bool? completed,
    int? stars,
    int? bestMoveCount,
    int? attempts,
    int? hintsUsed,
    bool? solutionViewed,
    DateTime? lastAttemptDate,
    DateTime? completionDate,
  }) {
    return PuzzleProgress(
      puzzleId: puzzleId ?? this.puzzleId,
      completed: completed ?? this.completed,
      stars: stars ?? this.stars,
      bestMoveCount: bestMoveCount ?? this.bestMoveCount,
      attempts: attempts ?? this.attempts,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      solutionViewed: solutionViewed ?? this.solutionViewed,
      lastAttemptDate: lastAttemptDate ?? this.lastAttemptDate,
      completionDate: completionDate ?? this.completionDate,
    );
  }

  /// Calculate stars based on move count
  static int calculateStars({
    required int moveCount,
    required int optimalMoveCount,
    required PuzzleDifficulty difficulty,
    required bool hintsUsed,
    bool solutionViewed = false,
  }) {
    // If solution was viewed, no stars awarded
    if (solutionViewed) {
      return 0;
    }

    // If hints were used, maximum 2 stars
    if (hintsUsed) {
      if (moveCount <= optimalMoveCount) {
        return 2;
      } else if (moveCount <= optimalMoveCount + difficulty.starThreshold) {
        return 1;
      }
      return 0;
    }

    // No hints used
    if (moveCount <= optimalMoveCount) {
      return 3;
    } else if (moveCount <= optimalMoveCount + difficulty.starThreshold) {
      return 2;
    } else if (moveCount <= optimalMoveCount + difficulty.starThreshold * 2) {
      return 1;
    }
    return 0;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'puzzleId': puzzleId,
      'completed': completed,
      'stars': stars,
      'bestMoveCount': bestMoveCount,
      'attempts': attempts,
      'hintsUsed': hintsUsed,
      'solutionViewed': solutionViewed,
      'lastAttemptDate': lastAttemptDate?.toIso8601String(),
      'completionDate': completionDate?.toIso8601String(),
    };
  }
}
