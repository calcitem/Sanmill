// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// daily_puzzle_service.dart
//
// Service for managing daily puzzle rotation and completion tracking

import 'package:flutter/foundation.dart';

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
    required this.completedToday,
    required this.totalCompleted,
  });

  final DateTime date;
  final String puzzleId;
  final int dayNumber;
  final bool completedToday;
  final int totalCompleted;
}

/// Service for managing daily puzzles
class DailyPuzzleService {
  factory DailyPuzzleService() => _instance;

  DailyPuzzleService._internal();

  static final DailyPuzzleService _instance = DailyPuzzleService._internal();

  static const String _tag = "[DailyPuzzleService]";

  @visibleForTesting
  static DateTime Function()? debugNowOverride;

  /// Epoch date for day number calculation (January 1, 2025)
  static final DateTime _epochDate = DateTime(2025);

  /// Get today's puzzle information
  DailyPuzzleInfo getTodaysPuzzle() {
    final DateTime today = _normalizeDate(_now());
    final int dayNumber = _getDayNumber(today);
    final DailyPuzzleStats stats = _getStats();
    final bool completedToday = stats.completedDates.contains(
      today.toIso8601String(),
    );

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
        completedToday: completedToday,
        totalCompleted: stats.completedDates.length,
      );
    }

    // Select puzzle based on day number (deterministic rotation)
    final PuzzleInfo todaysPuzzle = allPuzzles[dayNumber % allPuzzles.length];

    return DailyPuzzleInfo(
      date: today,
      puzzleId: todaysPuzzle.id,
      dayNumber: dayNumber,
      completedToday: completedToday,
      totalCompleted: stats.completedDates.length,
    );
  }

  /// Record completion of today's puzzle
  Future<void> recordCompletion() async {
    final DateTime today = _normalizeDate(_now());
    final DailyPuzzleStats stats = _getStats();

    if (!stats.completedDates.contains(today.toIso8601String())) {
      stats.completedDates.add(today.toIso8601String());
      await _saveStats(stats);
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

  DateTime _now() => debugNowOverride?.call() ?? DateTime.now();
}

/// Statistics for daily puzzles
class DailyPuzzleStats {
  DailyPuzzleStats({required this.completedDates, required this.longestStreak});

  List<String> completedDates;

  /// Retained only so existing streak history is not destroyed on save.
  int longestStreak;
}
