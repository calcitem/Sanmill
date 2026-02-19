// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// replay_service.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/recording_models.dart';
import 'recording_service.dart';

/// Supported playback speed multipliers.
enum ReplaySpeed {
  x1(1.0, '1×'),
  x2(2.0, '2×'),
  x4(4.0, '4×'),
  x8(8.0, '8×');

  const ReplaySpeed(this.multiplier, this.label);
  final double multiplier;
  final String label;
}

/// The current state of the replay engine.
enum ReplayState { idle, playing, paused, finished }

/// Service that replays a previously recorded [RecordingSession].
///
/// Before dispatching events the service pops the navigation stack back to the
/// root route (game page) so that [TapHandler] and all other UI code operate
/// against a valid, mounted [BuildContext].  The live context is obtained from
/// [currentNavigatorKey] on each event to avoid stale-context issues that arise
/// when the caller's widget has already been disposed.
///
/// Callers observe state changes through [stateNotifier], [progressNotifier],
/// and [speedNotifier] so the UI can update reactively.
class ReplayService {
  factory ReplayService() => _instance;

  ReplayService._internal();

  static final ReplayService _instance = ReplayService._internal();

  static const String _logTag = '[ReplayService]';

  // -----------------------------------------------------------------------
  // Observable state
  // -----------------------------------------------------------------------

  final ValueNotifier<ReplayState> stateNotifier = ValueNotifier<ReplayState>(
    ReplayState.idle,
  );

  /// Current event index (0-based). -1 when idle.
  final ValueNotifier<int> progressNotifier = ValueNotifier<int>(-1);

  /// Total number of events in the loaded session.
  final ValueNotifier<int> totalEventsNotifier = ValueNotifier<int>(0);

  final ValueNotifier<ReplaySpeed> speedNotifier = ValueNotifier<ReplaySpeed>(
    ReplaySpeed.x1,
  );

  ReplayState get state => stateNotifier.value;
  bool get isPlaying => state == ReplayState.playing;
  bool get isPaused => state == ReplayState.paused;

  // -----------------------------------------------------------------------
  // Internal state
  // -----------------------------------------------------------------------

  RecordingSession? _session;
  int _currentIndex = 0;
  Completer<void>? _pauseCompleter;
  bool _stopRequested = false;

  // Settings backup for restoration after replay.
  GeneralSettings? _backupGeneralSettings;
  RuleSettings? _backupRuleSettings;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Loads a session and starts playback.
  ///
  /// The method restores the session's initial settings snapshot, resets the
  /// game, and begins dispatching events sequentially.  Returns when replay
  /// completes or is stopped.
  ///
  /// The caller is responsible for navigating back to the game page BEFORE
  /// invoking this method so that [currentNavigatorKey.currentContext] resolves
  /// to a valid game-page context.  [SessionListPage._replaySession] handles
  /// this by calling [Navigator.popUntil] with a short post-navigation delay.
  Future<void> startReplay(RecordingSession session) async {
    assert(state == ReplayState.idle, 'Cannot start replay while active.');

    _session = session;
    _currentIndex = 0;
    _stopRequested = false;

    totalEventsNotifier.value = session.events.length;
    progressNotifier.value = 0;
    stateNotifier.value = ReplayState.playing;

    // Back up current settings so they can be restored after replay.
    _backupGeneralSettings = DB().generalSettings;
    _backupRuleSettings = DB().ruleSettings;

    // Suppress recording hooks during replay to prevent feedback loops.
    RecordingService().isSuppressed = true;

    // Restore the initial settings snapshot captured at recording time.
    _restoreSnapshot(session.initialSnapshot);

    // Reset the game board to a clean initial state.
    GameController().reset(force: true);

    logger.i(
      '$_logTag Replay started: ${session.id} '
      '(${session.events.length} events)',
    );

    // Dispatch events sequentially.
    await _dispatchEvents();

    // Finalise.
    if (!_stopRequested) {
      stateNotifier.value = ReplayState.finished;
      logger.i('$_logTag Replay finished: ${session.id}');
    }
  }

  /// Pauses the ongoing replay.
  void pause() {
    if (state != ReplayState.playing) {
      return;
    }
    stateNotifier.value = ReplayState.paused;
    _pauseCompleter = Completer<void>();
    logger.i('$_logTag Replay paused at event $_currentIndex');
  }

  /// Resumes a paused replay.
  void resume() {
    if (state != ReplayState.paused) {
      return;
    }
    stateNotifier.value = ReplayState.playing;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    logger.i('$_logTag Replay resumed at event $_currentIndex');
  }

