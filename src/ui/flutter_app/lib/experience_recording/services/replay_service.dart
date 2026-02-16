// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// replay_service.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/recording_models.dart';

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
/// The replay engine restores the initial configuration snapshot, then
/// sequentially dispatches recorded events with timing that respects the
/// original inter-event delays (scaled by [speed]).
///
/// Callers observe state changes through [stateNotifier], [progressNotifier],
/// and [speedNotifier] so UI can update reactively.
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
  /// game, and begins dispatching events. Returns when replay completes or
  /// is stopped.
  Future<void> startReplay(
    RecordingSession session, {
    BuildContext? context,
  }) async {
    assert(state == ReplayState.idle, 'Cannot start replay while active.');

    _session = session;
    _currentIndex = 0;
    _stopRequested = false;

    totalEventsNotifier.value = session.events.length;
    progressNotifier.value = 0;
    stateNotifier.value = ReplayState.playing;

    // Back up current settings.
    _backupGeneralSettings = DB().generalSettings;
    _backupRuleSettings = DB().ruleSettings;

    // Restore initial snapshot settings.
    _restoreSnapshot(session.initialSnapshot);

    // Reset game to match initial state.
    GameController().reset(force: true);

    logger.i(
      '$_logTag Replay started: ${session.id} '
      '(${session.events.length} events)',
    );

    // Dispatch events sequentially.
    await _dispatchEvents(context);

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

  Future<void> _dispatchEvents(BuildContext? context) async {
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

      // Compute delay to next event.
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

      // Dispatch the event. Context may be stale after an async gap,
      // but the replay engine only uses it for TapHandler which guards
      // against disposed contexts internally.
      _applyEvent(event, context); // ignore: use_build_context_synchronously

      progressNotifier.value = _currentIndex;
      _currentIndex++;
    }
  }

  /// Applies a single recorded event to the live game state.
  void _applyEvent(RecordingEvent event, BuildContext? context) {
    switch (event.type) {
      case RecordingEventType.boardTap:
        final int? sq = event.data['sq'] as int?;
        if (sq != null && context != null) {
          TapHandler(context: context).onBoardTap(sq);
        }

      case RecordingEventType.aiMove:
        // AI moves are the result of engine computation. During replay
        // the board tap that preceded the AI move will trigger the engine
        // automatically, so we do not need to apply the AI move explicitly.
        break;

      case RecordingEventType.settingsChange:
        _applySettingsChange(event.data);

      case RecordingEventType.gameReset:
        final bool force = event.data['force'] as bool? ?? false;
        final bool lanRestart = event.data['lanRestart'] as bool? ?? false;
        GameController().reset(force: force, lanRestart: lanRestart);

      case RecordingEventType.gameModeChange:
        // Mode changes are informational during replay; the initial
        // snapshot already sets the correct mode.
        break;

      case RecordingEventType.historyNavigation:
        // History navigation events are informational during replay.
        // The board state will be reconstructed by board tap events.
        logger.i('$_logTag Replay: history nav event (informational)');

      case RecordingEventType.gameOver:
        // Game over events are the natural result of preceding moves.
        break;

      case RecordingEventType.undoMove:
        // Undo events are informational during replay.
        logger.i('$_logTag Replay: undo event (informational)');

      case RecordingEventType.gameImport:
      case RecordingEventType.gameLoad:
        // Import/load events are informational; the move sequence
        // that follows will reconstruct the state.
        break;

      case RecordingEventType.custom:
        // Custom events are extension points; no default action.
        break;
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
      // Display and color settings changes are cosmetic; applying them
      // during replay could be jarring. We skip them by default.
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
    // Restore backed-up settings.
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
