// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_manager.dart
//
// Manages puzzle loading, saving, and progress tracking

import 'package:flutter/foundation.dart';

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';
import 'built_in_puzzles.dart';

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
    settingsNotifier.value = settings;

    // If no puzzles exist, load the built-in collection
    if (settings.allPuzzles.isEmpty) {
      await loadBuiltInPuzzles();
    }
  }

  /// Load built-in puzzles from assets/predefined collection
  Future<void> loadBuiltInPuzzles() async {
    logger.i("$_tag Loading built-in puzzles");
    final List<PuzzleInfo> builtInPuzzles = _getBuiltInPuzzles();
    final PuzzleSettings newSettings =
        settingsNotifier.value.copyWith(allPuzzles: builtInPuzzles);
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
    try {
      return settingsNotifier.value.allPuzzles
          .firstWhere((PuzzleInfo p) => p.id == id);
    } catch (e) {
      logger.w("$_tag Puzzle with id $id not found");
      return null;
    }
  }

  /// Get progress for a specific puzzle
  PuzzleProgress? getProgress(String puzzleId) {
    return settingsNotifier.value.getProgress(puzzleId);
  }

  /// Update progress for a puzzle
  void updateProgress(PuzzleProgress progress) {
    logger.i("$_tag Updating progress for puzzle ${progress.puzzleId}");
    final PuzzleSettings newSettings =
        settingsNotifier.value.updateProgress(progress);
    _saveSettings(newSettings);
  }

  /// Mark a puzzle as completed
  void completePuzzle({
    required String puzzleId,
    required int moveCount,
    required PuzzleDifficulty difficulty,
    required int optimalMoveCount,
    required bool hintsUsed,
  }) {
    final PuzzleProgress? currentProgress = getProgress(puzzleId);
    final int attempts = (currentProgress?.attempts ?? 0) + 1;
    final int totalHintsUsed = (currentProgress?.hintsUsed ?? 0) + (hintsUsed ? 1 : 0);

    final int stars = PuzzleProgress.calculateStars(
      moveCount: moveCount,
      optimalMoveCount: optimalMoveCount,
      difficulty: difficulty,
      hintsUsed: hintsUsed,
    );

    final bool isNewBest = currentProgress == null ||
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
          : (currentProgress?.bestMoveCount ?? moveCount),
      attempts: attempts,
      hintsUsed: totalHintsUsed,
      lastAttemptDate: DateTime.now(),
      completionDate: currentProgress?.completionDate ?? DateTime.now(),
    );

    updateProgress(newProgress);
    logger.i("$_tag Puzzle $puzzleId completed with $stars stars");
  }

  /// Record a failed attempt
  void recordAttempt(String puzzleId, {bool hintUsed = false}) {
    final PuzzleProgress? currentProgress = getProgress(puzzleId);
    final int attempts = (currentProgress?.attempts ?? 0) + 1;
    final int hintsUsed = (currentProgress?.hintsUsed ?? 0) + (hintUsed ? 1 : 0);

    final PuzzleProgress newProgress = PuzzleProgress(
      puzzleId: puzzleId,
      completed: currentProgress?.completed ?? false,
      stars: currentProgress?.stars ?? 0,
      bestMoveCount: currentProgress?.bestMoveCount,
      attempts: attempts,
      hintsUsed: hintsUsed,
      lastAttemptDate: DateTime.now(),
      completionDate: currentProgress?.completionDate,
    );

    updateProgress(newProgress);
  }

  /// Reset progress for a specific puzzle
  void resetProgress(String puzzleId) {
    logger.i("$_tag Resetting progress for puzzle $puzzleId");
    final PuzzleProgress newProgress = PuzzleProgress(
      puzzleId: puzzleId,
      completed: false,
      stars: 0,
      attempts: 0,
      hintsUsed: 0,
    );
    updateProgress(newProgress);
  }

  /// Reset all puzzle progress
  void resetAllProgress() {
    logger.i("$_tag Resetting all puzzle progress");
    final PuzzleSettings newSettings =
        settingsNotifier.value.copyWith(progressMap: <String, PuzzleProgress>{});
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
      autoShowSolution: autoShowSolution ?? settingsNotifier.value.autoShowSolution,
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

  /// Dispose resources
  void dispose() {
    settingsNotifier.dispose();
  }
}
