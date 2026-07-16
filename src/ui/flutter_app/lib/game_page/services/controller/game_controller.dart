// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_controller.dart

part of '../mill.dart';

@immutable
class MoveNowMessages {
  const MoveNowMessages({
    required this.aiIsDelaying,
    required this.analyzing,
    required this.notAIsTurn,
    required this.timeout,
  });

  factory MoveNowMessages.of(BuildContext context) {
    final S strings = S.of(context);
    return MoveNowMessages(
      aiIsDelaying: strings.aiIsDelaying,
      analyzing: strings.analyzing,
      notAIsTurn: strings.notAIsTurn,
      timeout: strings.timeout,
    );
  }

  final String aiIsDelaying;
  final String analyzing;
  final String notAIsTurn;
  final String timeout;
}

/// Game Controller
///
/// A singleton class that holds all objects and methods needed to play Mill.
///
/// Controls:
/// * The tip [HeaderTipNotifier]
/// * The engine [Engine]
/// * The position [Position]
/// * The game instance [Game]
/// * The recorder [GameRecorder]
class GameController {
  @Deprecated('Use MillGameSession from games/mill/mill_game_session.dart.')
  factory GameController() => instance;

  GameController._() {
    _init(GameMode.humanVsAi);
  }

  static const String _logTag = "[Controller]";

  /// True while an experience replay session is actively driving the game.
  ///
  /// When enabled, UI-driven code should avoid automatically triggering
  /// engine searches (AI moves are applied by the replay engine instead).
  bool isExperienceReplayActive = false;

  RemoteMatchController? remoteCoordinator;
  Map<String, Object?>? _lastRemoteDiagnostics;
  // Canceled by disposeRemoteMatch before every coordinator replacement.
  // ignore: cancel_subscriptions
  StreamSubscription<RemoteMatchEvent>? _remoteMatchSubscription;

  bool isDisposed = false;
  bool isControllerReady = false;
  bool isControllerActive = false;
  bool _isEngineRunning = false;
  bool _isEngineInDelay = false;
  Completer<void>? _engineDelaySkipCompleter;

  final ValueNotifier<bool> engineActivityNotifier = ValueNotifier<bool>(false);

  bool get isEngineRunning => _isEngineRunning;

  set isEngineRunning(bool value) {
    if (_isEngineRunning == value) {
      return;
    }
    _isEngineRunning = value;
    _updateEngineActivityNotifier();
  }

  bool get isEngineInDelay => _isEngineInDelay;

  set isEngineInDelay(bool value) {
    if (_isEngineInDelay == value) {
      return;
    }
    _isEngineInDelay = value;
    _updateEngineActivityNotifier();
  }

  BuildContext _stableDialogContext(BuildContext fallbackContext) {
    final BuildContext? overlayContext =
        currentNavigatorKey.currentState?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) {
      return overlayContext;
    }

    final BuildContext? messengerContext =
        rootScaffoldMessengerKey.currentState?.context;
    if (messengerContext != null &&
        messengerContext.mounted &&
        Navigator.maybeOf(messengerContext) != null) {
      return messengerContext;
    }

