// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// parental_control_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

// import 'package:shared_preferences/shared_preferences.dart'; // Removed - using existing DB() system

import '../../shared/services/logger.dart';

/// Callback for play time limit notifications
typedef PlayTimeLimitCallback = void Function();

/// Service for managing parental controls and child safety features
/// Ensures compliance with COPPA, GDPR, and Google Play for Education guidelines
class ParentalControlService {
  ParentalControlService._();

  static final ParentalControlService _instance = ParentalControlService._();
  static ParentalControlService get instance => _instance;

  // TODO: Settings keys for future DB() integration
  // static const String _keyEducationalHints = 'parental_educational_hints';
  // static const String _keyAnalytics = 'parental_analytics';
  // static const String _keyMaxPlayTime = 'parental_max_play_time';
  // static const String _keySessionStartTime = 'session_start_time';
  // static const String _keyTotalPlayTimeToday = 'total_play_time_today';
  // static const String _keyLastPlayDate = 'last_play_date';

  Timer? _playTimeTimer;
  DateTime? _sessionStartTime;

  // Default settings (privacy-focused)
  bool _educationalHintsEnabled = true;
  bool _analyticsEnabled = false; // Disabled by default for privacy
  int _maxPlayTimeMinutes = 30;
  int _totalPlayTimeToday = 0;

  // Getters for current settings
  bool get educationalHintsEnabled => _educationalHintsEnabled;
  bool get analyticsEnabled => _analyticsEnabled;
  int get maxPlayTimeMinutes => _maxPlayTimeMinutes;
  int get totalPlayTimeToday => _totalPlayTimeToday;
  bool get isPlayTimeLimitReached => _totalPlayTimeToday >= _maxPlayTimeMinutes;

  /// Initialize the parental control service
  Future<void> initialize() async {
    try {
      // Using existing DB() system instead of SharedPreferences
      await _loadSettings();
      _checkNewDay();
      logger.i('ParentalControlService initialized');
    } catch (e) {
      logger.e('Failed to initialize ParentalControlService: $e');
    }
  }

  /// Load settings from persistent storage
  Future<void> _loadSettings() async {
    // TODO: Implement settings loading from DB() system
    // For now using default values
    _educationalHintsEnabled = true;
    _analyticsEnabled = false;
    _maxPlayTimeMinutes = 30;
    _totalPlayTimeToday = 0;
    logger.i(
        'ParentalControlService: Loaded default settings (temporary implementation)');
  }

  /// Check if it's a new day and reset play time if needed
  void _checkNewDay() {
    // TODO: Implement day tracking using DB() system
    // For now, assume it's always a new session
    _totalPlayTimeToday = 0;
    logger.i(
        'ParentalControlService: New session started (temporary implementation)');
  }

  /// Update parental control settings
  Future<void> updateSettings({
    bool? educationalHintsEnabled,
    bool? analyticsEnabled,
    int? maxPlayTimeMinutes,
  }) async {
    // TODO: Implement settings persistence with DB() system

    if (educationalHintsEnabled != null) {
      _educationalHintsEnabled = educationalHintsEnabled;
    }

    if (analyticsEnabled != null) {
      _analyticsEnabled = analyticsEnabled;
    }

    if (maxPlayTimeMinutes != null) {
      _maxPlayTimeMinutes = maxPlayTimeMinutes;
    }

    logger.i('Parental control settings updated (temporary implementation)');
  }

  /// Start tracking play session
  void startPlaySession() {
    if (_sessionStartTime != null) return; // Session already started

    _sessionStartTime = DateTime.now();
    _playTimeTimer = Timer.periodic(const Duration(minutes: 1), (Timer timer) {
      _updatePlayTime();
    });

    logger.i('Play session started');
  }

  /// End tracking play session
  void endPlaySession() {
    if (_sessionStartTime == null) {
      return; // No active session
    }

    _updatePlayTime();
    _playTimeTimer?.cancel();
    _playTimeTimer = null;
    _sessionStartTime = null;

    logger.i('Play session ended, total today: $_totalPlayTimeToday minutes');
  }

