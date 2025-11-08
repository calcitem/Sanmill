// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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
  factory GameController() => instance;

  GameController._() {
    _init(GameMode.humanVsAi);
  }

  static const String _logTag = "[Controller]";

  NetworkService? networkService;
  bool isLanOpponentTurn = false; // Tracks whose turn it is in LAN mode

  bool isDisposed = false;
  bool isControllerReady = false;
  bool isControllerActive = false;
  bool isEngineRunning = false;
  bool isEngineInDelay = false;
  bool isPieceMarkedInPositionSetup = false;

  bool lastMoveFromAI = false;

  bool disableStats = false;

  // Prevent concurrent Move Now actions that could trigger repeated stops
  // and epoch bumps on the engine side.
  bool _isMoveNowInProgress = false;

  String? value;
  AiMoveType? aiMoveType;

  late Game gameInstance;
  late Position position;
  late Position setupPosition;
  late Engine engine;

  /// Remembers whether the host chose White; used for header icon arrangement.
  bool? lanHostPlaysWhite;

  // Use this Completer to wait for the final "accepted" or "rejected" from remote.
  Completer<bool>? pendingTakeBackCompleter;

  // Game timing tracking
  DateTime? _gameStartTime;
  bool _gameStartTimeRecorded = false;

  final HeaderTipNotifier headerTipNotifier = HeaderTipNotifier();
  final HeaderIconsNotifier headerIconsNotifier = HeaderIconsNotifier();
  final SetupPositionNotifier setupPositionNotifier = SetupPositionNotifier();
  final GameResultNotifier gameResultNotifier = GameResultNotifier();
  final BoardSemanticsNotifier boardSemanticsNotifier =
      BoardSemanticsNotifier();

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

  @visibleForTesting
  static GameController instance = GameController._();

  /// S.of(context).starts up the controller. It will initialize the audio subsystem and heat the engine.
  Future<void> startController() async {
    if (_isInitialized) {
      return;
    }

    await SoundManager().loadSounds();

    _isInitialized = true;
    logger.i("$_logTag initialized");
  }

  /// Determines the local player's color based on whether they are Host or Client
  PieceColor getLocalColor() {
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

  /// Sends a restart request to the LAN opponent.
  /// This method is called when the local user requests a game restart.
  void requestRestart() {
    // TODO: Use S.of(context).restartRequestSentWaitingForOpponentSResponse
    if (gameInstance.gameMode == GameMode.humanVsLAN &&
        (networkService?.isConnected ?? false)) {
      // Send a restart request message to the opponent
      networkService!.sendMove("restart:request");
      // Optionally, show a tip that the request has been sent
    } else {
      // For non-LAN modes, simply reset the game.
      reset();
    }
  }

  /// Handles a restart request received from the opponent.
  /// Shows a confirmation dialog; if accepted, sends "restart:accepted" and resets game;
  /// otherwise, sends "restart:rejected".
  void handleRestartRequest() {
    // Use a global navigator context to guarantee Navigator availability
    final BuildContext? context = currentNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Restart Request"),
          content: Text(
            S.of(dialogContext).opponentRequestedToRestartTheGameDoYouAccept,
          ),
          actions: <Widget>[
            TextButton(
              // If accepted, send accepted message and reset game (LAN socket remains open)
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
                networkService?.sendMove("restart:accepted");
                // Call reset with lanRestart flag true (do not dispose networkService)
                reset(lanRestart: true);
              },
              child: const Text("Yes"),
            ),
            TextButton(
              // If rejected, send rejected message and do nothing
              onPressed: () {
                // Cache the localized string before dismissing the dialog.
                final String rejectedMessage = S
                    .of(dialogContext)
                    .restartRequestRejected;
                Navigator.of(dialogContext).pop(false);
                networkService?.sendMove("restart:rejected");
                headerTipNotifier.showTip(rejectedMessage);
              },
              child: const Text("No"),
            ),
          ],
        );
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

    // In LAN mode, confirm with the player first (Navigator must be present)
    final BuildContext? context = currentNavigatorKey.currentContext;
    if (context == null) {
      return;
    }

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(context).confirmResignation),
          content: const Text(
            "S.of(context).areYouSureYouWantToResignThisGame",
          ),
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

                  // Get the opponent's color (winner)
                  final PieceColor localColor = getLocalColor();
                  final PieceColor winnerColor = localColor.opponent;

                  // Set game over with opponent as winner
                  position.setGameOver(
                    winnerColor,
                    GameOverReason.loseResign, // Using a generic reason
                  );

                  // Show resignation message
                  headerTipNotifier.showTip(
                    "S.of(context).youResignedGameOver",
                  );
                  gameResultNotifier.showResult(force: true);

                  // Play sound if enabled
                  SoundManager().playTone(Sound.lose);
                } catch (e) {
                  logger.e("$_logTag Failed to send resignation: $e");
                  headerTipNotifier.showTip("Failed to send resignation: $e");
                }
              },
              child: const Text("Resign"),
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
      // Get the local color (winner)
      final PieceColor localColor = getLocalColor();

      // Set game over with local player as winner
      position.setGameOver(
        localColor,
        GameOverReason.loseResign, // Using a generic reason for now
      );

      // Update UI
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      if (context != null) {
        headerTipNotifier.showTip(S.of(context).opponentResignedYouWin);
      } else {
        headerTipNotifier.showTip("Opponent resigned, you win");
      }
      gameResultNotifier.showResult(force: true);
      isLanOpponentTurn = false;

      // Play sound if enabled
      SoundManager().playTone(Sound.win);

      logger.i("$_logTag Handled opponent resignation");
    } catch (e) {
      logger.e("$_logTag Error handling resignation: $e");
      headerTipNotifier.showTip("Error handling opponent resignation");
    }
  }

  /// Handles resignation in non-LAN modes (e.g., vs AI)
  void _handleLocalResignation() {
    // Determine winner (opponent of current player)
    final PieceColor winnerColor = position.sideToMove.opponent;

    // Set game over state
    position.setGameOver(
      winnerColor,
      GameOverReason.drawStalemateCondition, // Using a generic reason
    );

    // Update UI
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    final String youResignedGameOver = context != null
        ? S.of(context).youResignedGameOver
        : "You resigned, game over";
    headerTipNotifier.showTip(youResignedGameOver);
    gameResultNotifier.showResult(force: true);

    // Play sound if enabled
    SoundManager().playTone(Sound.win);

    logger.i("$_logTag Local player resigned. Winner: $winnerColor");
  }

  /// Modify the reset method so that in LAN restart mode the socket is preserved.
  void reset({bool force = false, bool lanRestart = false}) {
    final GameMode gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPosSetup = isPositionSetup;
    final bool? savedHostPlaysWhite = lanHostPlaysWhite;

    value = "0";
    aiMoveType = AiMoveType.unknown;
    engine.stopSearching();
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

    // After reinitialization, mark controller as active (not disposed)
    // to allow engine to wait for responses normally.
    isDisposed = false;

    lanHostPlaysWhite = savedHostPlaysWhite;

    // For LAN games, always start with White and set turn based on local color.
    if (gameModeBak == GameMode.humanVsLAN) {
      position.sideToMove = PieceColor.white;
      final PieceColor localColor = getLocalColor();
      isLanOpponentTurn = (position.sideToMove != localColor);
    }

    if (isPosSetup && !force && fen != null) {
      gameRecorder.setupPosition = fen;
      gameRecorder.lastPositionWithRemove = fen;
      position.setFen(fen);
    }

    gameInstance.gameMode = gameModeBak;
    GifShare().captureView(first: true);

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
    position = Position();
    position.reset();
    gameInstance = Game(gameMode: mode);
    engine = Engine();
    gameRecorder = GameRecorder(lastPositionWithRemove: position.fen);

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
    logger.i(
      "$_logTag [LAN] startLanGame() called - isHost: $isHost, port: $port, hostPlaysWhite: $hostPlaysWhite",
    );
    if (hostAddress != null) {
      logger.i("$_logTag [LAN] Target host address: $hostAddress");
    }

    gameInstance.gameMode = GameMode.humanVsLAN;
    lanHostPlaysWhite = hostPlaysWhite;
    logger.i("$_logTag [LAN] Game mode set to humanVsLAN");

    headerIconsNotifier.showIcons();

    if (networkService == null || !networkService!.isConnected) {
      logger.i(
        "$_logTag [LAN] Creating new NetworkService (existing was ${networkService == null ? 'null' : 'not connected'})",
      );
      networkService?.dispose();
      networkService = NetworkService();
    } else {
      logger.i("$_logTag [LAN] Reusing existing connected NetworkService");
    }

    final BuildContext? currentContext =
        rootScaffoldMessengerKey.currentContext;

    final String connectedWaitingForOpponentSMove = currentContext != null
        ? S.of(currentContext).connectedWaitingForOpponentSMove
        : "Connected, waiting for opponent's move";

    try {
      if (isHost) {
        logger.i("$_logTag [LAN] Starting as HOST");
        position.sideToMove = PieceColor.white; // Host starts as White
        DB().generalSettings = DB().generalSettings.copyWith(
          aiMovesFirst: false,
        );
        final PieceColor localColor = getLocalColor();
        isLanOpponentTurn =
            (position.sideToMove != localColor); // Should be false for Host
        logger.i(
          "$_logTag [LAN] Host setup - localColor: $localColor, sideToMove: ${position.sideToMove}, isOpponentTurn: $isLanOpponentTurn",
        );

        networkService!.startHost(
          port,
          onClientConnected: (String clientIp, int clientPort) {
            logger.i(
              "$_logTag [LAN] Client connected callback - IP: $clientIp, port: $clientPort",
            );
            headerTipNotifier.showTip(
              "Client connected at $clientIp:$clientPort",
              snackBar: false,
            );
            // Ensure turn state is correct after connection
            isLanOpponentTurn = false; // Host moves first
            logger.i(
              "$_logTag [LAN] Set isLanOpponentTurn to false (host moves first)",
            );
            headerIconsNotifier.showIcons(); // Update icons immediately
            onClientConnected?.call(clientIp, clientPort);
          },
        );
      } else if (hostAddress != null) {
        logger.i(
          "$_logTag [LAN] Starting as CLIENT connecting to $hostAddress:$port",
        );
        position.sideToMove = PieceColor.white; // Game starts with White
        DB().generalSettings = DB().generalSettings.copyWith(
          aiMovesFirst: true,
        );
        networkService!
            .connectToHost(hostAddress, port)
            .then((_) {
              logger.i("$_logTag [LAN] Client successfully connected to host");
              final PieceColor localColor = getLocalColor();
              isLanOpponentTurn = (position.sideToMove != localColor);
              logger.i(
                "$_logTag [LAN] Client setup - localColor: $localColor, sideToMove: ${position.sideToMove}, isOpponentTurn: $isLanOpponentTurn",
              );

              headerTipNotifier.showTip(
                connectedWaitingForOpponentSMove,
                snackBar: false,
              );
              onClientConnected?.call(hostAddress, port);
            })
            .catchError((error) {
              logger.e("$_logTag [LAN] Client connection error: $error");
              headerTipNotifier.showTip("Connection failed: $error");
            });
      } else {
        logger.e(
          "$_logTag [LAN] Error: Host address required when not hosting",
        );
        headerTipNotifier.showTip("Error: Host address required");
        return;
      }

      boardSemanticsNotifier.updateSemantics();
      logger.i("$_logTag [LAN] LAN game setup initiated successfully");
    } catch (e, st) {
      logger.e("$_logTag [LAN] LAN game setup failed: $e");
      logger.d("$_logTag [LAN] Stack trace: $st");
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
      position.sideToMove = PieceColor.white; // Ensure White starts
      headerIconsNotifier.showIcons(); // Force icon update
      boardSemanticsNotifier.updateSemantics();
    }
  }

  /// Handles a move received from the LAN opponent
  void handleLanMove(String moveNotation) {
    if (gameInstance.gameMode != GameMode.humanVsLAN) {
      logger.w(
        "$_logTag [LAN] Ignoring move - not in LAN mode (current: ${gameInstance.gameMode})",
      );
      return;
    }

    logger.i("$_logTag [LAN] handleLanMove() called with: $moveNotation");
    logger.i("$_logTag [LAN] Current position: ${position.fen}");
    logger.i(
      "$_logTag [LAN] Current turn: ${position.sideToMove}, isLanOpponentTurn: $isLanOpponentTurn",
    );

    try {
      if (moveNotation.startsWith("request:aiMovesFirst")) {
        logger.i("$_logTag [LAN] Received aiMovesFirst request from client");
        // Host receives a request from Client and returns the aiMovesFirst value
        final bool aiMovesFirst = DB().generalSettings.aiMovesFirst;
        networkService?.sendMove("response:aiMovesFirst:$aiMovesFirst");
        logger.i(
          "$_logTag [LAN] Sent aiMovesFirst response: $aiMovesFirst to client",
        );
        return;
      }

      logger.i("$_logTag [LAN] Creating ExtMove from notation: $moveNotation");
      final ExtMove move = ExtMove(
        moveNotation,
        // Use current sideToMove as the moving side on receiver
        side: position.sideToMove,
      );

      logger.i("$_logTag [LAN] Attempting to apply move: ${move.notation}");
      if (gameInstance.doMove(move)) {
        logger.i("$_logTag [LAN] Move applied successfully");
        // Update turn based on local color
        // In LAN vs LAN mode, after receiving opponent's move, we should be able to play
        // So when position.sideToMove != localColor (opponent just played), it's our turn
        final PieceColor localColor = getLocalColor();
        final bool wasOpponentTurn = isLanOpponentTurn;
        // Opponent's turn means: sideToMove is NOT localColor
        isLanOpponentTurn = (position.sideToMove != localColor);
        logger.i(
          "$_logTag [LAN] Turn updated - local: $localColor, current: ${position.sideToMove}, isOpponentTurn: $wasOpponentTurn -> $isLanOpponentTurn",
        );
        boardSemanticsNotifier.updateSemantics();

        final BuildContext? context = rootScaffoldMessengerKey.currentContext;
        final String ot = context != null
            ? S.of(context).opponentSTurn
            : "Opponent's turn";
        final String yt = context != null
            ? S.of(context).yourTurn
            : "Your turn";
        // Derive tip directly from actual side-to-move to avoid stale flags
        final bool isMyTurn = (position.sideToMove == localColor);
        headerTipNotifier.showTip(isMyTurn ? yt : ot, snackBar: false);
        logger.i("$_logTag [LAN] Move processed successfully: $moveNotation");
        logger.i("$_logTag [LAN] New position: ${position.fen}");

        gameRecorder.appendMoveIfDifferent(move);
        if (position.phase == Phase.gameOver) {
          logger.i("$_logTag [LAN] Game is over after opponent's move");
          gameResultNotifier.showResult(force: true);
        }
      } else {
        logger.e("$_logTag [LAN] Invalid move received: $moveNotation");
        logger.e("$_logTag [LAN] Position state: ${position.fen}");
        logger.e(
          "$_logTag [LAN] Expected side to move: ${position.sideToMove}",
        );
        headerTipNotifier.showTip("Opponent sent an invalid move");
      }
    } catch (e, st) {
      logger.e("$_logTag [LAN] Error processing LAN move '$moveNotation': $e");
      logger.d("$_logTag [LAN] Stack trace: $st");
      headerTipNotifier.showTip("Error with opponent's move: $e");
    }
  }

  /// Sends a move to the LAN opponent
  void sendLanMove(String moveNotation) {
    logger.i("$_logTag [LAN] sendLanMove() called with: $moveNotation");
    logger.i(
      "$_logTag [LAN] Game mode: ${gameInstance.gameMode}, isLanOpponentTurn: $isLanOpponentTurn",
    );

    if (gameInstance.gameMode != GameMode.humanVsLAN || isLanOpponentTurn) {
      logger.w(
        "$_logTag [LAN] Cannot send move - mode: ${gameInstance.gameMode}, isOpponentTurn: $isLanOpponentTurn",
      );
      return;
    }

    try {
      logger.i("$_logTag [LAN] Sending move to opponent: $moveNotation");
      logger.i("$_logTag [LAN] Current position before send: ${position.fen}");
      networkService?.sendMove(moveNotation);

      // After sending our move, it becomes opponent's turn
      // In LAN vs LAN mode, when position.sideToMove == localColor (we just played), it's opponent's turn
      final PieceColor localColor = getLocalColor();
      final bool wasOpponentTurn = isLanOpponentTurn;
      // Opponent's turn means: sideToMove is NOT localColor
      isLanOpponentTurn = (position.sideToMove != localColor);
      logger.i("$_logTag [LAN] Move sent successfully");
      logger.i(
        "$_logTag [LAN] Turn updated - local: $localColor, current: ${position.sideToMove}, isOpponentTurn: $wasOpponentTurn -> $isLanOpponentTurn",
      );

      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String ot = context != null
          ? S.of(context).opponentSTurn
          : "Opponent's turn";
      final String yt = context != null ? S.of(context).yourTurn : "Your turn";
      // Derive tip directly from actual side-to-move to avoid stale flags
      final bool isMyTurn = (position.sideToMove == localColor);
      headerTipNotifier.showTip(isMyTurn ? yt : ot, snackBar: false);
    } catch (e, st) {
      logger.e("$_logTag [LAN] Failed to send move '$moveNotation': $e");
      logger.d("$_logTag [LAN] Stack trace: $st");
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
    // Only allow take-back immediately after your move, i.e., while it's opponent's turn
    if (!isLanOpponentTurn) {
      final BuildContext? context = rootScaffoldMessengerKey.currentContext;
      final String msg = context != null
          ? S.of(context).canOnlyRequestTakeBackRightAfterYourMove
          : "You can only request a take back immediately after your move.";
      headerTipNotifier.showTip(msg);
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
    // Use the global navigator key context to ensure a Navigator is present
    final BuildContext? context = currentNavigatorKey.currentContext;
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
            "Opponent requests to take back $steps move(s). Accept?",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
                networkService?.sendMove("take back:$steps:accepted");
                // Locally apply the 1-step rollback
                HistoryNavigator.doEachMove(HistoryNavMode.takeBack, 1);
                // Update turn state after rollback: if sideToMove != localColor, it's opponent's turn
                final PieceColor localColor = getLocalColor();
                isLanOpponentTurn = (position.sideToMove != localColor);
                // Refresh icons/semantics and tip to reflect new turn state
                headerIconsNotifier.showIcons();
                boardSemanticsNotifier.updateSemantics();
                final BuildContext? ctx =
                    rootScaffoldMessengerKey.currentContext;
                if (ctx != null) {
                  final String ot = S.of(ctx).opponentSTurn;
                  final String yt = S.of(ctx).yourTurn;
                  headerTipNotifier.showTip(
                    isLanOpponentTurn ? ot : yt,
                    snackBar: false,
                  );
                }
              },
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
                networkService?.sendMove("take back:$steps:rejected");
              },
              child: const Text("No"),
            ),
          ],
        );
      },
    );
  }

  bool isAutoRestart() {
    if (EnvironmentConfig.devMode == true) {
      return DB().generalSettings.isAutoRestart && position.isNoDraw() == false;
    }

    return DB().generalSettings.isAutoRestart;
  }

  // TODO: [Leptopoda] The reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<EngineResponse> engineToGo(
    BuildContext context, {
    required bool isMoveNow,
  }) async {
    const String tag = "[engineToGo]";

    if (gameInstance.gameMode == GameMode.humanVsLAN) {
      // In LAN mode, we don't use the engine; moves come from the network
      return const EngineResponseHumanOK();
    }

    late EngineRet engineRet;

    bool searched = false;
    bool loopIsFirst = true;

    final String aiStr = S.of(context).ai;
    final String thinkingStr = S.of(context).thinking;
    final String humanStr = S.of(context).human;

    final GameMode gameMode = gameInstance.gameMode;
    final bool isGameRunning = position.winner == PieceColor.nobody;

    // If isMoveNow but it's actually humanToMove, skip
    if (isMoveNow && gameInstance.isHumanToMove) {
      return const EngineResponseSkip();
    }

    // Instead of .isAtEnd(), you might do something like:
    // if (isMoveNow && !gameRecorder.isAtEnd()) { ... } or remove it entirely
    // Here, we just remove it for minimal code:
    // if (isMoveNow && !gameRecorder.isAtEnd()) {
    //   return const EngineResponseSkip();
    // }

    if (!isMoveNow && position._checkIfGameIsOver()) {
      return const EngineGameIsOver();
    }

    if (isEngineRunning && !isMoveNow) {
      // TODO: Monkey test trigger
      logger.t("$tag engineToGo() is still running, skip.");
      return const EngineResponseSkip();
    }

    isEngineRunning = true;
    isControllerActive = true;

    // Start AI's timer when AI starts thinking
    // This ensures the countdown appears during AI's turn
    if (gameInstance.isAiSideToMove && gameMode == GameMode.humanVsAi) {
      // Start timer only if AI has a time limit (moveTime > 0)
      // When moveTime is 0, AI has unlimited thinking time
      PlayerTimer().start();
    }

    // TODO
    logger.t("$tag engine type is $gameMode");

    if (gameMode == GameMode.humanVsAi &&
        position.phase == Phase.moving &&
        !isMoveNow &&
        DB().ruleSettings.mayFly &&
        DB().generalSettings.remindedOpponentMayFly == false &&
        (position.pieceOnBoardCount[position.sideToMove]! <=
                DB().ruleSettings.flyPieceCount &&
            position.pieceOnBoardCount[position.sideToMove]! >= 3)) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        CustomSnackBar(
          S.of(context).enteredFlyingPhase,
          duration: const Duration(seconds: 8),
        ),
      );
      DB().generalSettings = DB().generalSettings.copyWith(
        remindedOpponentMayFly: true,
      );
    }

    while ((gameInstance.isAiSideToMove &&
            (isGameRunning || isAutoRestart())) &&
        isControllerActive) {
      if (gameMode == GameMode.aiVsAi) {
        headerTipNotifier.showTip(position.scoreString, snackBar: false);
      } else {
        headerTipNotifier.showTip(thinkingStr, snackBar: false);
        showSnakeBarHumanNotation(humanStr);
      }

      headerIconsNotifier.showIcons();
      boardSemanticsNotifier.updateSemantics();

      try {
        logger.t("$tag Searching..., isMoveNow: $isMoveNow");

        if (position.pieceOnBoardCount[PieceColor.black]! > 0) {
          isEngineInDelay = true;
          await Future<void>.delayed(
            Duration(
              milliseconds: (DB().displaySettings.animationDuration * 1000)
                  .toInt(),
            ),
          );
          isEngineInDelay = false;
        }

        engineRet = await engine.search(moveNow: loopIsFirst && isMoveNow);

        if (!isControllerActive) {
          break;
        }

        // TODO: Unify return and throw
        if (!gameInstance.doMove(engineRet.extMove!)) {
          // TODO: Should catch it and throw.
          isEngineRunning = false;
          return const EngineNoBestMove();
        }

        loopIsFirst = false;
        searched = true;

        // Record game start time for AI vs AI mode on first move
        _recordGameStartTime();

        // TODO: Do not use BuildContexts across async gaps.
        if (DB().generalSettings.screenReaderSupport) {
          rootScaffoldMessengerKey.currentState!.showSnackBar(
            CustomSnackBar("$aiStr: ${engineRet.extMove!.notation}"),
          );
        }
      } on EngineTimeOut {
        logger.i("$tag Engine response type: timeout");
        // In AI vs AI mode, auto-recover from timeout and retry
        if (gameMode == GameMode.aiVsAi) {
          await engine.stopSearching();
          // Brief delay to avoid hitting stale session immediately
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        isEngineRunning = false;
        return const EngineTimeOut();
      } on EngineNoBestMove {
        logger.i("$tag Engine response type: nobestmove");
        if (gameMode == GameMode.aiVsAi) {
          await engine.stopSearching();
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        isEngineRunning = false;
        return const EngineNoBestMove();
      }

      value = engineRet.value;
      aiMoveType = engineRet.aiMoveType;

      if (value != null && aiMoveType != AiMoveType.unknown) {
        lastMoveFromAI = true;
      }

      if (position.winner != PieceColor.nobody) {
        if (isAutoRestart()) {
          reset();
        } else {
          isEngineRunning = false;
          if (gameMode == GameMode.aiVsAi) {
            headerTipNotifier.showTip(position.scoreString, snackBar: false);
            headerIconsNotifier.showIcons();
            boardSemanticsNotifier.updateSemantics();
          }
          // Always call showResult to trigger UI update, dialog display is handled in GameBoard
          gameResultNotifier.showResult(force: true);
          return const EngineResponseOK();
        }
      }
    }

    isEngineRunning = false;

    // TODO: Why need not update tip and icons?
    boardSemanticsNotifier.updateSemantics();

    // After AI makes a move, start the human player's timer if needed
    if (gameInstance.gameMode == GameMode.humanVsAi) {
      PlayerTimer().start();
    }

    return searched ? const EngineResponseOK() : const EngineResponseHumanOK();
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

    // TODO: WAR
    if (position.sideToMove != PieceColor.white &&
        position.sideToMove != PieceColor.black) {
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
    final String strNoBestMoveErr = S.of(context).error(S.of(context).noMove);

    GameController().disableStats = true;

    // If AI is already thinking, just send a soft stop to fetch the
    // current best move from the ongoing search, and return without
    // spawning another engineToGo loop.
    if (!reversed && isEngineRunning) {
      final bool aiThinking = await engine.isThinking();
      if (aiThinking) {
        await engine.stopSoft();
        headerTipNotifier.showTip(S.of(context).thinking, snackBar: false);
        return;
      }
    }
    if (_isMoveNowInProgress) {
      return; // silently ignore repeated taps
    }
    _isMoveNowInProgress = true;
    try {
      switch (await engineToGo(context, isMoveNow: isEngineRunning)) {
        case EngineResponseOK():
        case EngineGameIsOver():
          gameResultNotifier.showResult(force: true);
          break;
        case EngineResponseHumanOK():
          gameResultNotifier.showResult();
          break;
        case EngineTimeOut():
          headerTipNotifier.showTip(strTimeout);
          break;
        case EngineNoBestMove():
          headerTipNotifier.showTip(strNoBestMoveErr);
          break;
        case EngineResponseSkip():
          headerTipNotifier.showTip("Error: Skip"); // TODO
          break;
        default:
          logger.e("$tag Unknown engine response type.");
          break;
      }
    } finally {
      if (reversed) {
        gameInstance.reverseWhoIsAi();
      }
      _isMoveNowInProgress = false;
    }
  }

  void showSnakeBarHumanNotation(String humanStr) {
    final List<ExtMove> moves = gameRecorder.mainlineMoves;
    final ExtMove? lastMove = moves.isNotEmpty ? moves.last : null;
    final String? n = lastMove?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        position.action != Act.remove &&
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
    return ExportService.exportGame(context, shouldPop: shouldPop);
  }

  // Add method to run and display analysis
  Future<void> runAnalysis() async {
    // Set analyzing flag to true before starting analysis
    AnalysisMode.setAnalyzing(true);

    final PositionAnalysisResult result = await engine.analyzePosition();

    // Reset analyzing flag
    AnalysisMode.setAnalyzing(false);

    if (result.isValid && result.possibleMoves.isNotEmpty) {
      // Enable analysis mode with the results
      AnalysisMode.enable(result.possibleMoves);

      // Force a redraw of the board to show analysis results
      boardSemanticsNotifier.updateSemantics();

      // Show success message
      headerTipNotifier.showTip(
        "Analysis complete. Green = win, Yellow = draw, Red = loss",
      );
    } else {
      // Show error message if analysis failed
      final String errorMsg = result.errorMessage ?? "Analysis failed";
      headerTipNotifier.showTip(errorMsg);
    }
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
