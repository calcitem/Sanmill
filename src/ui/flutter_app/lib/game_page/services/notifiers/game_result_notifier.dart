// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_result_notifier.dart

part of '../mill.dart';

/// The GameResultNotifier is responsible for detecting and notifying when a game has ended.
class GameResultNotifier extends ChangeNotifier {
  bool _hasResult = false;
  bool _isVisible = false;
  bool _force = false;
  GameOverReason? _reason;
  PieceColor? _winner;

  // Import elo service
  final EloRatingService _eloService = EloRatingService();

  /// Returns true if the notifier has a result.
  bool get hasResult => _hasResult;

  /// Returns true if the result should be displayed.
  bool get isVisible => _isVisible;

  /// Indicates whether the result display was forced.
  bool get force => _force;

  /// Returns the reason why the game ended.
  GameOverReason? get reason => _reason;

  /// Returns the winning player's color.
  PieceColor? get winner => _winner;

  /// Checks if there's a game result and shows it.
  ///
  /// [force] When true, it will show the result regardless of game state.
  void showResult({bool force = false}) {
    _force = force;
    final Position position = GameController().position;

    // Preserve previous state to detect changes
    final bool prevHasResult = _hasResult;

    // Update internal state based on current position
    _hasResult = position.hasGameResult;
    _winner = position.winner;
    _reason = position.reason;

    // If a game result is newly detected, update ratings once
    if (_hasResult && !prevHasResult) {
      _updateRatings();
    }

    // Mark the result panel as visible only when a result actually exists
    _isVisible = _hasResult;

    // Notify listeners in **all** cases. This keeps dependent widgets
    // (e.g. GameHeader) in sync even when the game is still ongoing.
    notifyListeners();
  }

  /// Hides the game result.
  void hideResult() {
    _isVisible = false;
    notifyListeners();
  }

  /// Clears the game result.
  void clearResult() {
    _hasResult = false;
    _isVisible = false;
    _winner = null;
    _reason = null;
    notifyListeners();
  }

  /// Update ELO ratings based on game result
  void _updateRatings() {
    // Skip if no result or in setup mode
    if (!_hasResult ||
        GameController().gameInstance.gameMode == GameMode.setupPosition) {
      return;
    }

    // Update the ELO ratings using the service
    _eloService.updateStats(
        _winner ?? PieceColor.none, GameController().gameInstance.gameMode);
  }
}
