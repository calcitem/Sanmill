// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
    final GameController controller = GameController();

    // Preserve previous state to detect changes
    final bool prevHasResult = _hasResult;

    // Read terminal state from the native session outcome.  The
    // legacy `Position` mirror is gone with the rule-machine
    // cleanup; pre-session-bind reads simply see "not terminal".
    final platform.GameOutcome? nativeOutcome =
        controller.activeSessionSnapshot?.outcome;
    _hasResult = nativeOutcome?.isTerminal ?? false;
    // Prefer the session outcome winner: it distinguishes a draw
    // (mapped to `PieceColor.draw`) and reflects forced terminals
    // (resignation / timeout) that the board-view winner byte does not
    // carry.  Fall back to the board-view winner only pre-session-bind.
    _winner =
        controller.activeSessionWinner ?? controller.activeBoardView.winner;
    // The granular reason is published on the session snapshot by the
    // Rust engine and by `GameController.forceGameOver`.
    _reason = controller.activeSessionGameOverReason;

    // If a game result is newly detected, tally the score and update
    // ratings exactly once for this terminal transition.
    if (_hasResult && !prevHasResult) {
      _tallyScore();
      _updateRatings();

      // Record game over event for experience recording.
      RecordingService().recordEvent(
        RecordingEventType.gameOver,
        <String, dynamic>{
          'winner': _winner?.string ?? '',
          'reason': _reason?.toString() ?? '',
        },
      );
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

  /// Increment the in-memory win / draw / loss tally for the finished game.
  ///
  /// Invoked only on the terminal transition so a single game counts once.
  /// The session outcome is the source of truth because it distinguishes a
  /// draw (mapped to [PieceColor.draw]); the board-view winner byte collapses
  /// draws to "nobody" and would otherwise drop them from the tally. Setup
  /// Position is skipped because it does not represent a played-out game.
  void _tallyScore() {
    if (GameController().gameInstance.gameMode == GameMode.setupPosition) {
      return;
    }

    final PieceColor? scored = GameController().activeSessionWinner;
    if (scored == PieceColor.white ||
        scored == PieceColor.black ||
        scored == PieceColor.draw) {
      millScore[scored!] = (millScore[scored] ?? 0) + 1;
    }
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
      _winner ?? PieceColor.none,
      GameController().gameInstance.gameMode,
    );
  }
}
