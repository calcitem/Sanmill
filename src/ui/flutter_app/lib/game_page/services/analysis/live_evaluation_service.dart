// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

part of '../mill.dart';

/// Immutable position input for one live evaluation pass.
@immutable
class LiveEvaluationPosition {
  const LiveEvaluationPosition({
    required this.fen,
    required this.rules,
    required this.activeSeat,
    required this.outcome,
    required this.isRemovalPending,
  });

  factory LiveEvaluationPosition.fromSession(NativeMillGameSession session) {
    final GameStateSnapshot snapshot = session.state.value;
    return LiveEvaluationPosition(
      fen: session.getFen(),
      rules: session.activeRuleSettings,
      activeSeat: snapshot.activeSeat,
      outcome: snapshot.outcome,
      isRemovalPending: LiveEvaluationService.isRemovalPending(snapshot),
    );
  }

  final String fen;
  final RuleSettings rules;
  final PlayerSeat activeSeat;
  final platform.GameOutcome outcome;
  final bool isRemovalPending;
}

/// Current state of the optional in-game live evaluation.
@immutable
class LiveEvaluationState {
  const LiveEvaluationState({
    required this.enabled,
    required this.isSearching,
    required this.whiteScore,
    required this.positionKey,
    required this.isRemovalPending,
    this.appliedAiMoveEvaluation,
  });

  static const LiveEvaluationState disabled = LiveEvaluationState(
    enabled: false,
    isSearching: false,
    whiteScore: null,
    positionKey: null,
    isRemovalPending: false,
  );

  final bool enabled;
  final bool isSearching;

  /// Position score from White's perspective, clamped to -100 through 100.
  final int? whiteScore;

  /// Full FEN of the position represented by [whiteScore].
  final String? positionKey;

  /// Whether the mover still owes one or more removals in this position.
  final bool isRemovalPending;

  /// Database source information for the AI move that produced this exact
  /// position. Human Database entries carry real W/D/L statistics; Perfect
  /// Database entries use [whiteScore] as a deterministic result.
  final AppliedAiMoveEvaluation? appliedAiMoveEvaluation;
}

/// Reduces progressive live evaluations into one graph point per complete
/// Mill turn.
///
/// A place or move that forms a mill creates a provisional point while the
/// removal is still owed. Further pending-removal positions replace that
/// point, and the first completed position after removal finalizes it in
/// place. Ordinary completed turns append one point.
class LiveAdvantageHistory {
  LiveAdvantageHistory(this.values);

  final List<int> values;

  bool _wasEnabled = false;
  bool _waitingForInitialScore = false;
  bool _hasProvisionalPoint = false;
  String? _lastPositionKey;

  bool update(LiveEvaluationState state, {required int fallbackScore}) {
    bool changed = false;
    if (!state.enabled) {
      _wasEnabled = false;
      _waitingForInitialScore = false;
      _hasProvisionalPoint = false;
      _lastPositionKey = null;
      return false;
    }

    if (!_wasEnabled) {
      _wasEnabled = true;
      _waitingForInitialScore = true;
      _hasProvisionalPoint = false;
      _lastPositionKey = null;
      values
        ..clear()
        ..add(fallbackScore.clamp(-100, 100));
      changed = true;
    }

    final int? score = state.whiteScore;
    final String? positionKey = state.positionKey;
    if (score == null || positionKey == null) {
      return changed;
    }

    if (_waitingForInitialScore) {
      values[values.length - 1] = score;
      _waitingForInitialScore = false;
      _hasProvisionalPoint = state.isRemovalPending;
      _lastPositionKey = positionKey;
      return true;
    }

    if (_lastPositionKey == positionKey) {
      values[values.length - 1] = score;
      _hasProvisionalPoint = state.isRemovalPending;
      return true;
    }

    if (state.isRemovalPending) {
      if (_hasProvisionalPoint) {
        values[values.length - 1] = score;
      } else {
        values.add(score);
      }
      _hasProvisionalPoint = true;
    } else if (_hasProvisionalPoint) {
      values[values.length - 1] = score;
      _hasProvisionalPoint = false;
    } else {
      values.add(score);
    }
    _lastPositionKey = positionKey;
    return true;
  }
}

