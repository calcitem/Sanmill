// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_settings.dart

part of 'puzzle_models.dart';

/// Settings for puzzle mode stored in Hive
@HiveType(typeId: 32)
class PuzzleSettings {
  const PuzzleSettings({
    this.allPuzzles = const <PuzzleInfo>[],
    this.progressMap = const <String, PuzzleProgress>{},
    this.showHints = true,
    this.autoShowSolution = false,
    this.soundEnabled = true,
    this.userRating = 1500, // Default ELO-style rating
  });

  /// Create from JSON
  factory PuzzleSettings.fromJson(Map<String, dynamic> json) {
    return PuzzleSettings(
      allPuzzles:
          (json['allPuzzles'] as List<dynamic>?)
              ?.map(
                (dynamic e) => PuzzleInfo.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <PuzzleInfo>[],
      progressMap:
          (json['progressMap'] as Map<String, dynamic>?)?.map(
            (String k, dynamic v) => MapEntry<String, PuzzleProgress>(
              k,
              PuzzleProgress.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          const <String, PuzzleProgress>{},
      showHints: json['showHints'] as bool? ?? true,
      autoShowSolution: json['autoShowSolution'] as bool? ?? false,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      userRating: json['userRating'] as int? ?? 1500,
    );
  }

  /// All available puzzles
  @HiveField(0)
  final List<PuzzleInfo> allPuzzles;

  /// Map of puzzle ID to user progress
  @HiveField(1)
  final Map<String, PuzzleProgress> progressMap;

  /// Whether to show hints button
  @HiveField(2)
  final bool showHints;

  /// Whether to automatically show solution after failure
  @HiveField(3)
  final bool autoShowSolution;

  /// Whether sound is enabled for puzzles
  @HiveField(4)
  final bool soundEnabled;

  /// User's puzzle rating (ELO-style, default 1500)
  @HiveField(5)
  final int userRating;

  /// Creates a copy with updated fields
  PuzzleSettings copyWith({
    List<PuzzleInfo>? allPuzzles,
    Map<String, PuzzleProgress>? progressMap,
    bool? showHints,
    bool? autoShowSolution,
    bool? soundEnabled,
    int? userRating,
  }) {
    return PuzzleSettings(
      allPuzzles: allPuzzles ?? this.allPuzzles,
      progressMap: progressMap ?? this.progressMap,
      showHints: showHints ?? this.showHints,
      autoShowSolution: autoShowSolution ?? this.autoShowSolution,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      userRating: userRating ?? this.userRating,
    );
  }

  /// Get progress for a specific puzzle
  PuzzleProgress? getProgress(String puzzleId) {
    return progressMap[puzzleId];
  }

  /// Update progress for a specific puzzle
  PuzzleSettings updateProgress(PuzzleProgress progress) {
    final Map<String, PuzzleProgress> newMap = Map<String, PuzzleProgress>.from(
      progressMap,
    );
    newMap[progress.puzzleId] = progress;
    return copyWith(progressMap: newMap);
  }

  /// Get total number of completed puzzles
  int get totalCompleted {
    return progressMap.values.where((PuzzleProgress p) => p.completed).length;
  }

  /// Get total number of stars earned
  int get totalStars {
    return progressMap.values.fold<int>(
      0,
      (int sum, PuzzleProgress p) => sum + p.stars,
    );
  }

  /// Get completion percentage
  double get completionPercentage {
    if (allPuzzles.isEmpty) {
      return 0.0;
    }
    return (totalCompleted / allPuzzles.length) * 100;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'allPuzzles': allPuzzles.map((PuzzleInfo p) => p.toJson()).toList(),
      'progressMap': progressMap.map(
        (String k, PuzzleProgress v) =>
            MapEntry<String, dynamic>(k, v.toJson()),
      ),
      'showHints': showHints,
      'autoShowSolution': autoShowSolution,
      'soundEnabled': soundEnabled,
      'userRating': userRating,
    };
  }
}
