// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// player_timer.dart

import 'package:flutter/material.dart';

enum PlayerTimerStatus { stopped, running, paused }

/// Compatibility state for the retired per-move clock.
///
/// Ordinary games are untimed. Existing controller call sites may still start
/// or stop this singleton while older saved preferences retain their clock
/// values, but those calls never start a countdown or decide a game result.
class PlayerTimer {
  // Singleton pattern
  factory PlayerTimer() => instance;

  PlayerTimer._();

  static final PlayerTimer instance = PlayerTimer._();

  int _remainingTime = 0;

  // Callback to update UI with the remaining time
  final ValueNotifier<int> remainingTimeNotifier = ValueNotifier<int>(0);

  final ValueNotifier<PlayerTimerStatus> statusNotifier =
      ValueNotifier<PlayerTimerStatus>(PlayerTimerStatus.stopped);

  PlayerTimerStatus _status = PlayerTimerStatus.stopped;

  void _setStatus(PlayerTimerStatus status) {
    _status = status;
    statusNotifier.value = status;
  }

  /// Keeps legacy start calls inert because ordinary games are untimed.
  void start() {
    reset();
  }

  /// Stop the timer (when a move is completed)
  void stop() {
    _setStatus(PlayerTimerStatus.stopped);
  }

  /// Retained for source compatibility with older clock controls.
  void pause() {
    reset();
  }

  /// Retained for source compatibility with older clock controls.
  void resume() {
    reset();
  }

  /// Reset the timer (e.g., when starting a new game)
  void reset() {
    stop();
    _remainingTime = 0;
    remainingTimeNotifier.value = 0;
  }

  /// Check if the timer is currently active
  bool get isActive => _status == PlayerTimerStatus.running;

  bool get isPaused => _status == PlayerTimerStatus.paused;

  PlayerTimerStatus get status => _status;

  /// Get the current remaining time
  int get remainingTime => _remainingTime;
}