typedef LiveEvaluationSearchOverride =
    Future<List<NativeMillPrincipalVariation>> Function(
      LiveEvaluationPosition position,
      GeneralSettings engineSettings,
      void Function(List<NativeMillPrincipalVariation> variations) onUpdate,
    );

/// Runs optional background evaluation for local games.
///
/// The native Mill engine exposes one process-wide search slot. This service
/// therefore follows a strict last-request-wins policy: a new position stops
/// and fully drains the previous pass before it starts. AI move search,
/// analysis, review, and board input use [stopAndWait] to join the same
/// protocol.
class LiveEvaluationService {
  LiveEvaluationService._();

  static const String _logTag = '[LiveEvaluationService]';
  static const int searchDepth = 64;
  static const int searchTimeMs = 6000;

  static final ValueNotifier<LiveEvaluationState> stateNotifier =
      ValueNotifier<LiveEvaluationState>(LiveEvaluationState.disabled);

  static int _generation = 0;
  static Future<void>? _activeSearch;

  @visibleForTesting
  static LiveEvaluationSearchOverride? debugSearchOverride;

  @visibleForTesting
  static VoidCallback? debugStopSearch;

  @visibleForTesting
  static GameMode? debugGameMode;

  static LiveEvaluationState get state => stateNotifier.value;

  static bool get enabled => state.enabled;

  static bool supportsMode(GameMode mode) => switch (mode) {
    GameMode.humanVsAi || GameMode.humanVsHuman || GameMode.aiVsAi => true,
    GameMode.setupPosition ||
    GameMode.puzzle ||
    GameMode.humanVsCloud ||
    GameMode.humanVsLAN ||
    GameMode.humanVsBluetooth ||
    GameMode.testViaLAN ||
    GameMode.analysis => false,
  };

  /// Keep live calculation aligned with the two presentation controls that
  /// consume it. No engine work is needed when both the gauge and graph are
  /// hidden.
  static Future<void> syncWithDisplayPreferences({
    required bool showIndicator,
    required bool showGraph,
  }) async {
    final bool shouldEnable =
        supportsMode(_currentMode) && (showIndicator || showGraph);
    if (shouldEnable) {
      if (!state.enabled) {
        enable();
      }
      return;
    }
    if (state.enabled) {
      await disableAndWait();
    }
  }

  static Future<void> syncWithStoredDisplaySettings() {
    final DisplaySettings settings = DB().displaySettings;
    return syncWithDisplayPreferences(
      showIndicator: settings.isPositionalAdvantageIndicatorShown,
      showGraph: settings.isAdvantageGraphShown,
    );
  }

  /// Enable evaluation for the current local game and immediately analyze its
  /// current position. This preference is intentionally session-only.
  static void enable() {
    final GameMode mode = _currentMode;
    assert(supportsMode(mode), 'Live evaluation requires a local game mode.');
    if (!supportsMode(mode) || state.enabled) {
      return;
    }
    stateNotifier.value = const LiveEvaluationState(
      enabled: true,
      isSearching: false,
      whiteScore: null,
      positionKey: null,
      isRemovalPending: false,
    );
    unawaited(requestCurrentPosition());
  }

  /// Disable live evaluation immediately, then drain any native search.
  static Future<void> disableAndWait() async {
    _generation++;
    stateNotifier.value = LiveEvaluationState.disabled;
    await _drainActiveSearch();
  }

  /// Stop the current pass without changing the session-level toggle.
  static Future<void> stopAndWait() async {
    final int generation = ++_generation;
    await _drainActiveSearch();
    if (generation != _generation || !state.enabled) {
      return;
    }
    final LiveEvaluationState current = state;
    stateNotifier.value = LiveEvaluationState(
      enabled: true,
      isSearching: false,
      whiteScore: current.whiteScore,
      positionKey: current.positionKey,
      isRemovalPending: current.isRemovalPending,
      appliedAiMoveEvaluation: current.appliedAiMoveEvaluation,
    );
  }

  /// Analyze the current local position when the engine is otherwise idle.
  static Future<void> requestCurrentPosition() async {
    if (!state.enabled || !supportsMode(_currentMode)) {
      return;
    }
    final GameController controller = GameController();
    if (controller.isEngineRunning) {
      return;
    }
    final NativeMillGameSession? session = controller.activeNativeMillSession;
    if (session == null) {
      return;
    }
    await _requestPosition(
      LiveEvaluationPosition.fromSession(session),
      appliedAiMoveEvaluation: session.lastAppliedAiMoveEvaluation,
    );
  }

