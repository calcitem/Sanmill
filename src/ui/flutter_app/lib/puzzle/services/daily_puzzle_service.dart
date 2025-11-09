// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// daily_puzzle_service.dart
//
// Service for managing daily puzzle rotation and streak tracking

import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';
import 'puzzle_manager.dart';

/// Information about the daily puzzle
class DailyPuzzleInfo {
  DailyPuzzleInfo({
    required this.date,
    required this.puzzleId,
    required this.dayNumber,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalCompleted,
  });

  final DateTime date;
  final String puzzleId;
  final int dayNumber;
  final int currentStreak;
  final int longestStreak;
  final int totalCompleted;
}

/// Service for managing daily puzzles
class DailyPuzzleService {
  factory DailyPuzzleService() => _instance;

  DailyPuzzleService._internal();

  static final DailyPuzzleService _instance = DailyPuzzleService._internal();

  static const String _tag = "[DailyPuzzleService]";

  /// Epoch date for day number calculation (January 1, 2025)
  static final DateTime _epochDate = DateTime(2025);

  /// Get today's puzzle information
  DailyPuzzleInfo getTodaysPuzzle() {
    final DateTime today = _normalizeDate(DateTime.now());
    final int dayNumber = _getDayNumber(today);

    // Get all available puzzles
    final PuzzleManager puzzleManager = PuzzleManager();
    final List<PuzzleInfo> allPuzzles = puzzleManager.getAllPuzzles();

    if (allPuzzles.isEmpty) {
      logger.w("$_tag No puzzles available for daily puzzle");
      // Return a default/placeholder
      return DailyPuzzleInfo(
        date: today,
        puzzleId: '',
        dayNumber: dayNumber,
        currentStreak: 0,
        longestStreak: 0,
        totalCompleted: 0,
      );
    }

    // Select puzzle based on day number (deterministic rotation)
    final PuzzleInfo todaysPuzzle = allPuzzles[dayNumber % allPuzzles.length];

    // Get streak information
    final DailyPuzzleStats stats = _getStats();
    final int currentStreak = _calculateCurrentStreak(stats, today);

    return DailyPuzzleInfo(
      date: today,
      puzzleId: todaysPuzzle.id,
      dayNumber: dayNumber,
      currentStreak: currentStreak,
      longestStreak: stats.longestStreak,
      totalCompleted: stats.completedDates.length,
    );
  }

  /// Record completion of today's puzzle
  void recordCompletion() {
    final DateTime today = _normalizeDate(DateTime.now());
    final DailyPuzzleStats stats = _getStats();

    if (!stats.completedDates.contains(today.toIso8601String())) {
      stats.completedDates.add(today.toIso8601String());

      // Update longest streak
      final int currentStreak = _calculateCurrentStreak(stats, today);
      if (currentStreak > stats.longestStreak) {
        stats.longestStreak = currentStreak;
      }

      _saveStats(stats);
      logger.i("$_tag Recorded daily puzzle completion for $today");
    }
  }

  /// Get puzzle statistics
  DailyPuzzleStats _getStats() {
    // TODO: Load from database
    // For now, return default stats
    return DailyPuzzleStats(completedDates: <String>[], longestStreak: 0);
  }

  /// Save puzzle statistics
  void _saveStats(DailyPuzzleStats stats) {
    // TODO: Save to database
    logger.i(
      "$_tag Saved daily puzzle stats: ${stats.completedDates.length} completed",
    );
  }

  /// Calculate current streak
  int _calculateCurrentStreak(DailyPuzzleStats stats, DateTime today) {
    if (stats.completedDates.isEmpty) {
      return 0;
    }

    int streak = 0;
    DateTime checkDate = today;

    // Check backwards from today
    while (true) {
      final String dateStr = _normalizeDate(checkDate).toIso8601String();
      if (stats.completedDates.contains(dateStr)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  /// Get day number since epoch
  int _getDayNumber(DateTime date) {
    final DateTime normalized = _normalizeDate(date);
    final Duration diff = normalized.difference(_epochDate);
    return diff.inDays;
  }

  /// Normalize date to midnight UTC
  DateTime _normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }
}

/// Statistics for daily puzzles
class DailyPuzzleStats {
  DailyPuzzleStats({required this.completedDates, required this.longestStreak});

  List<String> completedDates;
  int longestStreak;
}
