// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_manager.dart
//
// Manages puzzle loading, saving, and progress tracking

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';
import 'built_in_puzzles.dart';
import 'puzzle_export_service.dart';

/// Singleton service for managing puzzles
class PuzzleManager {
  factory PuzzleManager() => _instance;

  PuzzleManager._internal();

  static final PuzzleManager _instance = PuzzleManager._internal();

  static const String _tag = "[PuzzleManager]";

  /// Notifier for puzzle settings changes
  final ValueNotifier<PuzzleSettings> settingsNotifier =
      ValueNotifier<PuzzleSettings>(const PuzzleSettings());

  /// Initialize the puzzle manager
  Future<void> init() async {
    logger.i("$_tag Initializing PuzzleManager");
    final PuzzleSettings settings = DB().puzzleSettings;

    // Remove all built-in puzzles from stored data
    final List<PuzzleInfo> customPuzzlesOnly = settings.allPuzzles
        .where((PuzzleInfo p) => p.isCustom)
        .toList();

    if (customPuzzlesOnly.length < settings.allPuzzles.length) {
      logger.i(
        "$_tag Removed ${settings.allPuzzles.length - customPuzzlesOnly.length} "
        "built-in puzzles, keeping ${customPuzzlesOnly.length} custom puzzles",
      );
      final PuzzleSettings cleanedSettings = settings.copyWith(
        allPuzzles: customPuzzlesOnly,
      );
      settingsNotifier.value = cleanedSettings;
      _saveSettings(cleanedSettings);
    } else {
      settingsNotifier.value = settings;
    }

    logger.i("$_tag Ready - ${customPuzzlesOnly.length} custom puzzles loaded");
  }