  /// Publish evaluation work that an AI move source has already performed.
  /// This never starts a second engine search.
  static void publishAiRootEvaluation(
    NativeMillGameSession session,
    int whiteScore,
  ) {
    if (!state.enabled || !supportsMode(_currentMode)) {
      return;
    }
    final NativeMillGameSession? active =
        GameController().activeNativeMillSession;
    if (active != null && !identical(active, session)) {
      return;
    }
    final LiveEvaluationPosition position = LiveEvaluationPosition.fromSession(
      session,
    );
    _publishScore(position, whiteScore.clamp(-100, 100), isSearching: false);
  }

  /// Publish a terminal position without asking the engine for a legal move.
  static void publishTerminalPosition(NativeMillGameSession session) {
    if (!state.enabled || !session.outcome.isTerminal) {
      return;
    }
    final LiveEvaluationPosition position = LiveEvaluationPosition.fromSession(
      session,
    );
    _publishScore(
      position,
      terminalWhiteScore(position.outcome),
      isSearching: false,
    );
  }

  @visibleForTesting
  static Future<void> debugRequestPosition(
    LiveEvaluationPosition position, {
    AppliedAiMoveEvaluation? appliedAiMoveEvaluation,
  }) => _requestPosition(
    position,
    appliedAiMoveEvaluation: appliedAiMoveEvaluation,
  );

  @visibleForTesting
  static void debugEnableForMode(GameMode mode) {
    debugGameMode = mode;
    stateNotifier.value = const LiveEvaluationState(
      enabled: true,
      isSearching: false,
      whiteScore: null,
      positionKey: null,
      isRemovalPending: false,
    );
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await disableAndWait();
    debugSearchOverride = null;
    debugStopSearch = null;
    debugGameMode = null;
  }

  static int whitePerspectiveScore(PlayerSeat activeSeat, int rootScore) {
    assert(
      activeSeat != PlayerSeat.none,
      'Live evaluation requires an active player.',
    );
    return switch (activeSeat) {
      PlayerSeat.first => rootScore.clamp(-100, 100),
      PlayerSeat.second => (-rootScore).clamp(-100, 100),
      PlayerSeat.none => 0,
    };
  }

  @visibleForTesting
  static int terminalWhiteScore(platform.GameOutcome outcome) {
    return switch (outcome.kind) {
      platform.GameOutcomeKind.win => switch (outcome.winner) {
        PlayerSeat.first => 100,
        PlayerSeat.second => -100,
        PlayerSeat.none || null => 0,
      },
      platform.GameOutcomeKind.draw ||
      platform.GameOutcomeKind.abandoned ||
      platform.GameOutcomeKind.ongoing => 0,
    };
  }

  @visibleForTesting
  static bool isRemovalPending(GameStateSnapshot snapshot) {
    final Object? raw = snapshot.payload['tgfPayload'];
    return raw is List<int> && raw.length > 29 && (raw[28] > 0 || raw[29] > 0);
  }

  static GameMode get _currentMode =>
      debugGameMode ?? GameController().gameInstance.gameMode;

  static Future<void> _requestPosition(
    LiveEvaluationPosition position, {
    AppliedAiMoveEvaluation? appliedAiMoveEvaluation,
  }) async {
    if (!state.enabled || !supportsMode(_currentMode)) {
      return;
    }
    assert(position.fen.isNotEmpty, 'Live evaluation requires a full FEN.');
    if (position.fen.isEmpty) {
      return;
    }

    final int generation = ++_generation;
    await _drainActiveSearch();
    if (generation != _generation || !state.enabled) {
      return;
    }

    if (position.outcome.isTerminal) {
      _publishScore(
        position,
        terminalWhiteScore(position.outcome),
        isSearching: false,
      );
      return;
    }
    if (position.activeSeat == PlayerSeat.none) {
      return;
    }
    if (appliedAiMoveEvaluation != null) {
      _publishScore(
        position,
        appliedAiMoveEvaluation.whiteScore,
        isSearching: false,
        appliedAiMoveEvaluation: appliedAiMoveEvaluation,
      );
      return;
    }

    stateNotifier.value = LiveEvaluationState(
      enabled: true,
      isSearching: true,
      whiteScore: null,
      positionKey: position.fen,
      isRemovalPending: position.isRemovalPending,
    );

    final GeneralSettings engineSettings = _engineSettings();
    final Future<void> search = _runSearch(
      generation: generation,
      position: position,
      engineSettings: engineSettings,
    );
    _activeSearch = search;
    try {
      await search;
    } finally {
      if (identical(_activeSearch, search)) {
        _activeSearch = null;
      }
    }
  }