  /// Stops the replay and restores original settings.
  void stop() {
    _stopRequested = true;
    if (state == ReplayState.paused) {
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
    _cleanup();
    logger.i('$_logTag Replay stopped');
  }

  /// Returns the current playback speed.
  ReplaySpeed get speed => speedNotifier.value;

  /// Changes the playback speed.
  set speed(ReplaySpeed value) {
    speedNotifier.value = value;
  }

  // -----------------------------------------------------------------------
  // Event dispatch loop
  // -----------------------------------------------------------------------

  Future<void> _dispatchEvents() async {
    final List<RecordingEvent> events = _session!.events;

    while (_currentIndex < events.length && !_stopRequested) {
      // Honour pause.
      if (state == ReplayState.paused) {
        await _pauseCompleter?.future;
        if (_stopRequested) {
          break;
        }
      }

      final RecordingEvent event = events[_currentIndex];

      // Compute inter-event delay scaled by the current speed multiplier.
      if (_currentIndex > 0) {
        final int deltaMs =
            event.timestampMs - events[_currentIndex - 1].timestampMs;
        final int scaledMs = (deltaMs / speedNotifier.value.multiplier).round();
        if (scaledMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: scaledMs));
        }
      }

      if (_stopRequested) {
        break;
      }

      // Apply the event.  _applyEvent is async because history navigation and
      // board taps require awaiting engine/state transitions.
      await _applyEvent(event); // ignore: use_build_context_synchronously

      progressNotifier.value = _currentIndex;
      _currentIndex++;
    }
  }

  /// Applies a single recorded event to the live game state.
  ///
  /// Uses [currentNavigatorKey.currentContext] as the live BuildContext so
  /// that the game-page context is always valid regardless of which widget
  /// originally triggered the replay.
  Future<void> _applyEvent(RecordingEvent event) async {
    // Obtain a fresh live context on every event application.
    // After [Navigator.popUntil] the root route is a game-page widget, so this
    // context is always mounted and correct for TapHandler / engine calls.
    final BuildContext? ctx = currentNavigatorKey.currentContext;

    switch (event.type) {
      case RecordingEventType.boardTap:
        final int? sq = event.data['sq'] as int?;
        if (sq != null && ctx != null) {
          await TapHandler(context: ctx).onBoardTap(sq);
        }

      case RecordingEventType.aiMove:
        // AI moves are the natural consequence of the preceding board-tap
        // event triggering the engine.  No explicit replay action needed.
        break;

      case RecordingEventType.settingsChange:
        _applySettingsChange(event.data);

      case RecordingEventType.gameReset:
        final bool force = event.data['force'] as bool? ?? false;
        final bool lanRestart = event.data['lanRestart'] as bool? ?? false;
        GameController().reset(force: force, lanRestart: lanRestart);

      case RecordingEventType.gameModeChange:
        // Mode changes are informational during replay; the initial snapshot
        // already contains the correct mode.
        break;

      case RecordingEventType.historyNavigation:
        // Replay the navigation so that take-back / step-forward sequences
        // produce the same board state as during the original session.
        await _applyHistoryNavigation(
          event.data['action'] as String? ?? '',
          event.data['steps'] as int?,
        );

      case RecordingEventType.gameOver:
        // Game-over events are the natural result of preceding moves.
        break;

      case RecordingEventType.undoMove:
        // An undo is equivalent to a single take-back step.
        await HistoryNavigator.doEachMove(HistoryNavMode.takeBack);
        logger.i('$_logTag Replay: applied undoMove as takeBack');

      case RecordingEventType.gameImport:
        // Restore the game recorder from the recorded PGN text.  The
        // subsequent historyNavigation events (takeBackAll + stepForwardAll)
        // will navigate the imported tree to the correct position.
        await _applyGameImport(event.data);

      case RecordingEventType.gameLoad:
        // Same approach as gameImport: restore the recorder from the stored
        // file content and let the following navigation events finish setup.
        await _applyGameLoad(event.data);

      case RecordingEventType.custom:
        // Custom events are extension points; no default action.
        break;
    }
  }

  // -----------------------------------------------------------------------
  // Event-type helpers
  // -----------------------------------------------------------------------

  /// Replays a history-navigation event by calling [HistoryNavigator.doEachMove]
  /// with the matching [HistoryNavMode].
  ///
  /// [actionStr] is the value stored in the event data, which is the result
  /// of [HistoryNavMode.toString()] (e.g. "HistoryNavMode.takeBack").
  Future<void> _applyHistoryNavigation(String actionStr, int? steps) async {
    // Strip the enum class name prefix if present ("HistoryNavMode.takeBack"
    // → "takeBack").
    String name = actionStr;
    final int dotIndex = actionStr.lastIndexOf('.');
    if (dotIndex != -1) {
      name = actionStr.substring(dotIndex + 1);
    }

    HistoryNavMode navMode;
    try {
      navMode = HistoryNavMode.values.firstWhere(
        (HistoryNavMode m) => m.name == name,
      );
    } catch (_) {
      logger.w(
        '$_logTag Replay: unknown historyNavigation action: "$actionStr"',
      );
      return;
    }

    await HistoryNavigator.doEachMove(navMode, steps);
    logger.i('$_logTag Replay: applied historyNavigation $name (steps=$steps)');
  }

  /// Restores the game recorder from a recorded PGN text payload so that the
  /// subsequent [historyNavigation] events operate on the imported tree.
  Future<void> _applyGameImport(Map<String, dynamic> data) async {
    final String? pgnText = data['pgnText'] as String?;
    final bool includeVariations = data['includeVariations'] as bool? ?? true;
    if (pgnText == null || pgnText.isEmpty) {
      logger.w('$_logTag Replay: gameImport event has no pgnText, skipping.');
      return;
    }
    try {
      ImportService.import(pgnText, includeVariations: includeVariations);
      logger.i('$_logTag Replay: applied gameImport');
    } catch (e) {
      logger.w('$_logTag Replay: gameImport failed: $e');
    }
  }

  /// Restores the game recorder from a recorded file-content payload so that
  /// the subsequent [historyNavigation] events operate on the loaded tree.
  Future<void> _applyGameLoad(Map<String, dynamic> data) async {
    final String? pgnContent = data['pgnContent'] as String?;
    final bool includeVariations = data['includeVariations'] as bool? ?? true;
    if (pgnContent == null || pgnContent.isEmpty) {
      logger.w('$_logTag Replay: gameLoad event has no pgnContent, skipping.');
      return;
    }
    try {
      ImportService.import(pgnContent, includeVariations: includeVariations);
      logger.i('$_logTag Replay: applied gameLoad');
    } catch (e) {
      logger.w('$_logTag Replay: gameLoad failed: $e');
    }
  }

  void _applySettingsChange(Map<String, dynamic> data) {
    final String category = data['category'] as String? ?? '';
    switch (category) {
      case 'general':
        final Map<String, dynamic>? settings =
            data['settings'] as Map<String, dynamic>?;
        if (settings != null) {
          DB().generalSettings = GeneralSettings.fromJson(settings);
        }
      case 'rule':
        final Map<String, dynamic>? settings =
            data['settings'] as Map<String, dynamic>?;
        if (settings != null) {
          DB().ruleSettings = RuleSettings.fromJson(settings);
        }
      // Display and color settings changes are cosmetic; applying them during
      // replay could be jarring, so they are intentionally skipped.
      default:
        break;
    }
  }

  // -----------------------------------------------------------------------
  // Snapshot restoration
  // -----------------------------------------------------------------------

  void _restoreSnapshot(Map<String, dynamic> snapshot) {
    try {
      final Map<String, dynamic>? general =
          snapshot['generalSettings'] as Map<String, dynamic>?;
      if (general != null) {
        DB().generalSettings = GeneralSettings.fromJson(general);
      }

      final Map<String, dynamic>? rules =
          snapshot['ruleSettings'] as Map<String, dynamic>?;
      if (rules != null) {
        DB().ruleSettings = RuleSettings.fromJson(rules);
      }
    } catch (e) {
      logger.w('$_logTag Snapshot restore error: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  void _cleanup() {
    // Re-enable recording hooks.
    RecordingService().isSuppressed = false;

    // Restore the settings that were active before replay started.
    if (_backupGeneralSettings != null) {
      DB().generalSettings = _backupGeneralSettings!;
      _backupGeneralSettings = null;
    }
    if (_backupRuleSettings != null) {
      DB().ruleSettings = _backupRuleSettings!;
      _backupRuleSettings = null;
    }

    _session = null;
    _currentIndex = 0;
    _pauseCompleter = null;
    _stopRequested = false;
    stateNotifier.value = ReplayState.idle;
    progressNotifier.value = -1;
    totalEventsNotifier.value = 0;
  }
}