  /// Load built-in puzzles from assets/predefined collection
  Future<void> loadBuiltInPuzzles() async {
    logger.i("$_tag Loading built-in puzzles");
    final List<PuzzleInfo> builtInPuzzles = _getBuiltInPuzzles();
    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      allPuzzles: builtInPuzzles,
    );
    _saveSettings(newSettings);
  }

  /// Get all available puzzles
  List<PuzzleInfo> getAllPuzzles() {
    return settingsNotifier.value.allPuzzles;
  }

  /// Get puzzles filtered by category
  List<PuzzleInfo> getPuzzlesByCategory(PuzzleCategory category) {
    return settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) => p.category == category)
        .toList();
  }

  /// Get puzzles filtered by difficulty
  List<PuzzleInfo> getPuzzlesByDifficulty(PuzzleDifficulty difficulty) {
    return settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) => p.difficulty == difficulty)
        .toList();
  }

  /// Get a specific puzzle by ID
  PuzzleInfo? getPuzzleById(String id) {
    for (final PuzzleInfo puzzle in settingsNotifier.value.allPuzzles) {
      if (puzzle.id == id) {
        return puzzle;
      }
    }
    logger.w("$_tag Puzzle with id $id not found");
    return null;
  }

  /// Get progress for a specific puzzle
  PuzzleProgress? getProgress(String puzzleId) {
    return settingsNotifier.value.getProgress(puzzleId);
  }

  /// Update progress for a puzzle
  void updateProgress(PuzzleProgress progress) {
    logger.i("$_tag Updating progress for puzzle ${progress.puzzleId}");
    final PuzzleSettings newSettings = settingsNotifier.value.updateProgress(
      progress,
    );
    _saveSettings(newSettings);
  }

  /// Mark a puzzle as completed
  void completePuzzle({
    required String puzzleId,
    required int moveCount,
    required PuzzleDifficulty difficulty,
    required int optimalMoveCount,
    required bool hintsUsed,
    bool solutionViewed = false,
  }) {
    final PuzzleProgress? currentProgress = getProgress(puzzleId);
    final int attempts = (currentProgress?.attempts ?? 0) + 1;
    final int totalHintsUsed = currentProgress?.hintsUsed ?? 0;

    final int stars = PuzzleProgress.calculateStars(
      moveCount: moveCount,
      optimalMoveCount: optimalMoveCount,
      difficulty: difficulty,
      hintsUsed: hintsUsed,
      solutionViewed: solutionViewed,
    );

    final bool isNewBest =
        currentProgress == null ||
        currentProgress.bestMoveCount == null ||
        moveCount < currentProgress.bestMoveCount!;

    final PuzzleProgress newProgress = PuzzleProgress(
      puzzleId: puzzleId,
      completed: true,
      stars: stars > (currentProgress?.stars ?? 0)
          ? stars
          : (currentProgress?.stars ?? 0),
      bestMoveCount: isNewBest
          ? moveCount
          : (currentProgress.bestMoveCount ?? moveCount),
      attempts: attempts,
      hintsUsed: totalHintsUsed,
      solutionViewed:
          solutionViewed || (currentProgress?.solutionViewed ?? false),
      lastAttemptDate: DateTime.now(),
      completionDate: currentProgress?.completionDate ?? DateTime.now(),
    );

    updateProgress(newProgress);

    // Update user rating if puzzle has a rating
    final PuzzleInfo? puzzle = getPuzzleById(puzzleId);
    if (puzzle != null && puzzle.rating != null && !solutionViewed) {
      _updateUserRating(
        puzzleRating: puzzle.rating!,
        success: stars > 0,
        hintsUsed: hintsUsed,
      );
    }

    logger.i("$_tag Puzzle $puzzleId completed with $stars stars");
  }

  /// Update user's puzzle rating based on performance
  void _updateUserRating({
    required int puzzleRating,
    required bool success,
    required bool hintsUsed,
  }) {
    final PuzzleSettings currentSettings = settingsNotifier.value;
    final int currentRating = currentSettings.userRating;

    // Calculate expected score based on rating difference
    final double expectedScore =
        1.0 / (1.0 + pow(10.0, (puzzleRating - currentRating) / 400.0));

    // Actual score: 1 for success, 0.5 if hints used, 0 for failure
    final double actualScore = success ? (hintsUsed ? 0.5 : 1.0) : 0.0;

    // K-factor (higher for beginners, lower for experienced)
    final double kFactor = currentRating < 1500 ? 40.0 : 20.0;

    // Calculate rating change
    final int ratingChange = (kFactor * (actualScore - expectedScore)).round();
    final int newRating = max(100, min(3000, currentRating + ratingChange));

    // Update settings with new rating
    final PuzzleSettings updatedSettings = currentSettings.copyWith(
      userRating: newRating,
    );
    _saveSettings(updatedSettings);

    logger.i(
      "$_tag User rating updated: $currentRating -> $newRating (${ratingChange >= 0 ? '+' : ''}$ratingChange)",
    );
  }

  /// Record a failed attempt
  void recordAttempt(String puzzleId) {
    final PuzzleProgress? currentProgress = getProgress(puzzleId);
    final int attempts = (currentProgress?.attempts ?? 0) + 1;
    final int hintsUsed = currentProgress?.hintsUsed ?? 0;

    final PuzzleProgress newProgress = PuzzleProgress(
      puzzleId: puzzleId,
      completed: currentProgress?.completed ?? false,
      stars: currentProgress?.stars ?? 0,
      bestMoveCount: currentProgress?.bestMoveCount,
      attempts: attempts,
      hintsUsed: hintsUsed,
      solutionViewed: currentProgress?.solutionViewed ?? false,
      lastAttemptDate: DateTime.now(),
      completionDate: currentProgress?.completionDate,
    );

    updateProgress(newProgress);
  }

  /// Record that the user used a hint without counting a new attempt.
  ///
  /// Attempts should represent discrete solve attempts (retry/give up/solve),
  /// not hint usage within the same attempt.
  void recordHintUsed(String puzzleId) {
    final PuzzleProgress? currentProgress = getProgress(puzzleId);
    final int newHintsUsed = (currentProgress?.hintsUsed ?? 0) + 1;

    final PuzzleProgress newProgress = PuzzleProgress(
      puzzleId: puzzleId,
      completed: currentProgress?.completed ?? false,
      stars: currentProgress?.stars ?? 0,
      bestMoveCount: currentProgress?.bestMoveCount,
      attempts: currentProgress?.attempts ?? 0,
      hintsUsed: newHintsUsed,
      solutionViewed: currentProgress?.solutionViewed ?? false,
      lastAttemptDate: DateTime.now(),
      completionDate: currentProgress?.completionDate,
    );

    updateProgress(newProgress);
  }

  /// Reset progress for a specific puzzle
  void resetProgress(String puzzleId) {
    logger.i("$_tag Resetting progress for puzzle $puzzleId");
    final PuzzleProgress newProgress = PuzzleProgress(puzzleId: puzzleId);
    updateProgress(newProgress);
  }

  /// Reset all puzzle progress
  void resetAllProgress() {
    logger.i("$_tag Resetting all puzzle progress");
    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      progressMap: <String, PuzzleProgress>{},
    );
    _saveSettings(newSettings);
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    final PuzzleSettings settings = settingsNotifier.value;
    return <String, dynamic>{
      'totalPuzzles': settings.allPuzzles.length,
      'completedPuzzles': settings.totalCompleted,
      'totalStars': settings.totalStars,
      'completionPercentage': settings.completionPercentage,
    };
  }

  /// Update settings
  void updateSettings({
    bool? showHints,
    bool? autoShowSolution,
    bool? soundEnabled,
  }) {
    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      showHints: showHints ?? settingsNotifier.value.showHints,
      autoShowSolution:
          autoShowSolution ?? settingsNotifier.value.autoShowSolution,
      soundEnabled: soundEnabled ?? settingsNotifier.value.soundEnabled,
    );
    _saveSettings(newSettings);
  }

  /// Save settings to database
  void _saveSettings(PuzzleSettings settings) {
    settingsNotifier.value = settings;
    DB().puzzleSettings = settings;
  }

  /// Get built-in puzzles collection
  List<PuzzleInfo> _getBuiltInPuzzles() {
    return getBuiltInPuzzles();
  }

  /// Add a new custom puzzle
  /// Returns true if successful, false if puzzle with same ID already exists
  bool addCustomPuzzle(PuzzleInfo puzzle) {
    // Check if puzzle with same ID already exists
    if (getPuzzleById(puzzle.id) != null) {
      logger.w("$_tag Puzzle with id ${puzzle.id} already exists");
      return false;
    }

    logger.i("$_tag Adding custom puzzle: ${puzzle.title}");
    final List<PuzzleInfo> updatedPuzzles = List<PuzzleInfo>.from(
      settingsNotifier.value.allPuzzles,
    )..add(puzzle);

    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      allPuzzles: updatedPuzzles,
    );
    _saveSettings(newSettings);
    return true;
  }

  /// Delete a puzzle (only custom puzzles can be deleted)
  /// Returns true if successful, false if puzzle doesn't exist or is built-in
  bool deletePuzzle(String puzzleId) {
    final PuzzleInfo? puzzle = getPuzzleById(puzzleId);

    if (puzzle == null) {
      logger.w("$_tag Cannot delete: puzzle $puzzleId not found");
      return false;
    }

    if (!puzzle.isCustom) {
      logger.w("$_tag Cannot delete built-in puzzle: $puzzleId");
      return false;
    }

    logger.i("$_tag Deleting custom puzzle: ${puzzle.title}");
    final List<PuzzleInfo> updatedPuzzles = settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) => p.id != puzzleId)
        .toList();

    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      allPuzzles: updatedPuzzles,
    );
    _saveSettings(newSettings);
    return true;
  }

  /// Delete multiple puzzles at once
  /// Returns the number of successfully deleted puzzles
  int deletePuzzles(List<String> puzzleIds) {
    int deletedCount = 0;
    for (final String id in puzzleIds) {
      if (deletePuzzle(id)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }

  /// Get all custom puzzles
  List<PuzzleInfo> getCustomPuzzles() {
    return settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) => p.isCustom)
        .toList();
  }

  /// Get all built-in puzzles
  List<PuzzleInfo> getBuiltInPuzzlesFromSettings() {
    return settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) => !p.isCustom)
        .toList();
  }

  /// Export puzzles to a file and share
  /// Returns true if successful
  Future<bool> exportAndSharePuzzles(
    List<PuzzleInfo> puzzles, {
    String? fileName,
    String? shareText,
    String? shareSubject,
  }) async {
    logger.i("$_tag Exporting ${puzzles.length} puzzles");
    return PuzzleExportService.sharePuzzles(
      puzzles,
      fileName: fileName,
      shareText: shareText,
      shareSubject: shareSubject,
    );
  }

  /// Import puzzles from a file
  /// Returns ImportResult with success status and imported puzzles
  Future<ImportResult> importPuzzles() async {
    logger.i("$_tag Starting puzzle import");
    final ImportResult result = await PuzzleExportService.importPuzzles();

    if (result.success && result.puzzles.isNotEmpty) {
      // Add imported puzzles to the collection
      int addedCount = 0;
      int skippedCount = 0;

      for (final PuzzleInfo puzzle in result.puzzles) {
        // Ensure imported puzzles are marked as custom
        final PuzzleInfo customPuzzle = puzzle.copyWith(isCustom: true);

        if (addCustomPuzzle(customPuzzle)) {
          addedCount++;
        } else {
          skippedCount++;
        }
      }

      logger.i(
        "$_tag Imported $addedCount puzzles, skipped $skippedCount duplicates",
      );
    }

    return result;
  }

  /// Update an existing puzzle
  /// Returns true if successful, false if puzzle doesn't exist or is built-in
  bool updatePuzzle(PuzzleInfo updatedPuzzle) {
    final PuzzleInfo? existingPuzzle = getPuzzleById(updatedPuzzle.id);

    if (existingPuzzle == null) {
      logger.w("$_tag Cannot update: puzzle ${updatedPuzzle.id} not found");
      return false;
    }

    if (!existingPuzzle.isCustom) {
      logger.w("$_tag Cannot update built-in puzzle: ${updatedPuzzle.id}");
      return false;
    }

    logger.i("$_tag Updating custom puzzle: ${updatedPuzzle.title}");
    final List<PuzzleInfo> updatedPuzzles = settingsNotifier.value.allPuzzles
        .map((PuzzleInfo p) => p.id == updatedPuzzle.id ? updatedPuzzle : p)
        .toList();

    final PuzzleSettings newSettings = settingsNotifier.value.copyWith(
      allPuzzles: updatedPuzzles,
    );
    _saveSettings(newSettings);
    return true;
  }

  /// Dispose resources
  void dispose() {
    settingsNotifier.dispose();
  }

  /// Get recommended puzzles based on user's rating
  /// Returns puzzles within a rating range suitable for the user
  List<PuzzleInfo> getRecommendedPuzzles({
    int? targetRating,
    int ratingRange = 200,
    int maxCount = 10,
  }) {
    final int userRating = targetRating ?? settingsNotifier.value.userRating;
    final PuzzleSettings settings = settingsNotifier.value;

    // Get unsolved or poorly solved puzzles
    final List<PuzzleInfo> candidates = settingsNotifier.value.allPuzzles
        .where((PuzzleInfo p) {
          final PuzzleProgress? progress = settings.getProgress(p.id);

          // Include if:
          // 1. Never attempted
          // 2. Not completed
          // 3. Completed but with low stars (< 3)
          if (progress == null || !progress.completed) {
            return true;
          }
          return progress.stars < 3;
        })
        .where((PuzzleInfo p) => p.rating != null)
        .toList();

    if (candidates.isEmpty) {
      return <PuzzleInfo>[];
    }

    // Sort by rating closeness to user rating
    candidates.sort((PuzzleInfo a, PuzzleInfo b) {
      final int aDiff = (a.rating! - userRating).abs();
      final int bDiff = (b.rating! - userRating).abs();
      return aDiff.compareTo(bDiff);
    });

    // Filter to puzzles within rating range and return top matches
    final List<PuzzleInfo> recommended = candidates
        .where((PuzzleInfo p) => (p.rating! - userRating).abs() <= ratingRange)
        .take(maxCount)
        .toList();

    logger.i(
      "$_tag Found ${recommended.length} recommended puzzles for rating $userRating",
    );

    return recommended;
  }
}
