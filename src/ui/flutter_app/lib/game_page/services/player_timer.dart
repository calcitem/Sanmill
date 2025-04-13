// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// player_timer.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import 'mill.dart';

/// PlayerTimer
///
/// Handles the time limit for human player moves.
/// If a player exceeds their time limit, they lose the game.
class PlayerTimer {
  // Singleton pattern
  factory PlayerTimer() => instance;

  PlayerTimer._();

  static final PlayerTimer instance = PlayerTimer._();

  // Timer instance
  Timer? _timer;

  // Current time remaining for the player (in seconds)
  int _remainingTime = 0;

  // Callback to update UI with the remaining time
  final ValueNotifier<int> remainingTimeNotifier = ValueNotifier<int>(0);

  // Flag to indicate if timer is active
  bool _isActive = false;

  /// Start the timer for a player's move
  void start() {
    final GameController gameController = GameController();

    // Skip timer for LAN mode
    if (gameController.gameInstance.gameMode == GameMode.humanVsLAN) {
      return;
    }

    // Skip timer entirely for AI vs AI mode
    if (gameController.gameInstance.gameMode == GameMode.aiVsAi) {
      _isActive = false; // Ensure timer is marked as inactive
      remainingTimeNotifier.value = 0; // Reset displayed time
      return;
    }

    // Check if this is the first move of the game - don't start timer in that case
    if (gameController.gameRecorder.mainlineMoves.isEmpty) {
      return;
    }

    // For AI with moveTime=0, we should not start an actual countdown timer
    // Instead, we'll just update the UI to show "-" indicating unlimited time
    final bool isAiWithUnlimitedTime =
        gameController.gameInstance.isAiSideToMove &&
            DB().generalSettings.moveTime <= 0;
    if (isAiWithUnlimitedTime) {
      // Just update the UI to show "-" via the notifier, but don't start a real timer
      _remainingTime = 0;
      remainingTimeNotifier.value = 0;
      _isActive = false;
      return;
    }

    // Stop any existing timer
    _timer?.cancel();

    // Get the time limit from settings based on the current player
    final bool isAiTurn = gameController.gameInstance.isAiSideToMove;
    final int timeLimit = isAiTurn
        ? DB().generalSettings.moveTime
        : DB().generalSettings.humanMoveTime;

    // If no time limit is set (value is 0) for human, don't start the timer
    if (timeLimit <= 0) {
      return;
    }

    // Initialize timer values
    _remainingTime = timeLimit;
    remainingTimeNotifier.value = _remainingTime;
    _isActive = true;

    // Start a periodic timer that ticks every second
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  /// Stop the timer (when a move is completed)
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
  }

  /// Reset the timer (e.g., when starting a new game)
  void reset() {
    stop();
    _remainingTime = 0;
    remainingTimeNotifier.value = 0;
  }

  /// Called every second to update the timer
  void _tick(Timer timer) {
    // Get the current game controller and position
    final GameController gameController = GameController();
    final Position position = gameController.position;

    // Check if AI is currently thinking
    final bool isAIThinking = gameController.gameInstance.isAiSideToMove &&
        gameController.isEngineRunning;

    // Count down if time is remaining
    if (_remainingTime > 0) {
      _remainingTime--;
      remainingTimeNotifier.value = _remainingTime;

      // For AI players, we don't want to check for timeout while engine is running
      if (isAIThinking) {
        return;
      }
    } else if (_remainingTime <= 0) {
      // Time is over, player loses
      stop();

      // Only declare timeout loss for human players, not AI or LAN opponents
      final bool isLanMode =
          gameController.gameInstance.gameMode == GameMode.humanVsLAN;
      final bool isHumanPlayer = !gameController.gameInstance.isAiSideToMove;
      final bool isAIWithUnlimitedTime =
          gameController.gameInstance.isAiSideToMove &&
              DB().generalSettings.moveTime <= 0;
      // Check if human player has unlimited time setting
      final bool isHumanWithUnlimitedTime =
          !gameController.gameInstance.isAiSideToMove &&
              DB().generalSettings.humanMoveTime <= 0;

      // For AI with unlimited time (moveTime=0), LAN mode, or when AI is playing,
      // or for human with unlimited time (humanMoveTime=0),
      // just update the display but don't set game over
      if (isLanMode ||
          !isHumanPlayer ||
          isAIWithUnlimitedTime ||
          isHumanWithUnlimitedTime) {
        _remainingTime = 0;
        remainingTimeNotifier.value = 0;

        // Restart timer for AI player if not in unlimited time mode
        // This ensures continuous timing for consecutive AI moves
        if (!isHumanPlayer && !isAIWithUnlimitedTime && !isLanMode) {
          // Restart the timer for the next move with proper time
          final int timeLimit = DB().generalSettings.moveTime;
          if (timeLimit > 0) {
            _remainingTime = timeLimit;
            remainingTimeNotifier.value = _remainingTime;
            _isActive = true;
            _timer = Timer.periodic(const Duration(seconds: 1), _tick);
          }
        }

        return;
      }

      // For human player in non-LAN mode
      // Set game over with current player as loser
      position.setGameOver(
        position.sideToMove.opponent,
        GameOverReason.loseTimeout,
      );

      // Update UI
      gameController.headerTipNotifier.showTip(
          "Time is over, ${position.sideToMove == PieceColor.white ? 'Player 1' : 'Player 2'} lost.");
      gameController.gameResultNotifier.showResult(force: true);

      // Play sound
      SoundManager().playTone(Sound.lose);
    }
  }

  /// Check if the timer is currently active
  bool get isActive => _isActive;

  /// Get the current remaining time
  int get remainingTime => _remainingTime;
}
