// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_controller.dart

part of '../mill.dart';

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

  NetworkService? networkService;
  bool isLanOpponentTurn = false; // Tracks whose turn it is in LAN mode

  bool isDisposed = false;
  bool isControllerReady = false;
  bool isControllerActive = false;
  bool isEngineRunning = false;
  bool isEngineInDelay = false;

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
    headerIconsNotifier.showIcons();
  }

  void refreshNativeSessionHeader(
    BuildContext context,
    NativeMillGameSession session, {
    bool showThinking = false,
  }) {
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();

    if (session.outcome.isTerminal) {
      return;
    }

    if (showThinking) {
      headerTipNotifier.showTip(S.of(context).thinking, snackBar: false);
      return;
    }

    final String? tip = _nativeSessionTurnTip(context, session);
    if (tip != null) {
      headerTipNotifier.showTip(tip, snackBar: false);
    }
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
        gameInstance.gameMode == GameMode.humanVsLAN;

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
      if (showSide || DB().ruleSettings.mayMoveInPlacingPhase) {
        return S.of(context).tipToMove(sideName);
      }
      return S.of(context).tipPlace;
    }

    return null;
  }

  /// Remembers whether the host chose White; used for header icon arrangement.
  bool? lanHostPlaysWhite;

  // Use this Completer to wait for the final "accepted" or "rejected" from remote.
  Completer<bool>? pendingTakeBackCompleter;

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

  late AnimationManager animationManager;

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

    _isInitialized = true;
    logger.i("$_logTag initialized");
  }

  /// Determines the local player's color based on whether they are Host or Client
  PieceColor getLocalColor() {
    final LanSessionMeta? meta = activeNativeLanMeta;
    if (meta != null) {
      return switch (meta.localSeat) {
        PlayerSeat.first => PieceColor.white,
        PlayerSeat.second => PieceColor.black,
        PlayerSeat.none => PieceColor.nobody,
      };
    }
    final bool amIHost = networkService?.isHost ?? false;
    final bool hostPlaysWhite = lanHostPlaysWhite ?? true;
    if (amIHost) {
      // Host: If hostPlaysWhite is true, local is White; otherwise Black
      return hostPlaysWhite ? PieceColor.white : PieceColor.black;
    } else {
      // Client: Opposite of host's choice
      return hostPlaysWhite ? PieceColor.black : PieceColor.white;
    }
  }

  LanSessionMeta? get activeNativeLanMeta {
    if (!true || gameInstance.gameMode != GameMode.humanVsLAN) {
      return null;
    }
    return activeNativeMillSession?.lanMeta;
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

  bool isNativeLanOpponentTurn(NativeMillGameSession session) {
    final LanSessionMeta? meta = session.lanMeta ?? activeNativeLanMeta;
    final PlayerSeat localSeat = meta?.localSeat ?? _fallbackLocalSeat();
    final bool opponentTurn = session.state.value.activeSeat != localSeat;
    isLanOpponentTurn = opponentTurn;
    return opponentTurn;
  }

  Future<bool> handleNativeLanMove(
    NativeMillGameSession session,
    String moveNotation,
  ) async {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      logger.w("$_logTag Ignoring native LAN move: wrong mode");
      return false;
    }

    final GameAction? action = _nativeSessionActionForMove(
      session,
      moveNotation,
    );
    if (action == null) {
      logger.e("$_logTag Invalid native LAN move received: $moveNotation");
      headerTipNotifier.showTip("Opponent sent an invalid move");
      return false;
    }

    await session.apply(action);
    refreshLanTurn();
    if (session.outcome.isTerminal) {
      gameResultNotifier.showResult(force: true);
    }
    logger.i("$_logTag Successfully processed native LAN move: $moveNotation");
    return true;
  }

  GameAction? _nativeSessionActionForMove(
    NativeMillGameSession session,
    String moveNotation,
  ) {
    for (final GameAction action in session.legalActions) {
      if (action.payload['move'] == moveNotation) {
        return action;
      }
    }
    return null;
  }

  static PlayerSeat _seatFromPieceColor(PieceColor color) {
    return switch (color) {
      PieceColor.white => PlayerSeat.first,
      PieceColor.black => PlayerSeat.second,
      _ => PlayerSeat.none,
    };
  }

  PlayerSeat _fallbackLocalSeat() {
    final bool amIHost = networkService?.isHost ?? false;
    final bool hostPlaysWhite = lanHostPlaysWhite ?? true;
    final PieceColor localColor = amIHost
        ? (hostPlaysWhite ? PieceColor.white : PieceColor.black)
        : (hostPlaysWhite ? PieceColor.black : PieceColor.white);
    return _seatFromPieceColor(localColor);
  }

  /// Sends a restart request to the LAN opponent.
  /// This method is called when the local user requests a game restart.
  void requestRestart() {
    if (gameInstance.gameMode == GameMode.humanVsLAN &&
        (networkService?.isConnected ?? false)) {
      networkService!.sendMove("restart:request");
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

  /// Handles a restart request received from the opponent.
  /// Shows a confirmation dialog; if accepted, sends "restart:accepted" and resets game;
  /// otherwise, sends "restart:rejected".
  void handleRestartRequest() {
    showLanRestartRequestDialog(
      onAccept: (BuildContext dialogContext) {
        networkService?.sendMove("restart:accepted");
        reset(lanRestart: true);
      },
      onReject: (BuildContext dialogContext) {
        final String rejectedMessage = S
            .of(dialogContext)
            .restartRequestRejected;
        networkService?.sendMove("restart:rejected");
        headerTipNotifier.showTip(rejectedMessage);
      },
    );
  }

  /// Sends a resignation request to the LAN opponent.
  /// This method is called when the local player wants to resign.
  void requestResignation() {
    if (gameInstance.gameMode != GameMode.humanVsLAN ||
        !(networkService?.isConnected ?? false)) {
      // For non-LAN modes or when not connected, just handle locally
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
        return AlertDialog(
          title: Text(S.of(context).confirmResignation),
          content: Text(S.of(dialogContext).areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(S.of(context).cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);

                // Send resignation to opponent
                try {
                  networkService!.sendMove("resign:request");
                  logger.i("$_logTag Sent resignation request");

                  // The local player resigned, so the opponent wins.
                  // Drive the native session to a terminal `loseResign`
                  // state; the result dialog plays the end-of-game tone.
                  final PieceColor winnerColor = getLocalColor().opponent;
                  forceGameOver(winnerColor, GameOverReason.loseResign);

                  headerTipNotifier.showTip(S.of(context).youResignedGameOver);
                  gameResultNotifier.showResult();
                } catch (e) {
                  logger.e("$_logTag Failed to send resignation: $e");
                  headerTipNotifier.showTip(
                    S.of(context).failedToSendResignation,
                  );
                }
              },
              child: Text(S.of(dialogContext).resign),
            ),
          ],
        );
      },
    );
  }

  /// Handles a resignation request received from the LAN opponent.
  /// This sets the local player as the winner and updates the game state.
  void handleResignation() {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      logger.w("$_logTag Ignoring resignation request: not in LAN mode");
      return;
    }

    try {
      // The LAN opponent resigned, so the local player wins.  Drive the
      // native session to a terminal `loseResign` state; the result
      // dialog plays the end-of-game tone.
      final PieceColor winner = getLocalColor();
      forceGameOver(winner, GameOverReason.loseResign);

      // Update UI
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      if (context != null) {
        headerTipNotifier.showTip(S.of(context).opponentResignedYouWin);
      } else {
        headerTipNotifier.showTip("Opponent resigned, you win");
      }
      gameResultNotifier.showResult();
      isLanOpponentTurn = false;

      logger.i("$_logTag Handled opponent resignation");
    } catch (e) {
      logger.e("$_logTag Error handling resignation: $e");
      headerTipNotifier.showTip("Error handling opponent resignation");
    }
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
    final GameMode gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPosSetup = isPositionSetup;
    final bool? savedHostPlaysWhite = lanHostPlaysWhite;

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
    } else if (gameModeBak == GameMode.humanVsHuman) {
      GameController().disableStats = true;
    }

    // Reset player timer
    PlayerTimer().reset();

    // Reset game timing tracking
    _resetGameTiming();

    if (gameModeBak == GameMode.humanVsLAN) {
      // In LAN mode, if this is a normal reset (or connection lost), dispose networkService.
      // But if this is a LAN restart (both agreed), do NOT dispose socket.
      if (force || !(networkService?.isConnected ?? false)) {
        networkService?.dispose();
        networkService = null;
        isLanOpponentTurn = false;
      } else if (!lanRestart) {
        // For normal LAN reset, dispose the connection.
        networkService?.dispose();
        networkService = null;
        isLanOpponentTurn = false;
      }
      // Otherwise (lanRestart == true) keep the socket open.
    } else {
      networkService?.dispose();
      networkService = null;
      if (!force) {
        isLanOpponentTurn = false;
      }
    }

    if (isPosSetup && !force) {
      fen = gameRecorder.setupPosition;
    }

    // Reinitialize game objects
    _init(gameModeBak);

    lanHostPlaysWhite = savedHostPlaysWhite;

    // For LAN games, always start with White and set turn based on local color.
    if (gameModeBak == GameMode.humanVsLAN) {
      // The native session resets to white-to-move below; just
      // recompute who owes the next LAN move.
      final PieceColor localColor = getLocalColor();
      isLanOpponentTurn = localColor != PieceColor.white;
    }

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
  }

  /// S.of(context).starts a LAN game, either as a host or a client.
  ///
  /// [isHost]: If true, the player hosts the game; if false, the player joins as a client.
  /// [hostAddress]: The IP address of the host to connect to (required if not hosting).
  /// [port]: The port number to use for the LAN connection (default is 33333).
  /// [hostPlaysWhite]: If hosting, determines if the host plays White (true) or Black (false).
  /// [onClientConnected]: Callback triggered when a client connects to the host, passing client IP and port.
  void startLanGame({
    bool isHost = true,
    String? hostAddress,
    int port = 33333,
    bool hostPlaysWhite = true, // Explicitly enforce Host as White
    void Function(String, int)? onClientConnected,
  }) {
    gameInstance.gameMode = GameMode.humanVsLAN;
    lanHostPlaysWhite = hostPlaysWhite;

    headerIconsNotifier.showIcons();

    if (networkService == null || !networkService!.isConnected) {
      networkService?.dispose();
      networkService = NetworkService();
    }

    final BuildContext? currentContext =
        rootScaffoldMessengerKey.currentContext;

    final String connectedWaitingForOpponentSMove = currentContext != null
        ? S.of(currentContext).connectedWaitingForOpponentSMove
        : "Connected, waiting for opponent's move";

    try {
      if (isHost) {
        // Native session always starts with white-to-move.  The
        // legacy `Position.sideToMove = white` mirror is gone.
        DB().generalSettings = DB().generalSettings.copyWith(
          aiMovesFirst: false,
        );
        final PieceColor localColor = getLocalColor();
        isLanOpponentTurn =
            localColor != PieceColor.white; // Host moves first if white

        networkService!.startHost(
          port,
          onClientConnected: (String clientIp, int clientPort) {
            logger.i(
              "$_logTag onClientConnected => IP:$clientIp, port:$clientPort",
            );
            headerTipNotifier.showTip(
              "Client connected at $clientIp:$clientPort",
              snackBar: false,
            );
            // Ensure turn state is correct after connection
            isLanOpponentTurn = false; // Host moves first
            headerIconsNotifier.showIcons(); // Update icons immediately
            onClientConnected?.call(clientIp, clientPort);
          },
        );
      } else if (hostAddress != null) {
        // Native session starts with white-to-move; client (Black)
        // waits for Host's first move.
        DB().generalSettings = DB().generalSettings.copyWith(
          aiMovesFirst: true,
        );
        networkService!.connectToHost(hostAddress, port).then((_) {
          final PieceColor localColor = getLocalColor();
          isLanOpponentTurn = localColor != PieceColor.white;

          headerTipNotifier.showTip(
            connectedWaitingForOpponentSMove,
            snackBar: false,
          );
          onClientConnected?.call(hostAddress, port);
        });
      } else {
        logger.e("$_logTag Host address required when not hosting");
        headerTipNotifier.showTip("Error: Host address required");
        return;
      }

      boardSemanticsNotifier.updateSemantics();
    } catch (e) {
      logger.e("$_logTag LAN game setup failed: $e");
      headerTipNotifier.showTip("Failed to start LAN game: $e");
      resetLanState(); // Reset on failure
    }
  }

  // Reset LAN state cleanly
  void resetLanState() {
    if (gameInstance.gameMode == GameMode.humanVsLAN) {
      if (networkService?.isConnected != true) {
        networkService?.dispose();
        networkService = null;
      }
      isLanOpponentTurn = false; // Reset to Host's turn if Host
      // Native session reset elsewhere ensures white-to-move.
      headerIconsNotifier.showIcons(); // Force icon update
      boardSemanticsNotifier.updateSemantics();
    }
  }

  /// This method must be called right after any state change that may alter
  /// the side to move (local move, remote move, take-back, restart, etc).
  /// It keeps `isLanOpponentTurn` and the header tip consistent on both peers.
  void refreshLanTurn({bool showTip = true, bool snackBar = false}) {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      return;
    }
    final BuildContext? scopedContext = rootScaffoldMessengerKey.currentContext;
    final GameSession? scopedSession = scopedContext == null
        ? null
        : GameSessionScope.sessionOf(scopedContext);
    if (scopedSession is NativeMillGameSession && true) {
      isNativeLanOpponentTurn(scopedSession);
      _showLanTurnTip(showTip: showTip, snackBar: snackBar);
      headerIconsNotifier.showIcons();
      boardSemanticsNotifier.updateSemantics();
      return;
    }
    final GameStateSnapshot? nativeSnapshot = activeSessionSnapshot;
    final PieceColor localColor = getLocalColor();
    final PieceColor sideToMove = activeBoardView.sideToMove;
    final bool wasOpponentTurn = isLanOpponentTurn;
    isLanOpponentTurn = (sideToMove != localColor);
    logger.i(
      "$_logTag [LAN] refreshLanTurn: local=$localColor, sideToMove=$sideToMove, "
      "native=${nativeSnapshot != null}, "
      "isOpponentTurn: $wasOpponentTurn -> $isLanOpponentTurn",
    );
    if (showTip) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String ot = context != null
          ? S.of(context).opponentSTurn
          : "Opponent's turn";
      final String yt = context != null ? S.of(context).yourTurn : "Your turn";
      headerTipNotifier.showTip(
        isLanOpponentTurn ? ot : yt,
        snackBar: snackBar,
      );
    }
    headerIconsNotifier.showIcons();
    boardSemanticsNotifier.updateSemantics();
  }

  void _showLanTurnTip({required bool showTip, required bool snackBar}) {
    if (!showTip) {
      return;
    }
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String ot = context != null
        ? S.of(context).opponentSTurn
        : "Opponent's turn";
    final String yt = context != null ? S.of(context).yourTurn : "Your turn";
    headerTipNotifier.showTip(isLanOpponentTurn ? ot : yt, snackBar: snackBar);
  }

  /// Handles a move received from the LAN opponent
  void handleLanMove(String moveNotation) {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      logger.w("$_logTag Ignoring LAN move: wrong mode");
      return;
    }

    try {
      if (moveNotation.startsWith("request:aiMovesFirst")) {
        // Host receives a request from Client and returns the aiMovesFirst value
        final bool aiMovesFirst = DB().generalSettings.aiMovesFirst;
        networkService?.sendMove("response:aiMovesFirst:$aiMovesFirst");
        logger.i("$_logTag Sent aiMovesFirst: $aiMovesFirst to Client");
        return;
      }

      final GameSession? scopedSession =
          rootScaffoldMessengerKey.currentContext == null
          ? null
          : GameSessionScope.sessionOf(
              rootScaffoldMessengerKey.currentContext!,
            );
      if (scopedSession is NativeMillGameSession) {
        handleNativeLanMove(scopedSession, moveNotation);
        return;
      }
      // The native session is the only supported board source on
      // this branch; the legacy LAN fallback that mutated
      // `Position` directly is gone with the rule-machine cleanup.
      logger.w(
        "$_logTag LAN move arrived without an active "
        "NativeMillGameSession; ignoring '$moveNotation'.",
      );
    } catch (e) {
      logger.e("$_logTag Error processing LAN move: $e");
      headerTipNotifier.showTip("Error with opponent's move: $e");
    }
  }

  /// Sends a move to the LAN opponent
  void sendLanMove(String moveNotation) {
    if (gameInstance.gameMode != GameMode.humanVsLAN || isLanOpponentTurn) {
      logger.w("$_logTag Cannot send move: not your turn or wrong mode");
      return;
    }

    try {
      final String outbound = moveNotation;
      networkService?.sendMove(outbound);
      // After sending, toggle turn based on local color.
      // Prefer the native session's active seat when available to avoid
      // relying on the legacy position side-to-move.
      if (true) {
        final BuildContext? ctx = rootScaffoldMessengerKey.currentContext;
        final GameSession? session = ctx != null
            ? GameSessionScope.sessionOf(ctx)
            : null;
        if (session is NativeMillGameSession) {
          final LanSessionMeta? meta = session.lanMeta ?? activeNativeLanMeta;
          if (meta != null) {
            isLanOpponentTurn = meta.isOpponentTurn(
              session.state.value.activeSeat,
            );
          }
        }
      }
      logger.i("$_logTag Sent move to LAN opponent: $outbound");
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String ot = context != null
          ? S.of(context).opponentSTurn
          : "Opponent's turn";
      final String yt = context != null ? S.of(context).yourTurn : "Your turn";
      headerTipNotifier.showTip(isLanOpponentTurn ? ot : yt, snackBar: false);
    } catch (e) {
      logger.e("$_logTag Failed to send move: $e");
      headerTipNotifier.showTip("Failed to send move: $e");
    }
  }

  /// Sends a LAN take-back request (e.g. "take back:1:request").
  Future<bool> requestLanTakeBack(int steps) async {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      return false; // Not in LAN mode => ignore
    }
    if (steps != 1) {
      // We only allow single-step, so fail
      return false;
    }

    // If not connected or it's the opponent's turn, you might block:
    if (networkService == null || !networkService!.isConnected) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String notConnectedToLanOpponent = context != null
          ? S.of(context).notConnectedToLanOpponent
          : "You resigned, game over";
      headerTipNotifier.showTip(notConnectedToLanOpponent);
      return false;
    }
    if (isLanOpponentTurn) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String cannotRequestATakeBackWhenItSNotYourTurn = context != null
          ? S.of(context).cannotRequestATakeBackWhenItSNotYourTurn
          : "Cannot request a take back when it's not your turn";
      headerTipNotifier.showTip(cannotRequestATakeBackWhenItSNotYourTurn);
      return false;
    }

    // Register a short-lived callback to handle acceptance or rejection
    // Or do it more elegantly in `_handleNetworkMessage` with a separate global.
    // For a minimal approach, store a reference to the completer in a field:
    pendingTakeBackCompleter = Completer<bool>();

    networkService!.sendMove("take back:$steps:request");

    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String takeBackRequestSentToTheOpponent = context != null
        ? S.of(context).takeBackRequestSentToTheOpponent
        : "Take back request sent to the opponent";
    headerTipNotifier.showTip(
      takeBackRequestSentToTheOpponent,
      snackBar: false,
    );

    // We'll wait up to X seconds for the user to respond.
    // If the user never responds, we can consider it "rejected."
    Future<void>.delayed(const Duration(seconds: 30), () {
      if (pendingTakeBackCompleter != null &&
          !pendingTakeBackCompleter!.isCompleted) {
        pendingTakeBackCompleter!.complete(false);
      }
    });

    // Wait for the opponent's response
    return pendingTakeBackCompleter!.future;
  }

  /// Called when we receive "take back:1:request" from the opponent.
  void handleTakeBackRequest(int steps) {
    if (steps != 1) {
      // We only allow single-step in this requirement
      networkService?.sendMove("take back:$steps:rejected");
      return;
    }
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      // If no context, auto-reject
      networkService?.sendMove("take back:$steps:rejected");
      return;
    }
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).takeBackRequest),
          content: Text(
            S
                .of(dialogContext)
                .opponentRequestsTakeBackAccept(steps.toString()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
                networkService?.sendMove("take back:$steps:accepted");
                // Locally apply the 1-step rollback
                HistoryNavigator.doEachMove(HistoryNavMode.takeBack, 1);
                // Also mark the next turn, etc. as needed
              },
              child: Text(S.of(dialogContext).yes),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
                networkService?.sendMove("take back:$steps:rejected");
              },
              child: Text(S.of(dialogContext).no),
            ),
          ],
        );
      },
    );
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

  Future<EngineResponse> engineToGo(
    BuildContext context, {
    required bool isMoveNow,
  }) async {
    const String tag = "[engineToGo]";
    logger.i(
      "$tag entry: gameMode=${gameInstance.gameMode}, "
      "isMoveNow=$isMoveNow, isEngineRunning=$isEngineRunning, "
      "isControllerActive=$isControllerActive, "
      "activeSessionSnapshot=${activeSessionSnapshot != null}, "
      "_activeSession.runtimeType=${_activeSession.runtimeType}",
    );

    if (gameInstance.gameMode == GameMode.humanVsLAN) {
      // In LAN mode, we don't use the engine; moves come from the network
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
      logger.i(
        "$tag isMoveNow && isEngineRunning -> request native search abort.",
      );
      tgf.nativeMillSearchStop();
      return const EngineResponseSkip();
    }

    if (gameInstance.gameMode == GameMode.humanVsAi) {
      return _nativeSessionEngineToGo(context, isMoveNow: isMoveNow);
    }

    // AI vs AI must also drive the Rust/FRB native session.  The legacy
    // `engine.search()` path delegates UCI commands through method-channel
    // stubs (see `Engine.startup` doc) that no longer reach a real engine
    // thread, so without this branch clicking "New Game" while in AI vs AI
    // mode silently spins on `_waitResponse(["bestmove"])` and the board
    // never advances.  Route through the dedicated native loop instead.
    if (gameInstance.gameMode == GameMode.aiVsAi) {
      logger.i("$tag routing to _nativeAiVsAiLoop");
      return _nativeAiVsAiLoop(context, isMoveNow: isMoveNow);
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
  }) async {
    const String tag = "[engineToGo][native]";
    // Same fall-back as _nativeAiVsAiLoop -- prefer the
    // controller-bound active session so flows triggered from the
    // modal route still work even if the InheritedWidget probe via
    // context returns null.
    final GameSession? scopedFromContext = GameSessionScope.sessionOf(context);
    final GameSession? scopedSession = scopedFromContext ?? _activeSession;
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
      logger.i("$tag Applied native AI move ${action.payload['move']}");
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
  }) async {
    const String tag = "[engineToGo][native][aiVsAi]";
    // Resolve session via the controller-bound `_activeSession`
    // FIRST so we don't depend on the modal's BuildContext still
    // being inside the GameSessionScope InheritedWidget tree --
    // showModalBottomSheet routes inside the same Navigator, but we
    // saw scopedSession show up as null in some app states; the
    // controller-bound reference is set by Home.dart whenever the
    // active session changes and never goes stale on a mode switch.
    final GameSession? scopedFromContext = GameSessionScope.sessionOf(context);
    final GameSession? scopedSession = scopedFromContext ?? _activeSession;
    logger.i(
      "$tag enter: isMoveNow=$isMoveNow, "
      "scopedFromContext=${scopedFromContext.runtimeType}, "
      "_activeSession=${_activeSession.runtimeType}, "
      "resolved=${scopedSession.runtimeType}, "
      "isEngineRunning=$isEngineRunning",
    );
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
        logger.i(
          "$tag iter=$iteration begin: "
          "phase=${loopSession.state.value.phase}, "
          "activeSeat=${loopSession.state.value.activeSeat}, "
          "outcome.isTerminal=${loopSession.outcome.isTerminal}",
        );
        // Bail out if the active session has been rebuilt under us,
        // OR if the aiLoopEpoch has advanced (a fresh New Game spun
        // up another loop).  Either signal means this loop has been
        // superseded and must release the session to the new owner.
        if (!identical(_activeSession, loopSession)) {
          logger.i("$tag session was replaced; exiting old loop.");
          break;
        }
        if (aiLoopEpoch != loopEpoch) {
          logger.i(
            "$tag aiLoopEpoch advanced from $loopEpoch to $aiLoopEpoch;"
            " exiting old loop.",
          );
          break;
        }
        if (loopSession.outcome.isTerminal) {
          logger.i("$tag terminal outcome; exiting.");
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

        logger.i("$tag iter=$iteration calling playIfAiTurn");
        final Stopwatch sw = Stopwatch()..start();
        final GameAction? action = await aiTurnController.playIfAiTurn(
          loopSession,
        );
        sw.stop();
        logger.i(
          "$tag iter=$iteration playIfAiTurn returned in ${sw.elapsedMilliseconds}ms: "
          "action=${action?.payload['move'] ?? '(null)'}",
        );
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
        logger.i("$tag Applied native AI move ${action.payload['move']}");

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
          isEngineInDelay = true;
          await Future<void>.delayed(
            Duration(milliseconds: (animationDuration * 1000).toInt()),
          );
          isEngineInDelay = false;
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

  Future<void> moveNow(BuildContext context) async {
    const String tag = "[engineToGo]";
    bool reversed = false;

    loadedGameFilenamePrefix = null;

    if (isEngineInDelay) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).aiIsDelaying,
      );
    }

    if (AnalysisMode.isEnabled || AnalysisMode.isAnalyzing) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).analyzing,
      );
    }

    // Defensive: sideToMove may be PieceColor.nobody when the game is over
    // or before the first move; treat that as "not AI's turn".
    final PieceColor moveNowSide = activeBoardView.sideToMove;
    if (moveNowSide != PieceColor.white && moveNowSide != PieceColor.black) {
      return rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).notAIsTurn,
      );
    }

    if (gameInstance.isHumanToMove) {
      logger.i("$tag Human to Move. Temporarily swap AI and Human roles.");
      //return rootScaffoldMessengerKey.currentState!
      //    .showSnackBarClear(S.of(context).notAIsTurn);
      gameInstance.reverseWhoIsAi();
      reversed = true;
    }

    final String strTimeout = S.of(context).timeout;

    GameController().disableStats = true;

    final EngineResponse engineResponse = await engineToGo(
      context,
      isMoveNow: isEngineRunning,
    );

    if (!context.mounted) {
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
          await PerformanceWarningDialog.showIfNeeded(context);
        }
        break;
      case EngineNoBestMove():
        final List<ExtMove> moves = gameRecorder.mainlineMoves;
        await EngineFailureDialog.show(
          context,
          diagnosticContext: EngineFailureDialog.buildDiagnosticContext(
            fen: activeFen,
            phase: activeBoardView.phase.name,
            sideToMove: activeBoardView.sideToMove.playerName(context),
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