  static Future<void> _runSearch({
    required int generation,
    required LiveEvaluationPosition position,
    required GeneralSettings engineSettings,
  }) async {
    NativeMillGameSession? temporarySession;
    try {
      void publish(List<NativeMillPrincipalVariation> variations) {
        if (generation != _generation || !state.enabled || variations.isEmpty) {
          return;
        }
        final NativeMillPrincipalVariation best = variations.firstWhere(
          (NativeMillPrincipalVariation variation) => variation.rank == 1,
          orElse: () => variations.first,
        );
        _publishScore(
          position,
          whitePerspectiveScore(position.activeSeat, best.score),
          isSearching: true,
        );
      }

      final LiveEvaluationSearchOverride? override = debugSearchOverride;
      final List<NativeMillPrincipalVariation> variations;
      if (override != null) {
        variations = await override(position, engineSettings, publish);
      } else {
        temporarySession = NativeMillGameSession(
          rules: position.rules,
          generalSettings: engineSettings,
        );
        final bool loaded = temporarySession.loadFen(position.fen);
        assert(loaded, 'Live-evaluation FEN must load in the search session.');
        if (!loaded) {
          return;
        }
        variations = await temporarySession.searchPrincipalVariations(
          depth: searchDepth,
          moveLimitMs: searchTimeMs,
          multiPv: 1,
          engineSettings: engineSettings,
          onUpdate: publish,
        );
      }
      if (generation != _generation || !state.enabled) {
        return;
      }
      if (variations.isNotEmpty) {
        publish(variations);
      }
      final LiveEvaluationState current = state;
      stateNotifier.value = LiveEvaluationState(
        enabled: true,
        isSearching: false,
        whiteScore: current.whiteScore,
        positionKey: position.fen,
        isRemovalPending: position.isRemovalPending,
      );
    } catch (error, stackTrace) {
      if (generation != _generation) {
        return;
      }
      logger.e('$_logTag Evaluation failed: $error', stackTrace: stackTrace);
      stateNotifier.value = LiveEvaluationState(
        enabled: true,
        isSearching: false,
        whiteScore: null,
        positionKey: position.fen,
        isRemovalPending: position.isRemovalPending,
      );
    } finally {
      temporarySession?.dispose();
    }
  }

  static void _publishScore(
    LiveEvaluationPosition position,
    int whiteScore, {
    required bool isSearching,
    AppliedAiMoveEvaluation? appliedAiMoveEvaluation,
  }) {
    stateNotifier.value = LiveEvaluationState(
      enabled: true,
      isSearching: isSearching,
      whiteScore: whiteScore.clamp(-100, 100),
      positionKey: position.fen,
      isRemovalPending: position.isRemovalPending,
      appliedAiMoveEvaluation: appliedAiMoveEvaluation,
    );
  }

  static Future<void> _drainActiveSearch() async {
    final Future<void>? active = _activeSearch;
    if (active == null) {
      return;
    }
    final VoidCallback? stopOverride = debugStopSearch;
    if (stopOverride != null) {
      stopOverride();
    } else {
      tgf.nativeMillSearchStop();
    }
    try {
      await active;
    } on Object {
      // The generation guard has already detached this cancelled pass. Its
      // failure was logged by _runSearch, so draining only needs to wait.
    }
  }

  static GeneralSettings _engineSettings() {
    return DB().generalSettings.copyWith(
      searchAlgorithm: SearchAlgorithm.pvs,
      aiIsLazy: false,
      skillLevel: 30,
      resignIfMostLose: false,
      shufflingEnabled: false,
      useLazySmp: false,
      engineThreads: 1,
    );
  }
}
