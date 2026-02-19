// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// replay_service.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game_page/services/analysis_mode.dart';
import '../../game_page/services/annotation/annotation_manager.dart';
import '../../game_page/services/mill.dart';
import '../../game_page/services/transform/transform.dart';
import '../../general_settings/models/general_settings.dart';
import '../../general_settings/widgets/general_settings_page.dart';
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
  bool _useRecordedAiMoves = false;

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

    // Stop any ongoing recording to avoid confusing "REC" + replay UI overlap.
    await RecordingService().stopRecording(
      notes: 'Auto-stopped: replay started',
    );

    _session = session;
    _currentIndex = 0;
    _stopRequested = false;
    _useRecordedAiMoves = session.events.any(
      (RecordingEvent e) => e.type == RecordingEventType.aiMove,
    );

    totalEventsNotifier.value = session.events.length;
    progressNotifier.value = -1;
    stateNotifier.value = ReplayState.playing;

    // Back up current settings so they can be restored after replay.
    _backupGeneralSettings = DB().generalSettings;
    _backupRuleSettings = DB().ruleSettings;

    // Suppress recording hooks during replay to prevent feedback loops.
    RecordingService().isSuppressed = true;
    // Suppress automatic engine searches when we have recorded AI moves.
    GameController().isExperienceReplayActive = _useRecordedAiMoves;

    // Restore the initial settings snapshot captured at recording time.
    _restoreSnapshot(session.initialSnapshot);

    // Reset the game board to a clean initial state.
    GameController().reset(force: true);

    await _waitForControllerReady();

    // In legacy recordings without aiMove events, the engine is still needed
    // to advance AI turns. Kick it once if the session starts with AI to move.
    _kickLegacyAiIfNeeded();

    logger.i(
      '$_logTag Replay started: ${session.id} '
      '(${session.events.length} events)',
    );

    // Dispatch events sequentially.
    await _dispatchEvents();

    // Finalise.
    if (!_stopRequested) {
      logger.i('$_logTag Replay finished: ${session.id}');
      stateNotifier.value = ReplayState.finished;

      // Give the UI a moment to show "finished", then clean up automatically.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!_stopRequested && stateNotifier.value == ReplayState.finished) {
        _cleanup();
        _restartAutoRecordingIfEnabled();
      }
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
  void stop({bool restartRecording = true}) {
    _stopRequested = true;
    if (state == ReplayState.paused) {
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
    _cleanup();
    if (restartRecording) {
      _restartAutoRecordingIfEnabled();
    }
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

      if (_stopRequested) {
        break;
      }

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
        if (sq != null) {
          await _waitForControllerReady();
          if (!_useRecordedAiMoves) {
            await _waitForHumanTurn();
          }
          // Re-fetch context after the async wait to avoid stale-context
          // issues (use_build_context_synchronously).
          final BuildContext? freshCtx = currentNavigatorKey.currentContext;
          if (!_stopRequested && freshCtx != null) {
            // ignore: use_build_context_synchronously
            await TapHandler(context: freshCtx).onBoardTap(sq);
          }
        }

      case RecordingEventType.aiMove:
        if (_useRecordedAiMoves) {
          await _applyAiMove(event.data);
        }
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

      case RecordingEventType.toolbarAction:
        await _applyToolbarAction(event.data, ctx);

      case RecordingEventType.dialogAction:
        // Dialog selections are informational; their effects are captured by
        // subsequent gameReset / gameImport / gameLoad / settingsChange events.
        logger.i('$_logTag Replay: dialogAction ${event.data}');

      case RecordingEventType.navigationAction:
        await _applyNavigationAction(event.data, ctx);

      case RecordingEventType.annotationAction:
        _applyAnnotationAction(event.data);

      case RecordingEventType.setupPositionAction:
        _applySetupPositionAction(event.data, ctx);

      case RecordingEventType.custom:
        // Custom events are extension points; no default action.
        break;
    }
  }

  // -----------------------------------------------------------------------
  // Event-type helpers
  // -----------------------------------------------------------------------

  /// Polls until it is the human player's turn, then returns.
  ///
  /// After a [boardTap] triggers the AI engine, [isAiSideToMove] remains
  /// `true` until the engine finishes computing its response.  If the next
  /// [boardTap] event is dispatched before that happens the tap is silently
  /// ignored by [TapHandler.onBoardTap].  Polling here ensures each tap is
  /// delivered only when the game is ready to accept human input.
  ///
  /// The poll interval uses exponential back-off (50 ms → 500 ms) to avoid
  /// busy-waiting while remaining responsive.  A hard timeout of 60 s
  /// prevents an infinite loop if the engine hangs.
  Future<void> _waitForHumanTurn() async {
    const Duration maxWait = Duration(seconds: 60);
    const int minPollMs = 50;
    const int maxPollMs = 500;
    int pollMs = minPollMs;
    final Stopwatch sw = Stopwatch()..start();

    while (!_stopRequested) {
      final bool aiTurn = GameController().gameInstance.isAiSideToMove;
      final bool engineRunning = GameController().isEngineRunning;
      if (!aiTurn && !engineRunning) {
        break;
      }
      if (sw.elapsed >= maxWait) {
        logger.w(
          '$_logTag _waitForHumanTurn: timed out after ${maxWait.inSeconds}s '
          '(isAiSideToMove=$aiTurn, isEngineRunning=$engineRunning)',
        );
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: pollMs));
      pollMs = math.min(pollMs * 2, maxPollMs);
    }
  }

  Future<void> _waitForControllerReady() async {
    const Duration maxWait = Duration(seconds: 10);
    const int minPollMs = 20;
    const int maxPollMs = 250;
    int pollMs = minPollMs;
    final Stopwatch sw = Stopwatch()..start();

    while (!_stopRequested) {
      final bool ready = GameController().isControllerReady;
      final BuildContext? ctx = currentNavigatorKey.currentContext;
      if (ready && ctx != null) {
        break;
      }
      if (sw.elapsed >= maxWait) {
        logger.w(
          '$_logTag _waitForControllerReady: timed out after '
          '${maxWait.inSeconds}s (ready=$ready, ctx=${ctx != null})',
        );
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: pollMs));
      pollMs = math.min(pollMs * 2, maxPollMs);
    }
  }

  void _kickLegacyAiIfNeeded() {
    if (_useRecordedAiMoves) {
      return;
    }
    if (GameController().gameInstance.gameMode != GameMode.humanVsAi) {
      return;
    }
    if (!GameController().gameInstance.isAiSideToMove) {
      return;
    }

    final BuildContext? ctx = currentNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      logger.w('$_logTag Legacy AI kick skipped: no mounted context.');
      return;
    }
    unawaited(GameController().engineToGo(ctx, isMoveNow: false));
  }

  Future<void> _applyAiMove(Map<String, dynamic> data) async {
    final String? rawMove = data['move'] as String?;
    final String? rawSide = data['side'] as String?;

    if (rawMove == null || rawMove.trim().isEmpty) {
      logger.w('$_logTag Replay: aiMove has no move payload, skipping.');
      return;
    }

    final PieceColor? side = _parsePieceColor(rawSide);
    if (side == null) {
      logger.w(
        '$_logTag Replay: aiMove has unknown side "$rawSide", skipping.',
      );
      return;
    }

    final String move = rawMove.trim().toLowerCase();

    try {
      final ExtMove extMove = ExtMove(move, side: side);
      final bool ok = GameController().applyMove(extMove);
      assert(ok, 'Replay aiMove failed: $move (side=$side)');
      if (!ok) {
        logger.e('$_logTag Replay: aiMove failed: $move (side=$side)');
        stop();
      } else {
        logger.i('$_logTag Replay: applied aiMove $move (side=$side)');
      }
    } catch (e) {
      logger.e('$_logTag Replay: aiMove exception: $move (side=$side): $e');
      stop();
    }
  }

  PieceColor? _parsePieceColor(String? value) {
    if (value == null) {
      return null;
    }

    // Common encodings in recordings:
    // - PieceColor.string => "O" / "@"
    // - enum string => "PieceColor.white" / "PieceColor.black"
    // - plain text => "white" / "black"
    final String v = value.trim();
    if (v == PieceColor.white.string || v.toLowerCase().contains('white')) {
      return PieceColor.white;
    }
    if (v == PieceColor.black.string || v.toLowerCase().contains('black')) {
      return PieceColor.black;
    }
    if (v == PieceColor.none.string || v.toLowerCase().contains('none')) {
      return PieceColor.none;
    }
    return null;
  }

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

  /// Replays a toolbar button action.
  Future<void> _applyToolbarAction(
    Map<String, dynamic> data,
    BuildContext? ctx,
  ) async {
    final String action = data['action'] as String? ?? '';
    switch (action) {
      case 'moveNow':
        if (ctx != null) {
          await GameController().moveNow(ctx);
        }
        logger.i('$_logTag Replay: toolbarAction moveNow');

      case 'analysisOn':
        // Analysis mode is cosmetic; replay toggles it but skips the engine
        // call to avoid blocking the event loop.
        AnalysisMode.enable(<MoveAnalysisResult>[]);
        logger.i('$_logTag Replay: toolbarAction analysisOn (no engine call)');

      case 'analysisOff':
        AnalysisMode.disable();
        logger.i('$_logTag Replay: toolbarAction analysisOff');

      default:
        logger.w('$_logTag Replay: unknown toolbarAction: "$action"');
    }
  }

  /// Replays a page navigation event.
  ///
  /// Waits 300 ms after each push to let the route animation settle before
  /// the next event is dispatched.
  Future<void> _applyNavigationAction(
    Map<String, dynamic> data,
    BuildContext? ctx,
  ) async {
    if (ctx == null) {
      return;
    }
    final String page = data['page'] as String? ?? '';
    final String action = data['action'] as String? ?? '';

    if (action == 'push') {
      switch (page) {
        case '/generalSettings':
          Navigator.push(
            ctx,
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/generalSettings'),
              builder: (_) => const GeneralSettingsPage(),
            ),
          );

        case '/movesList':
          // MovesListPage is inside the game_page widget library; access via
          // currentNavigatorKey to avoid a circular import.
          logger.i(
            '$_logTag Replay: skip push /movesList (read-only during replay)',
          );

        case '/savedGames':
          logger.i(
            '$_logTag Replay: skip push /savedGames (read-only during replay)',
          );

        default:
          logger.w('$_logTag Replay: unknown push page: "$page"');
      }
      // Let the route animation complete before the next event.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } else if (action == 'pop') {
      Navigator.maybePop(ctx);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    logger.i('$_logTag Replay: navigationAction $action $page');
  }

  /// Replays an annotation toolbar action.
  void _applyAnnotationAction(Map<String, dynamic> data) {
    final String action = data['action'] as String? ?? '';
    final AnnotationManager manager = GameController().annotationManager;

    switch (action) {
      case 'selectTool':
        final String toolName = data['tool'] as String? ?? '';
        try {
          manager.currentTool = AnnotationTool.values.firstWhere(
            (AnnotationTool t) => t.name == toolName,
          );
        } catch (_) {
          logger.w('$_logTag Replay: unknown annotation tool: "$toolName"');
        }

      case 'selectColor':
        final int? colorValue = data['color'] as int?;
        if (colorValue != null) {
          manager.currentColor = Color(colorValue);
        }

      case 'undo':
        manager.undo();

      case 'redo':
        manager.redo();

      case 'clear':
        manager.clear();

      case 'enter':
      case 'exit':
      case 'screenshot':
        // Visual/IO actions; no state change needed during replay.
        break;

      default:
        logger.w('$_logTag Replay: unknown annotationAction: "$action"');
    }
    logger.i('$_logTag Replay: annotationAction $action');
  }

  /// Replays a setup-position toolbar action.
  ///
  /// Piece selection and phase changes update [GameController.position]
  /// directly so that subsequent [boardTap] events are interpreted correctly.
  void _applySetupPositionAction(Map<String, dynamic> data, BuildContext? ctx) {
    final String action = data['action'] as String? ?? '';
    final Position position = GameController().position;

    switch (action) {
      case 'selectPiece':
        final String value = data['value'] as String? ?? '';
        switch (value) {
          case 'white':
            position.sideToSetup = PieceColor.white;
            position.sideToMove = PieceColor.white;
            position.action = Act.place;
          case 'black':
            position.sideToSetup = PieceColor.black;
            position.sideToMove = PieceColor.black;
            position.action = Act.place;
          case 'marked':
            position.sideToSetup = PieceColor.marked;
            position.action = Act.place;
          case 'none':
            position.action = Act.remove;
        }

      case 'selectPhase':
        final String value = data['value'] as String? ?? '';
        if (value == 'placing') {
          position.phase = Phase.placing;
        } else if (value == 'moving') {
          position.phase = Phase.moving;
        }

      case 'transform':
        final String value = data['value'] as String? ?? '';
        TransformationType? type;
        switch (value) {
          case 'rotate90':
            type = TransformationType.rotate90;
          case 'mirrorHorizontal':
            type = TransformationType.mirrorHorizontal;
          case 'mirrorVertical':
            type = TransformationType.mirrorVertical;
          case 'innerOuterFlip':
            type = TransformationType.swap;
        }
        if (type != null) {
          final String? fen = position.fen;
          if (fen != null) {
            transformSquareSquareAttributeList(type);
            final String newFen = transformFEN(fen, type);
            position.setFen(newFen);
          }
        }

      case 'clear':
        position.reset();

      case 'setNeedRemove':
        // The need-remove count is widget state in SetupPositionToolbarState.
        // It does not directly affect GameController.position, so we skip it.
        break;

      case 'copy':
      case 'paste':
      case 'cancel':
        // Clipboard and cancel operations cannot be meaningfully replayed.
        break;

      default:
        logger.w('$_logTag Replay: unknown setupPositionAction: "$action"');
    }
    logger.i('$_logTag Replay: setupPositionAction $action');
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
    GameController().isExperienceReplayActive = false;

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
    _useRecordedAiMoves = false;
    stateNotifier.value = ReplayState.idle;
    progressNotifier.value = -1;
    totalEventsNotifier.value = 0;
  }

  void _restartAutoRecordingIfEnabled() {
    if (RecordingService().isSuppressed) {
      return;
    }
    if (!DB().generalSettings.experienceRecordingEnabled) {
      return;
    }
    if (RecordingService().isRecording) {
      return;
    }
    unawaited(
      RecordingService().startRecording(
        gameMode: GameController().gameInstance.gameMode.toString(),
      ),
    );
  }
}