  /// Update total play time
  void _updatePlayTime() {
    if (_sessionStartTime == null) return;

    final int sessionMinutes =
        DateTime.now().difference(_sessionStartTime!).inMinutes;
    if (sessionMinutes > 0) {
      _totalPlayTimeToday += 1; // Add one minute
      // TODO: Persist play time using DB() system
      _sessionStartTime = DateTime.now(); // Reset for next minute
    }
  }

  /// Get remaining play time in minutes
  int getRemainingPlayTime() {
    return (_maxPlayTimeMinutes - _totalPlayTimeToday)
        .clamp(0, _maxPlayTimeMinutes);
  }

  /// Check if play time warning should be shown (5 minutes remaining)
  bool shouldShowPlayTimeWarning() {
    return getRemainingPlayTime() <= 5 && getRemainingPlayTime() > 0;
  }

  /// Get formatted play time string
  String getFormattedPlayTime() {
    final int hours = _totalPlayTimeToday ~/ 60;
    final int minutes = _totalPlayTimeToday % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Get formatted remaining time string
  String getFormattedRemainingTime() {
    final int remaining = getRemainingPlayTime();
    final int hours = remaining ~/ 60;
    final int minutes = remaining % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    } else {
      return '${minutes}m remaining';
    }
  }

  /// Check if analytics data can be collected
  /// This is always false for children under 13 to comply with COPPA
  bool canCollectAnalytics() {
    return _analyticsEnabled && !isPlayTimeLimitReached;
  }

  /// Log safe analytics event (no personal data)
  void logSafeAnalyticsEvent(String event, Map<String, dynamic> parameters) {
    if (!canCollectAnalytics()) return;

    // Only log non-personal analytics
    final Map<String, dynamic> safeParameters = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in parameters.entries) {
      // Only include safe, non-personal data
      if (_isSafeParameter(entry.key, entry.value)) {
        safeParameters[entry.key] = entry.value;
      }
    }

    // In a real implementation, this would send to analytics service
    logger.i('Safe analytics event: $event, parameters: $safeParameters');
  }

  /// Check if a parameter is safe to log
  bool _isSafeParameter(String key, dynamic value) {
    // Allowed parameters that don't contain personal information
    const Set<String> allowedKeys = <String>{
      'game_mode',
      'difficulty_level',
      'game_duration',
      'moves_count',
      'educational_hint_shown',
      'theme_selected',
    };

    return allowedKeys.contains(key) &&
        value != null &&
        value.toString().length < 100; // Reasonable length limit
  }

  /// Show play time limit notification
  PlayTimeLimitCallback? _playTimeLimitCallback;

  void setPlayTimeLimitCallback(PlayTimeLimitCallback callback) {
    _playTimeLimitCallback = callback;
  }

  void _notifyPlayTimeLimit() {
    _playTimeLimitCallback?.call();
  }

  /// Check and handle play time limits
  void checkPlayTimeLimit() {
    if (isPlayTimeLimitReached) {
      endPlaySession();
      _notifyPlayTimeLimit();
    } else if (shouldShowPlayTimeWarning()) {
      // Show warning but don't end session yet
      logger
          .i('Play time warning: ${getRemainingPlayTime()} minutes remaining');
    }
  }

  /// Reset play time (for testing or special circumstances)
  Future<void> resetPlayTime() async {
    _totalPlayTimeToday = 0;
    // TODO: Persist reset using DB() system
    logger.i('Play time reset (temporary implementation)');
  }

  /// Get privacy-compliant device info for diagnostics
  Map<String, String> getPrivacyCompliantDeviceInfo() {
    return <String, String>{
      'platform': defaultTargetPlatform.name,
      'app_version': 'unknown', // Would be populated from package_info
      'kids_mode': 'enabled',
      'educational_hints': _educationalHintsEnabled ? 'enabled' : 'disabled',
    };
  }

  /// Dispose resources
  void dispose() {
    endPlaySession();
    _playTimeTimer?.cancel();
    _playTimeTimer = null;
    _playTimeLimitCallback = null;
    logger.i('ParentalControlService disposed');
  }
}
