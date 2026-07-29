// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../models/puzzle_models.dart';

/// Shared difficulty policy for daily and continuous puzzle practice.
class PuzzleSelectionService {
  const PuzzleSelectionService();

  static const int beginnerCompletionLimit = 3;
  static const int guidedCompletionLimit = 10;
  static const int adaptiveRatingRange = 200;

  /// Returns puzzles appropriate for the user's current experience.
  ///
  /// The first three completed puzzles stay at beginner level. The next seven
  /// prefer easy puzzles. Rating-based selection only starts after ten
  /// completions, when the rating has enough evidence to guide difficulty.
  List<PuzzleInfo> candidatesForExperience(
    List<PuzzleInfo> puzzles, {
    required int experience,
    required int userRating,
  }) {
    if (puzzles.isEmpty) {
      return const <PuzzleInfo>[];
    }

    if (experience < beginnerCompletionLimit) {
      return _guidedCandidates(
        puzzles,
        preferred: PuzzleDifficulty.beginner,
        fallback: PuzzleDifficulty.easy,
      );
    }
    if (experience < guidedCompletionLimit) {
      return _guidedCandidates(
        puzzles,
        preferred: PuzzleDifficulty.easy,
        fallback: PuzzleDifficulty.beginner,
      );
    }
    return _adaptiveCandidates(puzzles, userRating);
  }

  List<PuzzleInfo> _guidedCandidates(
    List<PuzzleInfo> puzzles, {
    required PuzzleDifficulty preferred,
    required PuzzleDifficulty fallback,
  }) {
    final List<PuzzleInfo> preferredPuzzles = puzzles
        .where((PuzzleInfo puzzle) => puzzle.difficulty == preferred)
        .toList();
    if (preferredPuzzles.isNotEmpty) {
      return preferredPuzzles;
    }

    final List<PuzzleInfo> fallbackPuzzles = puzzles
        .where((PuzzleInfo puzzle) => puzzle.difficulty == fallback)
        .toList();
    return fallbackPuzzles.isNotEmpty ? fallbackPuzzles : puzzles;
  }

  List<PuzzleInfo> _adaptiveCandidates(
    List<PuzzleInfo> puzzles,
    int userRating,
  ) {
    final List<PuzzleInfo> ratedPuzzles = puzzles
        .where((PuzzleInfo puzzle) => puzzle.rating != null)
        .toList();
    if (ratedPuzzles.isEmpty) {
      return puzzles;
    }

    final List<PuzzleInfo> inRange = ratedPuzzles
        .where(
          (PuzzleInfo puzzle) =>
              (puzzle.rating! - userRating).abs() <= adaptiveRatingRange,
        )
        .toList();
    if (inRange.isNotEmpty) {
      return inRange;
    }

    ratedPuzzles.sort((PuzzleInfo a, PuzzleInfo b) {
      final int aDistance = (a.rating! - userRating).abs();
      final int bDistance = (b.rating! - userRating).abs();
      final int distanceComparison = aDistance.compareTo(bDistance);
      return distanceComparison != 0
          ? distanceComparison
          : a.id.compareTo(b.id);
    });
    final int closestRating = (ratedPuzzles.first.rating! - userRating).abs();
    return ratedPuzzles
        .where(
          (PuzzleInfo puzzle) =>
              (puzzle.rating! - userRating).abs() == closestRating,
        )
        .toList();
  }
}