    assert(
      fallbackContext.mounted,
      'Controller dialogs require a mounted context.',
    );
    return fallbackContext;
  }

  void _updateEngineActivityNotifier() {
    final bool isEngineActive = _isEngineRunning || _isEngineInDelay;
    if (engineActivityNotifier.value != isEngineActive) {
      engineActivityNotifier.value = isEngineActive;
    }
  }

  /// Monotonic counter incremented on every reset() so any in-flight
  /// AI loop (e.g. _nativeAiVsAiLoop) can detect that a New Game has
  /// happened underneath it and bail out cleanly.  Without this the
  /// previous loop continues racing with the freshly-spawned one,
  /// surfacing as 'AI vs AI New Game does nothing' when both loops
  /// trip over each other on isControllerActive / isEngineRunning.
  int aiLoopEpoch = 0;

  bool lastMoveFromAI = false;

  bool disableStats = false;

  // Puzzle mode state:
  // - puzzleHumanColor: which side the user controls when solving a puzzle.
  // - isPuzzleAutoMoveInProgress: prevents user input while the app auto-plays
  //   the opponent's forced responses.
  PieceColor? puzzleHumanColor;
  bool isPuzzleAutoMoveInProgress = false;

  String? value;
  AiMoveType? aiMoveType;

  late Game gameInstance;
  final ValueNotifier<GameStateSnapshot?> activeSessionSnapshotNotifier =
      ValueNotifier<GameStateSnapshot?>(null);

  GameStateSnapshot? get activeSessionSnapshot =>
      activeSessionSnapshotNotifier.value;

  NativeMillSnapshotBoardView? get activeNativeMillBoardView {
    final GameStateSnapshot? snapshot = activeSessionSnapshot;
    if (snapshot == null) {
      return null;
    }
    return NativeMillSnapshotBoardView.fromSnapshot(snapshot);
  }

  /// Returns a read-only [MillBoardView] for the current game state.
  ///
  /// Steady-state reads come from the native session snapshot.  The
  /// legacy `Position` is consulted only at very-early app startup
  /// before the first session has been bound (e.g. a widget rebuilds
  /// during `initState` before `bindActiveSession` runs).  Phase \u03b7
  /// drops the fallback altogether once `position.dart` is deleted.
  MillBoardView get activeBoardView {
    final GameStateSnapshot? snapshot = activeSessionSnapshot;
    if (snapshot != null) {
      final String? exportedFen = activeNativeMillSession?.getFen();
      final MillBoardView? view = MillBoardView.fromNativeSnapshot(
        snapshot,
        exportedFen,
      );
      if (view != null) {
        return view;
      }
    }
    return MillBoardView.empty();
  }

  /// Convenience FEN accessor.
  ///
  /// Reads from the native session when available; falls back to the
  /// legacy [Position.fen] getter otherwise.  Callers in the rendering
  /// and recording layers should prefer this over `position.fen` so that
  /// eventually [position.dart] can be deleted.
  String? get activeFen => activeBoardView.fen;

  /// Human-readable context for [EngineFailureDialog] error reports.
  ///
  /// Always includes the exported FEN (matching master-branch reports) plus
  /// phase, side to move, optional native Zobrist key, last move, and the
  /// mainline move list without variations.
  String buildEngineFailureDiagnosticContext(
    BuildContext context, {
    String? lastMove,
  }) {
    final MillBoardView view = activeBoardView;
    final String? fen = activeFen ?? activeNativeMillSession?.getFen();
    final String moveList = gameRecorder.moveHistoryTextWithoutVariations;
    return EngineFailureDialog.buildDiagnosticContext(
      fen: fen,
      phase: view.phase.name,
      sideToMove: view.sideToMove.playerName(context),
      zobrist: activeSessionSnapshot?.payload['tgfZobrist']?.toString(),
      lastMove: lastMove,
      moveList: moveList,
      failureDetails: activeNativeMillSession?.lastEngineFailureDetails,
    );
  }

  PieceColor? get activeSessionSideToMove {
    return switch (activeSessionSnapshot?.activeSeat) {
      PlayerSeat.first => PieceColor.white,
      PlayerSeat.second => PieceColor.black,
      PlayerSeat.none || null => null,
    };
  }

  Phase? get activeSessionPhase {
    final GameStateSnapshot? snapshot = activeSessionSnapshot;
    if (snapshot == null) {
      return null;
    }
    if (snapshot.outcome.isTerminal) {
      return Phase.gameOver;
    }
    return switch (snapshot.phase) {
      'ready' => Phase.ready,
      'placing' => Phase.placing,
      'moving' => Phase.moving,
      'gameOver' => Phase.gameOver,
      _ => null,
    };
  }

  PieceColor? get activeSessionWinner {
    final platform.GameOutcome? outcome = activeSessionSnapshot?.outcome;
    return switch (outcome?.kind) {
      platform.GameOutcomeKind.win => switch (outcome?.winner) {
        platform.PlayerSeat.first => PieceColor.white,
        platform.PlayerSeat.second => PieceColor.black,
        _ => PieceColor.nobody,
      },
      platform.GameOutcomeKind.draw => PieceColor.draw,
      platform.GameOutcomeKind.abandoned => PieceColor.nobody,
      platform.GameOutcomeKind.ongoing || null => null,
    };
  }

  /// The granular game-over reason for the current session snapshot, or
  /// null when the game is ongoing or the reason is unknown.
  ///
  /// The reason token is published by [NativeMillRulesPort] (from the Rust
  /// engine) and by [forceGameOver] (resignation / timeout) under
  /// [millOutcomeReasonPayloadKey]; it is decoded back to a
  /// [GameOverReason] via [gameOverReasonFromTgfReason].  Backs the result
  /// dialog and the detailed game-over SnackBar.
  GameOverReason? get activeSessionGameOverReason {
    final Object? raw =
        activeSessionSnapshot?.payload[millOutcomeReasonPayloadKey];
    return raw is String ? gameOverReasonFromTgfReason(raw) : null;
  }

  IconData get activeSideToMoveIcon {
    final PieceColor side =
        activeSessionSideToMove ?? activeBoardView.sideToMove;
    final platform.GameOutcome? outcome = activeSessionSnapshot?.outcome;
    if (outcome == null) {
      return side.icon;
    }
    if (!outcome.isTerminal) {
      return side._chevron;
    }
    return switch (outcome.kind) {
      platform.GameOutcomeKind.win => switch (outcome.winner) {
        platform.PlayerSeat.first => PieceColor.white._arrow,
        platform.PlayerSeat.second => PieceColor.black._arrow,
        _ => PieceColor.nobody._arrow,
      },
      platform.GameOutcomeKind.draw => PieceColor.draw._arrow,
      platform.GameOutcomeKind.abandoned ||
      platform.GameOutcomeKind.ongoing => PieceColor.nobody._arrow,
    };
  }

  set activeSessionSnapshot(GameStateSnapshot? snapshot) {
    activeSessionSnapshotNotifier.value = snapshot;
  }

  GameSession? _activeSession;

  /// Binds the session owned by the game shell so controller code that is not
  /// under the page [BuildContext] can still update the active native kernel.
  void bindActiveSession(GameSession session) {
    _activeSession = session;
    activeSessionSnapshot = session.state.value;
  }

  void unbindActiveSession(GameSession session) {
    if (!identical(_activeSession, session)) {
      return;
    }
    _activeSession = null;
    activeSessionSnapshot = null;
  }

  NativeMillGameSession? get activeNativeMillSession {
    final GameSession? session = _activeSession;
    return session is NativeMillGameSession ? session : null;
  }

  void syncAiMoveTypeFromSession(NativeMillGameSession session) {
    aiMoveType = session.lastAiMoveType;
    final int? bestValue = session.lastAiBestValue;
    value = bestValue?.toString();
    lastMoveFromAI =
        bestValue != null &&
        aiMoveType != null &&
        aiMoveType != AiMoveType.unknown;
    headerIconsNotifier.showIcons();
  }

  void refreshNativeSessionHeader(
    BuildContext context,
    NativeMillGameSession session, {
    bool showThinking = false,
  }) {
    final BuildContext effectiveContext =
        rootScaffoldMessengerKey.currentContext ?? context;
    assert(
      effectiveContext.mounted,
      'Native session header refresh requires a mounted context.',
    );
    if (!effectiveContext.mounted) {
      return;
    }

    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();

    if (session.outcome.isTerminal) {
      return;
    }

    // Master always shows the cumulative W-D-L tally in AI-vs-AI mode,
    // never turn prompts like "Please place".
    if (gameInstance.gameMode == GameMode.aiVsAi) {
      headerTipNotifier.showTip(millScoreString, snackBar: false);
      return;
    }

    // When enabled, surface the recognised opening (name + source) while the
    // game follows a known book line; append the current turn prompt so the
    // opening and actionable state remain visible as one header sentence.
    final String? openingTip = _openingInfoTip(effectiveContext, session);
    final String? turnTip = showThinking
        ? S.of(effectiveContext).thinking
        : _nativeSessionTurnTip(effectiveContext, session);
    if (openingTip != null) {
      headerTipNotifier.showTip(
        _joinHeaderTips(openingTip, turnTip),
        snackBar: false,
        kind: HeaderTipKind.openingInfo,
      );
      return;
    }

    if (turnTip != null) {
      headerTipNotifier.showTip(turnTip, snackBar: false);
    }
  }

  String _joinHeaderTips(String primary, String? secondary) {
    if (secondary == null || secondary.isEmpty) {
      return primary;
    }
    return '$primary; $secondary';
  }

  /// Builds the opening-information tip for [refreshNativeSessionHeader], or
  /// null when the feature is off, the variant is unsupported, or no named
  /// opening is currently recognised.
  String? _openingInfoTip(BuildContext context, NativeMillGameSession session) {
    if (!DB().generalSettings.showOpeningInfo) {
      return null;
    }
    final RuleSettings rules = DB().ruleSettings;
    final bool isElFilja = rules.isLikelyElFilja();
    if (!rules.isLikelyNineMensMorris() && !isElFilja) {
      return null;
    }
    final List<String> placements = openingBookPlacementHistory();
    if (placements.isEmpty) {
      return null;
    }
    final MillOpeningRecognition recognition = MillOpeningRecognizer.recognize(
      placements,
      OpeningBookRepository.instance.openingsFor(isElFilja: isElFilja),
    );
    if (!recognition.isNamed) {
      return null;
    }

    // Ambiguous shared start: several different families still fit the played
    // prefix (e.g. the common d2/d6/f4/b4 opening of Battle Lines and the Open
    // Z Mill). Show the family shortlist rather than committing to one name,
    // which previously surfaced the wrong opening until the lines diverged.
    if (recognition.status != MillOpeningStatus.deviation &&
        recognition.candidateFamilies.length > 1) {
      const int maxShown = 3;
      final List<String> families = recognition.candidateFamilies;
      final String shown = families.take(maxShown).join(' / ');
      final String suffix = families.length > maxShown ? ' \u2026' : '';
      return '${S.of(context).openingLabel}: $shown$suffix';
    }

    final String display =
        recognition.status == MillOpeningStatus.deviation &&
            (recognition.branchName?.isNotEmpty ?? false)
        ? recognition.branchName!
        : (recognition.name ?? '');
    if (display.isEmpty) {
      return null;
    }
    final StringBuffer buffer = StringBuffer(
      '${S.of(context).openingLabel}: $display',
    );
    final String reference = recognition.sourceReference ?? '';
    if (reference.isNotEmpty) {
      buffer.write(' ($reference)');
    }
    final String favourName = switch (recognition.favoredSide) {
      'W' => S.of(context).white,
      'B' => S.of(context).black,
      _ => '',
    };
    if (favourName.isNotEmpty) {
      buffer.write(' \u2022 ${S.of(context).openingFavours} $favourName');
    }
    if (recognition.commonBlunders.isNotEmpty) {
      buffer.write(
        ' \u2022 ${S.of(context).openingAvoid}: '
        '${recognition.commonBlunders.join(", ")}',
      );
    }
    final List<String> replies = _openingResponsesForSide(session, recognition);
    if (replies.isNotEmpty) {
      buffer.write(
        ' \u2022 ${S.of(context).openingReply}: ${replies.join(", ")}',
      );
    }
    return buffer.toString();
  }

  /// Recommended replies for the side currently to move, if the recognised
  /// opening lists any.
  List<String> _openingResponsesForSide(
    NativeMillGameSession session,
    MillOpeningRecognition recognition,
  ) {
    final String key = switch (session.state.value.activeSeat) {
      PlayerSeat.first => 'W',
      PlayerSeat.second => 'B',
      PlayerSeat.none => '',
    };
    return recognition.recommendedResponses[key] ?? const <String>[];
  }

  String? _nativeSessionTurnTip(
    BuildContext context,
    NativeMillGameSession session,
  ) {
    final GameStateSnapshot snapshot = session.state.value;
    final PieceColor side = switch (snapshot.activeSeat) {
      PlayerSeat.first => PieceColor.white,
      PlayerSeat.second => PieceColor.black,
      PlayerSeat.none => PieceColor.nobody,
    };
    if (side == PieceColor.nobody) {
      return null;
    }

    final String sideName = side.playerName(context);
    final MillBoardView? boardView = MillBoardView.fromNativeSnapshot(
      snapshot,
      session.getFen(),
    );
    final Phase phase = boardView?.phase ?? activeSessionPhase ?? Phase.placing;
    final Act action = boardView?.action ?? Act.place;
    final bool showSide =
        gameInstance.gameMode == GameMode.humanVsHuman ||
        gameInstance.gameMode == GameMode.analysis ||
        isRemoteGameMode;

    if (action == Act.remove) {
      return showSide
          ? "${S.of(context).tipToMove(sideName)} ${S.of(context).tipRemove}"
          : S.of(context).tipRemove;
    }

    if (phase == Phase.moving) {
      return showSide
          ? "${S.of(context).tipToMove(sideName)} ${S.of(context).tipMove}"
          : S.of(context).tipMove;
    }

    if (phase == Phase.placing) {
      if (showSide || ruleSettingsForActiveBoard.mayMoveInPlacingPhase) {
        return S.of(context).tipToMove(sideName);
      }
      return S.of(context).tipPlace;
    }

    return null;
  }

  // Game timing tracking
  DateTime? _gameStartTime;
  bool _gameStartTimeRecorded = false;

  final HeaderTipNotifier headerTipNotifier = HeaderTipNotifier();
  final HeaderIconsNotifier headerIconsNotifier = HeaderIconsNotifier();
  final GameResultNotifier gameResultNotifier = GameResultNotifier();
  final BoardSemanticsNotifier boardSemanticsNotifier =
      BoardSemanticsNotifier();
  final SetupPositionNotifier setupPositionNotifier = SetupPositionNotifier();

  /// Active setup-position editor, or null when not in setup mode.  Owned
  /// by the controller while [GameMode.setupPosition] is active.
  MillSetupPositionController? setupPositionController;

  /// Game mode to restore when leaving the setup-position editor.
  GameMode? _setupPreviousMode;

  late GameRecorder gameRecorder;
  GameRecorder? newGameRecorder;

  // Add a new boolean to track annotation mode:
  bool isAnnotationMode = false;

  final AnnotationManager annotationManager = AnnotationManager();

  String? _initialSharingMoveList;
  ValueNotifier<String?> initialSharingMoveListNotifier =
      ValueNotifier<String?>(null);

  String? get initialSharingMoveList => _initialSharingMoveList;

  set initialSharingMoveList(String? list) {
    _initialSharingMoveList = list;
    initialSharingMoveListNotifier.value = list;
  }

  String? loadedGameFilenamePrefix;

  /// Absolute path of the saved game backing the current in-memory session.
  ///
  /// The shell uses this identity to replace the source card with the live
  /// preview instead of presenting the same game twice.
  String? loadedGameSourcePath;
  String? _claimedLoadedAiTurnResumeKey;

  /// Claims the current loaded AI turn exactly once for automatic resume.
  ///
  /// The claim is reset with the game session. Repeated widget rebuilds or
  /// navigation callbacks for the same loaded position therefore cannot
  /// launch concurrent searches.
  bool claimLoadedAiTurnResume(String sourceIdentity) {
    assert(sourceIdentity.isNotEmpty, 'Loaded-game identity cannot be empty.');
    final GameStateSnapshot? snapshot = activeSessionSnapshot;
    if (gameInstance.gameMode != GameMode.humanVsAi ||
        snapshot == null ||
        snapshot.outcome.isTerminal ||
        isEngineRunning) {
      return false;
    }
    final PieceColor? sideToMove = activeSessionSideToMove;
    if (sideToMove == null || !gameInstance.getPlayerByColor(sideToMove).isAi) {
      return false;
    }
    final String key = <Object?>[
      sourceIdentity,
      snapshot.phase,
      snapshot.activeSeat.name,
      gameRecorder.moveCountNotifier.value,
      activeFen,
    ].join('|');
    if (_claimedLoadedAiTurnResumeKey == key) {
      return false;
    }
    _claimedLoadedAiTurnResumeKey = key;
    return true;
  }

  AnimationManager? _animationManager;

  /// True once a [GameBoard] has assigned [animationManager] at least once
  /// this session. History navigation can run before any board has ever
  /// mounted (e.g. loading a saved game from the Home tab, which replays
  /// moves via [HistoryNavigator] before navigating to the game page), so
  /// callers that may run in that window must check this first instead of
  /// touching [animationManager] directly.
  bool get hasAnimationManager => _animationManager != null;

  AnimationManager get animationManager {
    assert(
      _animationManager != null,
      'animationManager accessed before a GameBoard assigned it; '
      'guard with hasAnimationManager first.',
    );
    return _animationManager!;
  }

  set animationManager(AnimationManager value) {
    _animationManager = value;
  }

  bool _isInitialized = false;

  bool get initialized => _isInitialized;

  bool get isPositionSetup => gameRecorder.setupPosition != null;

  void clearPositionSetupFlag() => gameRecorder.setupPosition = null;

  /// True while the setup-position editor is active.
  bool get isSetupPosition =>
      gameInstance.gameMode == GameMode.setupPosition &&
      setupPositionController != null;

  /// Enter the setup-position editor, seeding it from the current native
  /// session board.  No-op when there is no active native Mill session or
  /// when an editor is already active (idempotent).
  void enterSetupPosition() {
    if (setupPositionController != null) {
      return;
    }
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null) {
      logger.w("$_logTag enterSetupPosition: no active native Mill session.");
      return;
    }
    final MillSetupPositionController controller = MillSetupPositionController(
      session: session,
      ruleSettings: DB().ruleSettings,
    )..initFromSession();
    // The editor may be mounted directly on a setup-position route, in which
    // case the previous mode is already `setupPosition`; fall back to a
    // playable mode so committing/cancelling lands on a real game.
    _setupPreviousMode = gameInstance.gameMode == GameMode.setupPosition
        ? GameMode.humanVsAi
        : gameInstance.gameMode;
    setupPositionController = controller;
    gameInstance.gameMode = GameMode.setupPosition;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  /// Commit the edited position: install [fen] as the game's setup
  /// position and restore the previous (playable) game mode.
  void finishSetupPosition(String fen) {
    final GameMode previous = _setupPreviousMode ?? GameMode.humanVsAi;
    gameRecorder = GameRecorder(
      lastPositionWithRemove: fen,
      setupPosition: fen,
    );
    setupPositionController = null;
    _setupPreviousMode = null;
    gameInstance.gameMode = previous;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  /// Abandon setup editing, rolling the board back and restoring the
  /// previous game mode.
  void cancelSetupPosition() {
    final GameMode previous = _setupPreviousMode ?? GameMode.humanVsAi;
    setupPositionController?.cancel();
    setupPositionController = null;
    _setupPreviousMode = null;
    gameInstance.gameMode = previous;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  /// Apply a board symmetry to the current local playable Mill game.
  ///
  /// Setup-position editing has its own controller and LAN games cannot be
  /// transformed locally without desynchronising the remote peer. For local
  /// games this keeps the native session and the recorder in the same
  /// coordinate frame.
  bool transformActiveLocalGame(TransformationType type) {
    assert(
      gameInstance.gameMode != GameMode.setupPosition,
      'Setup Position must transform through MillSetupPositionController.',
    );
    if (gameInstance.gameMode == GameMode.setupPosition ||
        isRemoteGameMode ||
        isEngineRunning ||
        isEngineInDelay) {
      return false;
    }

    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null || session.outcome.isTerminal) {
      return false;
    }

    final String transformedFen = transformFEN(session.getFen(), type);
    final bool loaded = session.loadFen(transformedFen);
    assert(loaded, 'Active game board transformation must keep a valid FEN.');
    if (!loaded) {
      return false;
    }

    gameRecorder.transformCoordinates(type);
    session.lastHumanDatabaseMoveStats = null;
    lastMoveFromAI = false;
    activeSessionSnapshot = session.state.value;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'gameMenu',
        'action': 'transformBoard',
        'type': type.name,
      },
    );
    return true;
  }

  /// Discard an in-progress setup edit without changing the current game
  /// mode.  Used when the setup-position page is torn down by navigation:
  /// the next route has already set its own game mode, so this only rolls
  /// the board back and releases the editor.
  void abandonSetupPositionIfActive() {
    final MillSetupPositionController? controller = setupPositionController;
    if (controller == null) {
      return;
    }
    controller.cancel();
    setupPositionController = null;
    _setupPreviousMode = null;
  }

  @visibleForTesting
  static GameController instance = GameController._();

  /// S.of(context).starts up the controller. It will initialize the audio subsystem and heat the engine.
  Future<void> startController() async {
    if (_isInitialized) {
      return;
    }

    await SoundManager().loadSounds();
    await SoundManager().startBackgroundMusic();

    if (DB().generalSettings.usePerfectDatabase) {
      unawaited(ensurePerfectDatabaseReady());
    }

    // Only load the bundled error-patch asset when at least one of the two
    // switches that consume it is on, so devices that never enable either
    // toggle pay no extra startup/memory cost.
    final GeneralSettings settings = DB().generalSettings;
    if (settings.patchAvoidTraps || settings.patchMakeTraps) {
      unawaited(ensureMillPatchReady());
    }

    _isInitialized = true;
    logger.i("$_logTag initialized");
  }

  bool get isRemoteGameMode =>
      gameInstance.gameMode == GameMode.humanVsLAN ||
      gameInstance.gameMode == GameMode.humanVsBluetooth ||
      gameInstance.gameMode == GameMode.humanVsCloud;

  MillRemoteSessionMeta? get activeRemoteMeta =>
      isRemoteGameMode ? activeNativeMillSession?.remoteMeta : null;

  bool get isRemoteConnected => remoteCoordinator?.isConnected ?? false;

  bool get isRemoteBoardLocked => isRemoteGameMode && !isRemoteConnected;

  RuleSettings get ruleSettingsForActiveBoard {
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session != null) {
      return session.activeRuleSettings;
    }
    return gameRecorder.recordedRuleSettings ?? DB().ruleSettings;
  }

  bool get isRemoteOpponentTurn {
    final NativeMillGameSession? session = activeNativeMillSession;
    final MillRemoteSessionMeta? meta = activeRemoteMeta;
    if (session == null || meta == null) {
      return true;
    }
    return meta.isOpponentTurn(session.state.value.activeSeat);
  }

  /// Compatibility getter for widgets while LAN-only naming is removed.
  bool get isLanOpponentTurn => isRemoteOpponentTurn;

  PieceColor getLocalColor() {
    return switch (activeRemoteMeta?.localSeat) {
      PlayerSeat.first => PieceColor.white,
      PlayerSeat.second => PieceColor.black,
      PlayerSeat.none || null => PieceColor.nobody,
    };
  }

  Map<String, Object?>? get remoteDiagnostics =>
      remoteCoordinator?.diagnosticSnapshot ?? _lastRemoteDiagnostics;

  Future<String?> exportRemoteDiagnosticsToTempFile() async {
    final Map<String, Object?>? snapshot = remoteDiagnostics;
    if (snapshot == null) {
      return null;
    }
    final Directory directory = await getTemporaryDirectory();
    final File file = File('${directory.path}/sanmill_remote_diagnostics.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot),
    );
    return file.path;
  }

  Future<RemoteMatchCoordinator> createRemoteCoordinator({
    required RemoteTransportKind kind,
    required RemoteRole role,
  }) async {
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null) {
      throw StateError('A native Mill session is required for remote play.');
    }
    await disposeRemoteMatch();
    _lastRemoteDiagnostics = null;
    final RemoteTransport transport = switch (kind) {
      RemoteTransportKind.lan => LanTransport(role: role),
      RemoteTransportKind.bluetooth => BluetoothTransport(role: role),
      RemoteTransportKind.cloud => throw ArgumentError.value(
        kind,
        'kind',
        'Cloud matches must be created by the online-play contribution.',
      ),
    };
    final NativeMillRemoteGameAdapter adapter = NativeMillRemoteGameAdapter(
      session: session,
      transportKind: kind,
      role: role,
      generalSettings: DB().generalSettings,
      onBeforeReset: () => _prepareRemoteSessionReset(session),
      onStateChanged: () => _onRemoteSessionStateChanged(session),
    );
    final RemoteMatchCoordinator coordinator = RemoteMatchCoordinator(
      transport: transport,
      game: adapter,
      localPeer: await RemotePeerIdentity.create(),
    );
    remoteCoordinator = coordinator;
    _remoteMatchSubscription = coordinator.events.listen(_onRemoteMatchEvent);
    gameInstance.gameMode = switch (kind) {
      RemoteTransportKind.lan => GameMode.humanVsLAN,
      RemoteTransportKind.bluetooth => GameMode.humanVsBluetooth,
      RemoteTransportKind.cloud => throw StateError(
        'Cloud coordinators use the online-play factory.',
      ),
    };
    disableStats = false;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
    logger.i(
      '$_logTag [Remote] coordinator created '
      'transport=${kind.name} role=${role.name}',
    );
    return coordinator;
  }

  /// Builds and installs the server-authoritative controller supplied by the
  /// optional online-play module without importing that module here.
  Future<T> createCloudRemoteController<T extends RemoteMatchController>(
    FutureOr<T> Function(RemoteGameAdapter game) factory, {
    required RemoteRole role,
  }) async {
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null) {
      throw StateError('A native Mill session is required for online play.');
    }
    await disposeRemoteMatch();
    _lastRemoteDiagnostics = null;
    final NativeMillRemoteGameAdapter adapter = NativeMillRemoteGameAdapter(
      session: session,
      transportKind: RemoteTransportKind.cloud,
      role: role,
      generalSettings: DB().generalSettings,
      onBeforeReset: () => _prepareRemoteSessionReset(session),
      onStateChanged: () => _onRemoteSessionStateChanged(session),
    );
    final T coordinator = await factory(adapter);
    remoteCoordinator = coordinator;
    _remoteMatchSubscription = coordinator.events.listen(_onRemoteMatchEvent);
    gameInstance.gameMode = GameMode.humanVsCloud;
    disableStats = false;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
    logger.i('$_logTag [Remote] cloud coordinator created');
    return coordinator;
  }

  Future<void> startRemoteHost({
    required RemoteMatchCoordinator coordinator,
    required bool hostPlaysWhite,
    String? bindAddress,
    int port = 33333,
    String advertisedLabel = 'Sanmill',
  }) async {
    assert(identical(remoteCoordinator, coordinator));
    final RuleSettings rules = DB().ruleSettings;
    final NativeMillRulesPort initialRules = NativeMillRulesPort(
      ruleSettings: rules,
      generalSettings: DB().generalSettings,
    );
    final String initialFen = initialRules.exportFen();
    initialRules.dispose();
    await coordinator.startHost(
      options: RemoteHostOptions(
        bindAddress: bindAddress,
        port: port,
        advertisedLabel: advertisedLabel,
      ),
      ruleSettings: Map<String, Object?>.from(rules.toJson()),
      initialFen: initialFen,
      hostPlaysFirst: hostPlaysWhite,
    );
  }

  void _prepareRemoteSessionReset(NativeMillGameSession session) {
    gameResultNotifier.clearResult();
    gameRecorder = GameRecorder(lastPositionWithRemove: session.getFen());
    lastMoveFromAI = false;
    PlayerTimer().reset();
    OfflineBoardClock().reset();
    _resetGameTiming();
  }

  void _onRemoteSessionStateChanged(NativeMillGameSession session) {
    activeSessionSnapshot = session.state.value;
    refreshRemoteTurn(showTip: remoteCoordinator?.isConnected ?? false);
    if (session.outcome.isTerminal) {
      gameResultNotifier.showResult(force: true);
    }
  }

  void _onRemoteMatchEvent(RemoteMatchEvent event) {
    switch (event) {
      case RemoteMatchStateChanged():
        if (event.state == RemoteConnectionState.reconnecting) {
          final BuildContext? context = rootScaffoldMessengerKey.currentContext;
          if (context != null) {
            headerTipNotifier.showTip(
              S.of(context).remoteReconnectingBoardLocked,
              snackBar: false,
            );
          }
        }
        boardSemanticsNotifier.updateSemantics();
      case RemotePeerApprovalRequested():
        unawaited(_approveRemotePeer(event));
      case RemoteMatchReady():
        disableStats = false;
        refreshRemoteTurn();
      case RemoteMatchUpgradeRequired():
        unawaited(_showRemoteUpgradeRequired());
      case RemoteMatchActionRejected():
        _showRemoteRejection(event.reason);
      case RemoteTakeBackApprovalRequested():
        unawaited(_approveRemoteTakeBack(event));
      case RemoteRestartApprovalRequested():
        unawaited(_approveRemoteRestart(event));
      case RemoteOpponentResigned():
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(S.of(context).opponentResignedYouWin);
        }
        gameResultNotifier.showResult(force: true);
      case RemoteOpponentConnectionChanged():
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null && !event.connected) {
          headerTipNotifier.showTip(
            S.of(context).onlineOpponentDisconnected,
            snackBar: false,
          );
        }
      case RemoteOpponentLeft():
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(
            S.of(context).onlineOpponentLeft,
            snackBar: true,
          );
        }
      case RemoteReconnectExhausted():
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(
            S.of(context).onlineReconnectFailed,
            snackBar: true,
          );
        }
      case RemoteOnlineFailure():
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(
            _onlineFailureMessage(S.of(context), event.failure),
            snackBar: true,
          );
        }
      case RemoteMatchAborted():
        disableStats = true;
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(
            event.reason.startsWith('Reconnect timed out')
                ? S.of(context).remoteReconnectTimedOut
                : S.of(context).remoteConnectionFailed(event.reason),
            snackBar: true,
          );
        }
      case RemoteMatchFailure():
        logger.e(
          '$_logTag [Remote] coordinator failure: ${event.error}',
          stackTrace: event.stackTrace,
        );
        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        if (context != null) {
          headerTipNotifier.showTip(
            S.of(context).remoteConnectionFailed(event.error.toString()),
            snackBar: true,
          );
        }
    }
  }

  String _onlineFailureMessage(S s, OnlineFailure failure) {
    return switch (failure) {
      OnlineFailure.invalidInvite => s.onlineInvalidInvite,
      OnlineFailure.inviteExpired => s.onlineInviteExpired,
      OnlineFailure.inviteAlreadyUsed => s.onlineInviteAlreadyUsed,
      OnlineFailure.roomUnavailable => s.onlineRoomUnavailable,
      OnlineFailure.roomFull => s.onlineRoomFull,
      OnlineFailure.versionMismatch => s.onlineVersionMismatch,
      OnlineFailure.serviceUnavailable ||
      OnlineFailure.unauthorized ||
      OnlineFailure.protocolError => s.onlineServiceUnavailable,
    };
  }

  Future<void> _approveRemotePeer(RemotePeerApprovalRequested event) async {
    final RemoteMatchController? coordinator = remoteCoordinator;
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (coordinator is! RemoteMatchCoordinator) {
      return;
    }
    if (context == null) {
      await coordinator.approvePeer(accepted: false);
      return;
    }
    final bool accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(S.of(dialogContext).remoteApprovalTitle),
            content: Text(
              S
                  .of(dialogContext)
                  .remoteApprovalBody(
                    event.peer.label,
                    event.peer.platform,
                    event.peer.shortId,
                  ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(S.of(dialogContext).no),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(S.of(dialogContext).yes),
              ),
            ],
          ),
        ) ??
        false;
    if (identical(remoteCoordinator, coordinator)) {
      await coordinator.approvePeer(accepted: accepted);
    }
  }

  Future<void> _approveRemoteTakeBack(
    RemoteTakeBackApprovalRequested event,
  ) async {
    final RemoteMatchController? coordinator = remoteCoordinator;
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (coordinator == null) {
      return;
    }
    final bool accepted =
        context != null &&
        (await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: Text(S.of(dialogContext).takeBackRequest),
                content: Text(
                  S
                      .of(dialogContext)
                      .opponentRequestsTakeBackAccept(event.steps.toString()),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(S.of(dialogContext).no),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(S.of(dialogContext).yes),
                  ),
                ],
              ),
            ) ??
            false);
    if (identical(remoteCoordinator, coordinator)) {
      await coordinator.respondToTakeBack(
        requestId: event.requestId,
        steps: event.steps,
        accepted: accepted,
      );
    }
  }

  Future<void> _approveRemoteRestart(
    RemoteRestartApprovalRequested event,
  ) async {
    final RemoteMatchController? coordinator = remoteCoordinator;
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (coordinator == null) {
      return;
    }
    final bool accepted =
        context != null &&
        (await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: Text(S.of(dialogContext).restartRequest),
                content: Text(
                  S
                      .of(dialogContext)
                      .opponentRequestedToRestartTheGameDoYouAccept,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(S.of(dialogContext).no),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(S.of(dialogContext).yes),
                  ),
                ],
              ),
            ) ??
            false);
    if (identical(remoteCoordinator, coordinator)) {
      await coordinator.respondToRestart(
        requestId: event.requestId,
        accepted: accepted,
      );
    }
  }

  Future<void> _showRemoteUpgradeRequired() async {
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(S.of(dialogContext).appName),
        content: Text(S.of(dialogContext).remoteProtocolUpgradeRequired),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).ok),
          ),
        ],
      ),
    );
  }

  void _showRemoteRejection(String reason) {
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }
    final String message = switch (reason) {
      'hostBusy' ||
      'activeSession' ||
      'approvalPending' => S.of(context).remoteHostBusy,
      'hostRejected' => S.of(context).remotePeerRejected,
      _ => S.of(context).remoteActionRejected,
    };
    headerTipNotifier.showTip(message, snackBar: true);
  }

  /// Undo the last move through the active [NativeMillGameSession].
  ///
  /// Returns true if a session was available and undo was triggered.
  Future<bool> undoNativeMove() async {
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null) {
      return false;
    }
    await session.undo();
    return true;
  }

  bool isNativeRemoteOpponentTurn(NativeMillGameSession session) {
    final MillRemoteSessionMeta? meta = session.remoteMeta ?? activeRemoteMeta;
    return meta == null || meta.isOpponentTurn(session.state.value.activeSeat);
  }

  void requestRestart() {
    if (isRemoteGameMode && isRemoteConnected) {
      unawaited(_requestRemoteRestart());
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      if (context != null) {
        headerTipNotifier.showTip(
          S.of(context).restartRequestSentWaitingForOpponentSResponse,
        );
      }
    } else {
      reset();
    }
  }

  Future<void> _requestRemoteRestart() async {
    final bool accepted = await remoteCoordinator!.requestRestart();
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (!accepted && context != null && context.mounted) {
      headerTipNotifier.showTip(S.of(context).restartRequestRejected);
    }
  }

  void requestResignation() {
    if (!isRemoteGameMode || !isRemoteConnected) {
      logger.i("$_logTag Local resignation in non-LAN mode");
      _handleLocalResignation();
      return;
    }

    // In LAN mode, confirm with the player first
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final S strings = S.of(dialogContext);
        return AlertDialog(
          title: Text(strings.confirmResignation),
          content: Text(strings.areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(strings.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(true);
                try {
                  await remoteCoordinator!.resign();
                  headerTipNotifier.showTip(strings.youResignedGameOver);
                  gameResultNotifier.showResult();
                } catch (e) {
                  logger.e("$_logTag Failed to send resignation: $e");
                  headerTipNotifier.showTip(strings.failedToSendResignation);
                }
              },
              child: Text(strings.resign),
            ),
          ],
        );
      },
    );
  }

  /// Handles resignation in non-LAN modes (e.g., vs AI)
  void _handleLocalResignation() {
    // The side to move resigns, so its opponent wins.  Drive the native
    // session to a terminal `loseResign` state so the result dialog,
    // score tally, and ELO update all fire.
    final PieceColor winnerColor = activeBoardView.sideToMove.opponent;
    forceGameOver(winnerColor, GameOverReason.loseResign);

    // Update UI.  The result dialog plays the appropriate end-of-game
    // tone, so no explicit SoundManager call is needed here.
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String youResignedGameOver = context != null
        ? S.of(context).youResignedGameOver
        : "You resigned, game over";
    headerTipNotifier.showTip(youResignedGameOver);
    gameResultNotifier.showResult();

    logger.i("$_logTag Local player resigned. Winner: $winnerColor");
  }

  /// Maps a Mill [PieceColor] winner onto the platform [GameOutcome]
  /// consumed by the native session.  A draw collapses to
  /// [platform.GameOutcome.draw]; an unknown / "nobody" winner collapses
  /// to [platform.GameOutcome.abandoned].
  static platform.GameOutcome _sessionOutcomeForWinner(PieceColor winner) {
    return switch (winner) {
      PieceColor.white => const platform.GameOutcome.win(
        platform.PlayerSeat.first,
      ),
      PieceColor.black => const platform.GameOutcome.win(
        platform.PlayerSeat.second,
      ),
      PieceColor.draw => const platform.GameOutcome.draw(),
      _ => const platform.GameOutcome.abandoned(),
    };
  }

  /// Force the active native Mill session into a terminal state that the
  /// Rust rule machine cannot derive on its own (resignation, human-clock
  /// timeout).  Mirrors the legacy `Position.setGameOver(winner, reason)`.
  ///
  /// Returns true when an active native session accepted the override.
  /// Callers should invoke [GameResultNotifier.showResult] afterwards to
  /// surface the result UI from the now-terminal snapshot.
  bool forceGameOver(PieceColor winner, GameOverReason reason) {
    final NativeMillGameSession? session = activeNativeMillSession;
    if (session == null) {
      logger.w("$_logTag forceGameOver: no active native Mill session.");
      return false;
    }
    session.forceTerminal(
      _sessionOutcomeForWinner(winner),
      reason: reason.tgfReason,
    );
    if (gameInstance.gameMode == GameMode.humanVsHuman) {
      OfflineBoardClock().pause();
    }
    return true;
  }

  /// The human player's move clock expired: award the win to the opponent
  /// of the side to move (mirrors the legacy `loseTimeout` game-over) and
  /// surface the result.
  void handleHumanTimeout() {
    final PieceColor winnerColor = activeBoardView.sideToMove.opponent;
    forceGameOver(winnerColor, GameOverReason.loseTimeout);
    gameResultNotifier.showResult();
  }

  /// Modify the reset method so that in LAN restart mode the socket is preserved.
  void reset({
    bool force = false,
    bool lanRestart = false,
    bool preserveLan = false,
  }) {
    loadedGameSourcePath = null;
    _claimedLoadedAiTurnResumeKey = null;
    final GameMode gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPosSetup = isPositionSetup;

    // Puzzle mode: reset any transient auto-move lock.
    isPuzzleAutoMoveInProgress = false;

    value = "0";
    aiMoveType = AiMoveType.unknown;
    // Ask the Rust searcher to abort if one is in flight.  Gated on
    // `isEngineRunning` so unit-test environments that do not load
    // the FRB native library do not panic on the call (the FRB
    // generated stub asserts the global runtime is initialised).
    if (isEngineRunning) {
      tgf.nativeMillSearchStop();
    }
    // Signal any running AI-vs-AI / human-vs-AI loop to bail out:
    // _nativeAiVsAiLoop checks isControllerActive between iterations
    // and breaks out as soon as it flips to false.  We also clear
    // isEngineRunning so the *new* engineToGo call we are about to
    // dispatch can start its own loop instead of getting an early
    // 'engine still running, skip' return.  Without this, pressing
    // New Game during an active aiVsAi self-play left the prior loop
    // running on the old session reference while the freshly-built
    // session was idle, surfacing as 'no AI activity after New Game'.
    isControllerActive = false;
    isEngineRunning = false;
    isEngineInDelay = false;
    aiLoopEpoch++;
    AnalysisMode.disable();

    if (gameModeBak == GameMode.humanVsAi) {
      GameController().disableStats = false;
    } else if (gameModeBak == GameMode.humanVsHuman ||
        gameModeBak == GameMode.analysis) {
      GameController().disableStats = true;
    }

    // Reset player timer
    PlayerTimer().reset();
    OfflineBoardClock().reset();

    // Reset game timing tracking
    _resetGameTiming();

    final bool remoteMode =
        gameModeBak == GameMode.humanVsLAN ||
        gameModeBak == GameMode.humanVsBluetooth ||
        gameModeBak == GameMode.humanVsCloud;
    if (!remoteMode || force || !lanRestart) {
      unawaited(disposeRemoteMatch());
    }

    if (isPosSetup && !force) {
      fen = gameRecorder.setupPosition;
    }

    // Reinitialize game objects
    _init(gameModeBak);

    if (isPosSetup && !force && fen != null) {
      gameRecorder.setupPosition = fen;
      gameRecorder.lastPositionWithRemove = fen;
      // Restore the setup FEN into the native session.
      activeNativeMillSession?.loadFen(fen);
    } else {
      // New game: reset the native session to the initial empty board.
      activeNativeMillSession?.resetGame(
        rules: DB().ruleSettings,
        generalSettings: DB().generalSettings,
      );
      gameRecorder.lastPositionWithRemove = activeFen;
    }

    gameInstance.gameMode = gameModeBak;
    GifShare().captureView(first: true);

    // Record game reset event for experience recording.
    RecordingService().recordEvent(
      RecordingEventType.gameReset,
      <String, dynamic>{
        'force': force,
        'lanRestart': lanRestart,
        'gameMode': gameModeBak.toString(),
      },
    );

    // Timer is no longer started here.
    // It will be started in tap_handler after the first human move.
  }

  bool startGameFromFen({required GameMode mode, required String fen}) {
    assert(
      mode == GameMode.humanVsAi ||
          mode == GameMode.humanVsHuman ||
          mode == GameMode.analysis,
      'Continue from here supports local playable and analysis modes.',
    );
    final String trimmedFen = fen.trim();
    assert(trimmedFen.isNotEmpty, 'Continue from here requires a FEN.');

    gameInstance.gameMode = mode;
    reset(force: true);

    final NativeMillGameSession session = activeNativeMillSession!;

    final bool loaded = session.loadFen(trimmedFen);
    assert(loaded, 'Continue from here FEN must be loadable.');

    gameRecorder.setupPosition = trimmedFen;
    gameRecorder.lastPositionWithRemove = trimmedFen;
    activeSessionSnapshot = session.state.value;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
    return true;
  }

  void clearAnalysisMoves({required NativeMillGameSession session}) {
    assert(
      gameInstance.gameMode == GameMode.analysis,
      'Only analysis mode can clear analysis moves.',
    );
    assert(
      activeNativeMillSession == session,
      'Analysis move clearing requires the active native session.',
    );

    final String? setupFen = gameRecorder.setupPosition?.trim();
    gameRecorder.reset();
    AnalysisMode.disable();

    if (setupFen != null && setupFen.isNotEmpty) {
      final bool loaded = session.loadFen(setupFen);
      assert(loaded, 'Analysis start FEN must be loadable.');
      gameRecorder.setupPosition = setupFen;
    } else {
      session.resetGame(
        rules: DB().ruleSettings,
        generalSettings: DB().generalSettings,
      );
      gameRecorder.setupPosition = null;
    }

    gameRecorder.lastPositionWithRemove = session.getFen();
    activeSessionSnapshot = session.state.value;
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  /// S.of(context).starts the current game.
  ///
  /// This method is suitable to use for starting a new game.
  void _startGame() {
    // Placeholder for future implementation
  }

  void _init(GameMode mode) {
    gameInstance = Game(gameMode: mode);
    gameRecorder = GameRecorder(lastPositionWithRemove: activeFen);

    _startGame();

    // Reset player timer
    PlayerTimer().reset();
    OfflineBoardClock().reset();
  }

  Future<void> disposeRemoteMatch() async {
    final RemoteMatchController? coordinator = remoteCoordinator;
    final StreamSubscription<RemoteMatchEvent>? subscription =
        _remoteMatchSubscription;
    final NativeMillGameSession? session = activeNativeMillSession;
    remoteCoordinator = null;
    _remoteMatchSubscription = null;
    await subscription?.cancel();
    await coordinator?.dispose();
    if (coordinator != null) {
      _lastRemoteDiagnostics = coordinator.diagnosticSnapshot;
    }
    session?.remoteMeta = null;
    boardSemanticsNotifier.updateSemantics();
  }

  void refreshRemoteTurn({bool showTip = true, bool snackBar = false}) {
    if (!isRemoteGameMode) {
      return;
    }
    final bool opponentTurn = isRemoteOpponentTurn;
    logger.i(
      '$_logTag [Remote] turn refreshed local=${getLocalColor()} '
      'side=${activeBoardView.sideToMove} opponentTurn=$opponentTurn '
      'ready=$isRemoteConnected',
    );
    if (showTip) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      if (context != null) {
        headerTipNotifier.showTip(
          opponentTurn ? S.of(context).opponentSTurn : S.of(context).yourTurn,
          snackBar: snackBar,
        );
      }
    }
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  Future<bool> submitRemoteMove(String notation) async {
    final RemoteMatchController? coordinator = remoteCoordinator;
    if (!isRemoteGameMode || coordinator == null || !coordinator.isConnected) {
      return false;
    }
    final bool accepted = await coordinator.submitLocalAction(notation);
    if (accepted) {
      refreshRemoteTurn();
    }
    return accepted;
  }

  Future<bool> requestRemoteTakeBack(int steps) async {
    assert(steps > 0, 'Remote takeback requires a positive step count.');
    final RemoteMatchController? coordinator = remoteCoordinator;
    if (!isRemoteGameMode ||
        coordinator == null ||
        !coordinator.isConnected ||
        steps <= 0) {
      return false;
    }
    if (isRemoteOpponentTurn) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      if (context != null) {
        headerTipNotifier.showTip(
          S.of(context).cannotRequestATakeBackWhenItSNotYourTurn,
        );
      }
      return false;
    }
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String? rejectedMessage = context != null
        ? S.of(context).takeBackRejected
        : null;
    if (context != null) {
      headerTipNotifier.showTip(
        S.of(context).takeBackRequestSentToTheOpponent,
        snackBar: false,
      );
    }
    final bool accepted = await coordinator.requestTakeBack(steps);
    if (!accepted && rejectedMessage != null) {
      headerTipNotifier.showTip(rejectedMessage);
    }
    return accepted;
  }

  bool isAutoRestart() {
    if (EnvironmentConfig.devMode == true) {
      final bool hasNonDrawScore =
          (millScore[PieceColor.white] ?? 0) > 0 ||
          (millScore[PieceColor.black] ?? 0) > 0;
      return DB().generalSettings.isAutoRestart && !hasNonDrawScore;
    }

    return DB().generalSettings.isAutoRestart;
  }

  /// Whether the finished game should immediately start a fresh board.
  ///
  /// Mirrors master `engineToGo` auto-restart gating: the option is
  /// honoured for local play modes, AI-vs-AI additionally requires zero
  /// animation time and disabled shuffling (same constraints as the
  /// result dialog), and LAN / setup / puzzle flows are excluded.
  bool shouldAutoRestartAfterGameOver() {
    if (!isAutoRestart()) {
      return false;
    }

    final GameMode gameMode = gameInstance.gameMode;
    if (gameMode == GameMode.setupPosition ||
        gameMode == GameMode.humanVsLAN ||
        gameMode == GameMode.humanVsBluetooth ||
        gameMode == GameMode.analysis ||
        gameMode == GameMode.puzzle) {
      return false;
    }

    final PieceColor winner = activeSessionWinner ?? activeBoardView.winner;
    if (winner == PieceColor.nobody) {
      return false;
    }

    if (gameMode == GameMode.aiVsAi) {
      return DB().displaySettings.animationDuration == 0.0 &&
          DB().generalSettings.shufflingEnabled == false;
    }

    return true;
  }

  /// Reset the session and resume AI play when [shouldAutoRestartAfterGameOver]
  /// is true.  Restores the master `engineToGo` behaviour that was lost
  /// during the Rust/FRB migration.
  void performAutoRestartIfEnabled(BuildContext context) {
    if (!shouldAutoRestartAfterGameOver()) {
      return;
    }

    gameResultNotifier.clearResult();
    reset();

    if (!context.mounted) {
      return;
    }

    final GameMode gameMode = gameInstance.gameMode;
    if (gameInstance.isAiSideToMove &&
        (gameMode == GameMode.humanVsAi || gameMode == GameMode.aiVsAi)) {
      unawaited(engineToGo(context, isMoveNow: false));
    }
  }

  Future<EngineResponse> engineToGo(
    BuildContext context, {
    required bool isMoveNow,
    GameSession? session,
  }) async {
    const String tag = "[engineToGo]";
    if (EnvironmentConfig.devMode) {
      logger.i(
        "$tag entry: gameMode=${gameInstance.gameMode}, "
        "isMoveNow=$isMoveNow, isEngineRunning=$isEngineRunning, "
        "isControllerActive=$isControllerActive, "
        "activeSessionSnapshot=${activeSessionSnapshot != null}, "
        "_activeSession.runtimeType=${_activeSession.runtimeType}",
      );
    }

    if (isRemoteGameMode) {
      // Remote matches are driven by the authoritative coordinator.
      return const EngineResponseHumanOK();
    }

    // Move Now while a native search is already running: ask the
    // Rust searcher to abort.  The driving coroutine that started the
    // search will then receive the aborted bestmove from
    // `searchBestAction`, apply it, and clear `isEngineRunning`.  We
    // must NOT spawn a second concurrent search on top of it -- both
    // calls would race for the global `ACTIVE_SEARCH` slot in
    // `crates/tgf-frb/src/games/mill/search.rs` and produce no visible
    // move, which is the exact symptom reported on this branch.
    //
    // Master's Move Now used `engine.stopSoft()` over UCI to achieve
    // the same effect; here we mirror that by hitting the FRB stop
    // entry point directly.  When the engine is idle this is a no-op
    // and we fall through to the regular dispatch below so the AI
    // starts thinking on demand (e.g. user pressed Move Now while it
    // was the human's turn after `moveNow()` swapped roles).
    if (isMoveNow && isEngineRunning) {
      if (EnvironmentConfig.devMode) {
        logger.i(
          "$tag isMoveNow && isEngineRunning -> request native search abort.",
        );
      }
      tgf.nativeMillSearchStop();
      return const EngineResponseSkip();
    }

    // Master-parity re-entrancy guard (legacy engineToGo / search_engine):
    // never start a second concurrent search while one is already in flight.
    // Move Now is the only exception and is handled above by aborting the
    // running search.  Without this guard a re-triggered engineToGo (new
    // game, auto-restart, replay kick, or a stray notifier) races the
    // in-flight search for the global ACTIVE_SEARCH slot; the first applies
    // its move and the second's now-stale bestMove is rejected as illegal --
    // the spurious EngineNoBestMove symptom this branch fixed in the tap path.
    if (isEngineRunning && !isMoveNow) {
      logger.t("$tag engineToGo still running; skip re-entrant call.");
      return const EngineResponseSkip();
    }

    if (gameInstance.gameMode == GameMode.humanVsAi) {
      return _nativeSessionEngineToGo(
        context,
        isMoveNow: isMoveNow,
        session: session,
      );
    }

    // AI vs AI must also drive the Rust/FRB native session.  The legacy
    // `engine.search()` path delegates UCI commands through method-channel
    // stubs (see `Engine.startup` doc) that no longer reach a real engine
    // thread, so without this branch clicking "New Game" while in AI vs AI
    // mode silently spins on `_waitResponse(["bestmove"])` and the board
    // never advances.  Route through the dedicated native loop instead.
    if (gameInstance.gameMode == GameMode.aiVsAi) {
      if (EnvironmentConfig.devMode) {
        logger.i("$tag routing to _nativeAiVsAiLoop");
      }
      return _nativeAiVsAiLoop(context, isMoveNow: isMoveNow, session: session);
    }

    // Every game mode that drives the AI is intercepted above
    // (humanVsLAN early-returns, humanVsAi delegates to
    // `_nativeSessionEngineToGo`, aiVsAi delegates to
    // `_nativeAiVsAiLoop`).  humanVsHuman / setupPosition never reach
    // `engineToGo` because the legacy `Engine` no longer exists.
    // Keep this assert as a tripwire: if a future game mode is added
    // without an explicit branch above, surface it loudly instead of
    // silently falling through to a deleted UCI loop.
    assert(
      false,
      "$tag unreachable: gameMode=${gameInstance.gameMode} has no AI driver.",
    );
    return const EngineResponseSkip();
  }

  Future<EngineResponse> _nativeSessionEngineToGo(
    BuildContext context, {
    required bool isMoveNow,
    GameSession? session,
  }) async {
    const String tag = "[engineToGo][native]";
    // Same fall-back as _nativeAiVsAiLoop -- prefer the
    // controller-bound active session so flows triggered from the
    // modal route still work even if the InheritedWidget probe via
    // context returns null.
    final GameSession? scopedFromContext =
        session == null && _activeSession == null
        ? GameSessionScope.sessionOf(context)
        : null;
    final GameSession? scopedSession =
        session ?? _activeSession ?? scopedFromContext;
    if (scopedSession is! NativeMillGameSession) {
      logger.w(
        "$tag Native flag is enabled but session is "
        "${scopedSession.runtimeType}.",
      );
      return const EngineResponseSkip();
    }

    // The controller's seat-aware filter normally derives `aiSeat`
    // from `generalSettings.aiMovesFirst`.  That breaks when Move Now
    // is pressed on a human-to-move turn, because `moveNow()` flips
    // who-is-AI via `gameInstance.reverseWhoIsAi()` but does NOT
    // touch the persisted `aiMovesFirst` flag.  The canonical "is it
    // an AI turn?" predicate is `gameInstance.isAiSideToMove`, which
    // checks `players[sideToMove].isAi` and therefore reflects the
    // temporary swap.  Run the controller in `bothSidesAi: true` mode
    // for the Move Now / human-vs-AI dispatch so it advances any
    // active seat the legacy logic deemed AI-controlled, and gate
    // entry on `gameInstance.isAiSideToMove` instead of the
    // controller's narrower seat predicate.
    final NativeMillAiTurnController aiTurnController =
        NativeMillAiTurnController(
          generalSettings: DB().generalSettings,
          bothSidesAi: true,
          onBeforeRemoveApply: gameInstance.awaitPendingMillSoundBeforeRemove,
          openingBook: MillOpeningBookProvider(
            ruleSettings: DB().ruleSettings,
            generalSettings: DB().generalSettings,
            placementHistory: openingBookPlacementHistory,
          ),
          humanDatabase: MillHumanDatabaseProvider(
            ruleSettings: DB().ruleSettings,
            generalSettings: DB().generalSettings,
          ),
        );
    final bool aiTurn = gameInstance.isAiSideToMove;
    if (isMoveNow && !aiTurn) {
      return const EngineResponseSkip();
    }
    if (!aiTurn) {
      return const EngineResponseHumanOK();
    }

    isEngineRunning = true;
    isControllerActive = true;
    refreshNativeSessionHeader(context, scopedSession, showThinking: true);

    try {
      final GameAction? action = await aiTurnController.playIfAiTurn(
        scopedSession,
      );
      if (action == null) {
        return const EngineNoBestMove();
      }
      syncAiMoveTypeFromSession(scopedSession);
      PlayerTimer().start();
      if (EnvironmentConfig.devMode) {
        logger.i("$tag Applied native AI move ${action.payload['move']}");
      }
      return const EngineResponseOK();
    } finally {
      isEngineRunning = false;
      if (context.mounted) {
        refreshNativeSessionHeader(context, scopedSession);
      }
    }
  }

  /// AI vs AI loop driven by the Rust/FRB native session.
  ///
  /// Mirrors the structure of `_nativeSessionEngineToGo` but keeps invoking
  /// `playIfAiTurn` while the session is still alive and the controller has
  /// not been deactivated.  Each iteration:
  ///   * lets the AI consume one full obligation chain (place / move +
  ///     follow-up removes are handled inside `playIfAiTurn`);
  ///   * refreshes the header tip so the UI reflects who is to move next;
  ///   * yields to the Flutter event loop via an animation-aware delay so
  ///     the UI can render the board and capture frames.
  ///
  /// When `isMoveNow` is true, the loop runs at most one iteration to honour
  /// the "Move Now" semantics of the legacy adapter.
  Future<EngineResponse> _nativeAiVsAiLoop(
    BuildContext context, {
    required bool isMoveNow,
    GameSession? session,
  }) async {
    const String tag = "[engineToGo][native][aiVsAi]";
    // Resolve session via the controller-bound `_activeSession`
    // FIRST so we don't depend on the modal's BuildContext still
    // being inside the GameSessionScope InheritedWidget tree --
    // showModalBottomSheet routes inside the same Navigator, but we
    // saw scopedSession show up as null in some app states; the
    // controller-bound reference is set by Home.dart whenever the
    // active session changes and never goes stale on a mode switch.
    final GameSession? scopedFromContext =
        session == null && _activeSession == null
        ? GameSessionScope.sessionOf(context)
        : null;
    final GameSession? scopedSession =
        session ?? _activeSession ?? scopedFromContext;
    if (EnvironmentConfig.devMode) {
      logger.i(
        "$tag enter: isMoveNow=$isMoveNow, "
        "scopedFromContext=${scopedFromContext.runtimeType}, "
        "_activeSession=${_activeSession.runtimeType}, "
        "resolved=${scopedSession.runtimeType}, "
        "isEngineRunning=$isEngineRunning",
      );
    }
    if (scopedSession is! NativeMillGameSession) {
      logger.w(
        "$tag AI-vs-AI requires NativeMillGameSession, got "
        "${scopedSession.runtimeType}.",
      );
      return const EngineResponseSkip();
    }

    if (isEngineRunning && !isMoveNow) {
      logger.w(
        "$tag _nativeAiVsAiLoop already running (isEngineRunning=true), skip.",
      );
      return const EngineResponseSkip();
    }

    // bothSidesAi: true bypasses the aiSeat filter inside the turn
    // controller so playIfAiTurn keeps advancing the game on every
    // active seat until terminal, mirroring master Search where
    // gameMode == GameMode::aiVsAi runs the engine for both colours.
    final NativeMillAiTurnController aiTurnController =
        NativeMillAiTurnController(
          generalSettings: DB().generalSettings,
          bothSidesAi: true,
          onBeforeRemoveApply: gameInstance.awaitPendingMillSoundBeforeRemove,
          openingBook: MillOpeningBookProvider(
            ruleSettings: DB().ruleSettings,
            generalSettings: DB().generalSettings,
            placementHistory: openingBookPlacementHistory,
          ),
          humanDatabase: MillHumanDatabaseProvider(
            ruleSettings: DB().ruleSettings,
            generalSettings: DB().generalSettings,
          ),
        );

    // Pin both the session identity AND the AI-loop epoch so the
    // loop can detect a New Game while it is mid-await.  reset()
    // increments aiLoopEpoch and the session's resetGame() mutates
    // the same object in-place, so identity alone is not enough --
    // the identity check fails to fire when the active session is
    // the same Dart object but the underlying state was wiped by
    // the freshly-clicked New Game.  The epoch is the canonical
    // signal: if it has been bumped while we were awaiting Rust
    // search, the loop bails out and lets the freshly-spawned loop
    // own the session exclusively.
    final NativeMillGameSession loopSession = scopedSession;
    aiLoopEpoch++;
    final int loopEpoch = aiLoopEpoch;

    isEngineRunning = true;
    isControllerActive = true;
    boardSemanticsNotifier.updateSemantics();

    bool searched = false;
    int iteration = 0;
    try {
      while (isControllerActive) {
        iteration++;
        if (EnvironmentConfig.devMode) {
          logger.i(
            "$tag iter=$iteration begin: "
            "phase=${loopSession.state.value.phase}, "
            "activeSeat=${loopSession.state.value.activeSeat}, "
            "outcome.isTerminal=${loopSession.outcome.isTerminal}",
          );
        }
        // Bail out if the active session has been rebuilt under us,
        // OR if the aiLoopEpoch has advanced (a fresh New Game spun
        // up another loop).  Either signal means this loop has been
        // superseded and must release the session to the new owner.
        if (!identical(_activeSession, loopSession)) {
          if (EnvironmentConfig.devMode) {
            logger.i("$tag session was replaced; exiting old loop.");
          }
          break;
        }
        if (aiLoopEpoch != loopEpoch) {
          if (EnvironmentConfig.devMode) {
            logger.i(
              "$tag aiLoopEpoch advanced from $loopEpoch to $aiLoopEpoch;"
              " exiting old loop.",
            );
          }
          break;
        }
        if (loopSession.outcome.isTerminal) {
          if (EnvironmentConfig.devMode) {
            logger.i("$tag terminal outcome; exiting.");
          }
          break;
        }
        // Both players are AI in this mode, so `aiTurnController.aiSeat`
        // does not cover the full picture: the active seat is always the
        // AI side here.  Using the seat-aware check still works because
        // bothSidesAi=true makes isAiTurn return true for any active
        // non-terminal seat, so the loop terminates only on terminal
        // outcomes, controller deactivation, or session replacement.
        if (!aiTurnController.isAiTurn(loopSession)) {
          logger.w("$tag isAiTurn=false; exiting (unexpected).");
          break;
        }

        if (context.mounted) {
          refreshNativeSessionHeader(context, loopSession, showThinking: true);
        }

        if (EnvironmentConfig.devMode) {
          logger.i("$tag iter=$iteration calling playIfAiTurn");
        }
        final Stopwatch sw = Stopwatch()..start();
        final GameAction? action = await aiTurnController.playIfAiTurn(
          loopSession,
        );
        sw.stop();
        if (EnvironmentConfig.devMode) {
          logger.i(
            "$tag iter=$iteration playIfAiTurn returned in ${sw.elapsedMilliseconds}ms: "
            "action=${action?.payload['move'] ?? '(null)'}",
          );
        }
        if (action == null) {
          logger.w(
            "$tag iter=$iteration playIfAiTurn returned null "
            "(searched=$searched); breaking.",
          );
          if (!searched) {
            return const EngineNoBestMove();
          }
          break;
        }
        searched = true;
        syncAiMoveTypeFromSession(loopSession);
        // Record AI-vs-AI game start time on the first applied move
        // so `calculateGameDurationSeconds` reports a meaningful
        // wall-clock duration on the result dialog.
        _recordGameStartTime();
        if (EnvironmentConfig.devMode) {
          logger.i("$tag Applied native AI move ${action.payload['move']}");
        }

        if (context.mounted) {
          refreshNativeSessionHeader(context, loopSession);
        }

        // Honour Move Now: a single AI turn is enough.
        if (isMoveNow) {
          break;
        }

        // Yield to the Flutter event loop so the UI repaints between AI
        // moves; this also gives `isControllerActive = false` (e.g. user
        // navigated away or pressed New Game) a chance to break the loop.
        final double animationDuration = DB().displaySettings.animationDuration;
        if (animationDuration > 0) {
          await _waitEngineDelay(
            Duration(milliseconds: (animationDuration * 1000).toInt()),
          );
        } else {
          // Even with zero animation time we must yield once so the event
          // loop can flush taps and lifecycle callbacks.
          await Future<void>.delayed(Duration.zero);
        }
      }
      return searched
          ? const EngineResponseOK()
          : const EngineResponseHumanOK();
    } finally {
      isEngineInDelay = false;
      _engineDelaySkipCompleter = null;
      // Only release running flag / show dialog when this loop is
      // still the *current* one (epoch matches) AND owns the active
      // session.  If a New Game raced ahead the new loop has already
      // taken ownership and we must not clobber its state.
      final bool stillCurrent =
          aiLoopEpoch == loopEpoch && identical(_activeSession, loopSession);
      if (stillCurrent) {
        isEngineRunning = false;
      }
      if (context.mounted) {
        refreshNativeSessionHeader(context, loopSession);
      }
      if (stillCurrent && loopSession.outcome.isTerminal) {
        gameResultNotifier.showResult(force: true);
      }
    }
  }

  Future<void> moveNow(
    BuildContext context, {
    MoveNowMessages? messages,
    GameSession? session,
  }) async {
    const String tag = "[engineToGo]";
    final BuildContext actionContext = _stableDialogContext(context);
    final GameSession? effectiveSession = session ?? activeNativeMillSession;
    bool reversed = false;
    final MoveNowMessages effectiveMessages =
        messages ?? MoveNowMessages.of(actionContext);

    loadedGameFilenamePrefix = null;

    if (isEngineInDelay) {
      _skipEngineDelayIfActive();
      return;
    }

    // Move Now only makes sense in modes with an engine driver; the other
    // modes (analysis, humanVsHuman, setupPosition, puzzle, ...) have no AI
    // side, and engineToGo would hit its unreachable-game-mode tripwire.
    final GameMode moveNowMode = gameInstance.gameMode;
    if (moveNowMode != GameMode.humanVsAi && moveNowMode != GameMode.aiVsAi) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        effectiveMessages.notAIsTurn,
      );
    }

    if (AnalysisMode.isEnabled || AnalysisMode.isAnalyzing) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        effectiveMessages.analyzing,
      );
    }

    // Defensive: sideToMove may be PieceColor.nobody when the game is over
    // or before the first move; treat that as "not AI's turn".
    final PieceColor moveNowSide = activeBoardView.sideToMove;
    if (moveNowSide != PieceColor.white && moveNowSide != PieceColor.black) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        effectiveMessages.notAIsTurn,
      );
    }

    if (gameInstance.isHumanToMove) {
      logger.i("$tag Human to Move. Temporarily swap AI and Human roles.");
      //return rootScaffoldMessengerKey.currentState!
      //    .showSnackBarClear(S.of(context).notAIsTurn);
      gameInstance.reverseWhoIsAi();
      reversed = true;
    }

    final String strTimeout = effectiveMessages.timeout;

    GameController().disableStats = true;

    final EngineResponse engineResponse = await engineToGo(
      actionContext,
      isMoveNow: true,
      session: effectiveSession,
    );

    if (!actionContext.mounted) {
      if (reversed) {
        gameInstance.reverseWhoIsAi();
      }
      return;
    }

    switch (engineResponse) {
      case EngineResponseOK():
      case EngineGameIsOver():
        gameResultNotifier.showResult(force: true);
        break;
      case EngineResponseHumanOK():
        gameResultNotifier.showResult();
        break;
      case EngineTimeOut():
        headerTipNotifier.showTip(strTimeout);
        if (gameInstance.gameMode != GameMode.aiVsAi) {
          await PerformanceWarningDialog.showIfNeeded(actionContext);
        }
        break;
      case EngineNoBestMove():
        final List<ExtMove> moves = gameRecorder.mainlineMoves;
        await EngineFailureDialog.show(
          actionContext,
          diagnosticContext: buildEngineFailureDiagnosticContext(
            actionContext,
            lastMove: moves.isNotEmpty ? moves.last.notation : null,
          ),
        );
        break;
      case EngineCancelled():
        break;
      case EngineResponseSkip():
        break;
      default:
        logger.e("$tag Unknown engine response type.");
        break;
    }

    if (reversed) {
      gameInstance.reverseWhoIsAi();
    }
  }

  Future<void> _waitEngineDelay(Duration duration) async {
    assert(!isEngineInDelay, 'Engine delay must not be nested.');
    assert(
      _engineDelaySkipCompleter == null,
      'Engine delay skip completer must be clear before waiting.',
    );
    final Completer<void> skipCompleter = Completer<void>();
    final Completer<void> delayCompleter = Completer<void>();
    final Timer delayTimer = Timer(duration, () {
      if (!delayCompleter.isCompleted) {
        delayCompleter.complete();
      }
    });
    _engineDelaySkipCompleter = skipCompleter;
    isEngineInDelay = true;
    try {
      await Future.any(<Future<void>>[
        delayCompleter.future,
        skipCompleter.future,
      ]);
    } finally {
      delayTimer.cancel();
      if (identical(_engineDelaySkipCompleter, skipCompleter)) {
        _engineDelaySkipCompleter = null;
      }
      isEngineInDelay = false;
    }
  }

  void _skipEngineDelayIfActive() {
    assert(isEngineInDelay, 'Move Now can skip only an active engine delay.');
    final Completer<void>? skipCompleter = _engineDelaySkipCompleter;
    assert(
      skipCompleter != null,
      'Engine delay flag requires a skip completer.',
    );
    if (skipCompleter == null || skipCompleter.isCompleted) {
      return;
    }
    skipCompleter.complete();
  }

  void showSnakeBarHumanNotation(String humanStr) {
    final List<ExtMove> moves = gameRecorder.mainlineMoves;
    final ExtMove? lastMove = moves.isNotEmpty ? moves.last : null;
    final String? n = lastMove?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        activeBoardView.action != Act.remove &&
        n != null) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        CustomSnackBar("$humanStr: $n"),
      );
    }
  }

  Future<void> gifShare(BuildContext context) async {
    headerTipNotifier.showTip(S.of(context).pleaseWait);
    final String done = S.of(context).done;
    await GifShare().captureView();
    headerTipNotifier.showTip(done);

    GifShare().shareGif();
  }

  /// S.of(context).starts a game save.
  static Future<String?> save(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    return LoadService.saveGame(context, shouldPop: shouldPop);
  }

  /// S.of(context).starts a game load.
  static Future<void> load(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    return LoadService.loadGame(
      context,
      null,
      isRunning: true,
      shouldPop: shouldPop,
    );
  }

  /// S.of(context).starts a game import.
  static Future<void> import(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    return ImportService.importGame(context, shouldPop: shouldPop);
  }

  /// S.of(context).starts a game export.
  static Future<void> export(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    DiagnosticReplayGuard.requireAllowed('Game clipboard exporting');
    final GameSession? session = GameSessionScope.sessionOf(context);
    if (session != null) {
      final String? exportText = GameExportService.buildCurrentExportText(
        context,
        session: session,
      );
      if (exportText != null && exportText.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: exportText));
        if (!context.mounted) {
          return;
        }
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).moveHistoryCopied,
        );
        if (shouldPop) {
          Navigator.pop(context);
        }
        return;
      }
    }
    return ExportService.exportGame(context, shouldPop: shouldPop);
  }

  /// Record the game start time when the first move is made in AI vs AI mode
  void _recordGameStartTime() {
    if (gameInstance.gameMode == GameMode.aiVsAi && !_gameStartTimeRecorded) {
      _gameStartTime = DateTime.now();
      _gameStartTimeRecorded = true;
      logger.i("$_logTag AI vs AI game start time recorded: $_gameStartTime");
    }
  }

  /// Calculate the game duration in seconds from first move to game end
  int calculateGameDurationSeconds() {
    if (_gameStartTime == null) {
      return 0;
    }
    final DateTime endTime = DateTime.now();
    final Duration gameDuration = endTime.difference(_gameStartTime!);
    return gameDuration.inSeconds;
  }

  /// Reset game timing tracking
  void _resetGameTiming() {
    _gameStartTime = null;
    _gameStartTimeRecorded = false;
  }
}

/// Placement moves played so far (in order, removals filtered), used by the
/// opening-book recognizer and the favoured-opening director.
List<String> openingBookPlacementHistory() {
  return GameController().gameRecorder.mainlineMoves
      .where((ExtMove move) => move.type == MoveType.place)
      .map((ExtMove move) => move.move)
      .toList(growable: false);
}
