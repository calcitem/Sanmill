// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// daily_puzzle_service.dart
//
// Service for managing daily puzzle rotation and streak tracking

import '../../shared/database/database.dart';
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
    // Load from database
    final dynamic data = DB().puzzleAnalyticsBox.get('dailyPuzzleStats');
    if (data == null) {
      return DailyPuzzleStats(completedDates: <String>[], longestStreak: 0);
    }

    try {
      final Map<String, dynamic> map = Map<String, dynamic>.from(
        data as Map<dynamic, dynamic>,
      );
      return DailyPuzzleStats(
        completedDates: List<String>.from(
          map['completedDates'] as List<dynamic>? ?? <dynamic>[],
        ),
        longestStreak: map['longestStreak'] as int? ?? 0,
      );
    } catch (e) {
      logger.e("$_tag Failed to load daily puzzle stats: $e");
      return DailyPuzzleStats(completedDates: <String>[], longestStreak: 0);
    }
  }

  /// Save puzzle statistics
  Future<void> _saveStats(DailyPuzzleStats stats) async {
    // Save to database
    try {
      await DB().puzzleAnalyticsBox.put('dailyPuzzleStats', <String, dynamic>{
        'completedDates': stats.completedDates,
        'longestStreak': stats.longestStreak,
      });
      logger.i(
        "$_tag Saved daily puzzle stats: ${stats.completedDates.length} completed",
      );
    } catch (e) {
      logger.e("$_tag Failed to save daily puzzle stats: $e");
    }
  }

  /// Calculate current streak.
  ///
  /// If today has not been completed yet the streak is still considered
  /// active as long as yesterday was completed (the user still has a chance
  /// to extend it today).  In that case we start counting from yesterday.
  int _calculateCurrentStreak(DailyPuzzleStats stats, DateTime today) {
    if (stats.completedDates.isEmpty) {
      return 0;
    }

    final String todayStr = _normalizeDate(today).toIso8601String();
    final bool completedToday = stats.completedDates.contains(todayStr);

    // Start from today if completed, otherwise from yesterday so an ongoing
    // streak is not prematurely reported as 0.
    DateTime checkDate = completedToday
        ? today
        : today.subtract(const Duration(days: 1));

    int streak = 0;

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
