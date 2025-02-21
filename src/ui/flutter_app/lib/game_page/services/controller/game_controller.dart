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
  bool isPositionSetupMarkedPiece =
      false; // TODO: isPieceMarkedInPositionSetup?

  bool lastMoveFromAI = false;

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

  final HeaderTipNotifier headerTipNotifier = HeaderTipNotifier();
  final HeaderIconsNotifier headerIconsNotifier = HeaderIconsNotifier();
  final SetupPositionNotifier setupPositionNotifier = SetupPositionNotifier();
  final GameResultNotifier gameResultNotifier = GameResultNotifier();
  final BoardSemanticsNotifier boardSemanticsNotifier =
      BoardSemanticsNotifier();

  late GameRecorder gameRecorder;
  GameRecorder? newGameRecorder;

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

  /// Starts up the controller. It will initialize the audio subsystem and heat the engine.
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
    if (gameInstance.gameMode == GameMode.humanVsLAN &&
        (networkService?.isConnected ?? false)) {
      // Send a restart request message to the opponent
      networkService!.sendMove("restart:request");
      // Optionally, show a tip that the request has been sent
      headerTipNotifier
          .showTip("Restart request sent. Waiting for opponent's response.");
    } else {
      // For non-LAN modes, simply reset the game.
      reset();
    }
  }

  /// Handles a restart request received from the opponent.
  /// Shows a confirmation dialog; if accepted, sends "restart:accepted" and resets game;
  /// otherwise, sends "restart:rejected".
  void handleRestartRequest() {
    // Use a global context (e.g. rootScaffoldMessengerKey.currentContext) to show the dialog.
    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Restart Request"),
          content: const Text(
              "Opponent requested to restart the game. Do you accept?"),
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
                Navigator.of(dialogContext).pop(false);
                networkService?.sendMove("restart:rejected");
                headerTipNotifier.showTip("Restart request rejected.");
              },
              child: const Text("No"),
            ),
          ],
        );
      },
    );
  }

  /// Modify the reset method so that in LAN restart mode the socket is preserved.
  void reset({bool force = false, bool lanRestart = false}) {
    final GameMode gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPosSetup = isPositionSetup;

    value = "0";
    aiMoveType = AiMoveType.unknown;
    engine.stopSearching();

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
    // Optionally, show a tip that the game has been restarted.
    headerTipNotifier.showTip("Game restarted.");
  }

  /// Starts the current game.
  ///
  /// This method is suitable to use for starting a new game.
  void _startGame() {
    // Placeholder for future implementation
  }

  void _init(GameMode mode) {
    position = Position();
    gameInstance = Game(gameMode: mode);
    engine = Engine();
    gameRecorder = GameRecorder(lastPositionWithRemove: position.fen);

    _startGame();
  }

  /// Starts a LAN game, either as a host or a client.
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
    lanHostPlaysWhite = true; // Host always plays White

    headerIconsNotifier.showIcons();

    if (networkService == null || !networkService!.isConnected) {
      networkService?.dispose();
      networkService = NetworkService();
    }

    try {
      if (isHost) {
        position.sideToMove = PieceColor.white; // Host starts as White
        DB().generalSettings =
            DB().generalSettings.copyWith(aiMovesFirst: false);
        final PieceColor localColor = getLocalColor();
        isLanOpponentTurn =
            (position.sideToMove != localColor); // Should be false for Host

        networkService!.startHost(port,
            onClientConnected: (String clientIp, int clientPort) {
          logger.i(
              "$_logTag onClientConnected => IP:$clientIp, port:$clientPort");
          headerTipNotifier.showTip("Client connected at $clientIp:$clientPort",
              snackBar: false);
          // Ensure turn state is correct after connection
          isLanOpponentTurn = false; // Host moves first
          headerIconsNotifier.showIcons(); // Update icons immediately
          onClientConnected?.call(clientIp, clientPort);
        });
      } else if (hostAddress != null) {
        position.sideToMove = PieceColor.white; // Game starts with White
        DB().generalSettings =
            DB().generalSettings.copyWith(aiMovesFirst: true);
        networkService!.connectToHost(hostAddress, port).then((_) {
          final PieceColor localColor = getLocalColor();
          isLanOpponentTurn = (position.sideToMove != localColor);
          headerTipNotifier.showTip("Connected, waiting for opponent's move",
              snackBar: false);
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
      position.sideToMove = PieceColor.white; // Ensure White starts
      headerIconsNotifier.showIcons(); // Force icon update
      boardSemanticsNotifier.updateSemantics();
    }
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

      final ExtMove move = ExtMove(
        moveNotation,
        side: position.sideToMove.opponent,
      );

      if (gameInstance.doMove(move)) {
        // Update turn based on local color
        final PieceColor localColor = getLocalColor();
        isLanOpponentTurn = (position.sideToMove != localColor);
        boardSemanticsNotifier.updateSemantics();
        headerTipNotifier.showTip(
          isLanOpponentTurn ? "Opponent's turn" : "Your turn",
          snackBar: false,
        );
        logger.i("$_logTag Successfully processed LAN move: $moveNotation");

        gameRecorder.appendMoveIfDifferent(move);
        if (position.phase == Phase.gameOver) {
          gameResultNotifier.showResult(force: true);
        }
      } else {
        logger.e("$_logTag Invalid move received from LAN: $moveNotation");
        headerTipNotifier.showTip("Opponent sent an invalid move");
      }
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
      networkService?.sendMove(moveNotation);
      // After sending, toggle turn based on local color
      final PieceColor localColor = getLocalColor();
      isLanOpponentTurn = (position.sideToMove != localColor);
      logger.i("$_logTag Sent move to LAN opponent: $moveNotation");
      headerTipNotifier.showTip(
        isLanOpponentTurn ? "Opponent's turn" : "Your turn",
        snackBar: false,
      );
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
      headerTipNotifier.showTip("Not connected to LAN opponent.");
      return false;
    }
    if (isLanOpponentTurn) {
      headerTipNotifier
          .showTip("Cannot request a take back when it's not your turn.");
      return false;
    }

    // Register a short-lived callback to handle acceptance or rejection
    // Or do it more elegantly in `_handleNetworkMessage` with a separate global.
    // For a minimal approach, store a reference to the completer in a field:
    pendingTakeBackCompleter = Completer<bool>();

    networkService!.sendMove("take back:$steps:request");
    headerTipNotifier.showTip("Take back request sent to the opponent.",
        snackBar: false);

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
          title: const Text("Take Back Request"),
          content:
              Text("Opponent requests to take back $steps move(s). Accept?"),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
                networkService?.sendMove("take back:$steps:accepted");
                // Locally apply the 1-step rollback
                HistoryNavigator.doEachMove(HistoryNavMode.takeBack, 1);
                // Also mark the next turn, etc. as needed
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
        CustomSnackBar(S.of(context).enteredFlyingPhase,
            duration: const Duration(seconds: 8)),
      );
      DB().generalSettings = DB().generalSettings.copyWith(
            remindedOpponentMayFly: true,
          );
    }

    while (
        (gameInstance.isAiSideToMove && (isGameRunning || isAutoRestart())) &&
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
          await Future<void>.delayed(Duration(
            milliseconds:
                (DB().displaySettings.animationDuration * 1000).toInt(),
          ));
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

        // TODO: Do not use BuildContexts across async gaps.
        if (DB().generalSettings.screenReaderSupport) {
          rootScaffoldMessengerKey.currentState!.showSnackBar(
              CustomSnackBar("$aiStr: ${engineRet.extMove!.notation}"));
        }
      } on EngineTimeOut {
        logger.i("$tag Engine response type: timeout");
        isEngineRunning = false;
        return const EngineTimeOut();
      } on EngineNoBestMove {
        logger.i("$tag Engine response type: nobestmove");
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
          return const EngineResponseOK();
        }
      }
    }

    isEngineRunning = false;

    // TODO: Why need not update tip and icons?
    boardSemanticsNotifier.updateSemantics();

    return searched ? const EngineResponseOK() : const EngineResponseHumanOK();
  }

  Future<void> moveNow(BuildContext context) async {
    const String tag = "[engineToGo]";
    bool reversed = false;

    loadedGameFilenamePrefix = null;

    if (isEngineInDelay) {
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).aiIsDelaying);
    }

    // TODO: WAR
    if (position.sideToMove != PieceColor.white &&
        position.sideToMove != PieceColor.black) {
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
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

    switch (await engineToGo(context, isMoveNow: isEngineRunning)) {
      case EngineResponseOK():
      case EngineGameIsOver():
        gameResultNotifier.showResult(force: true);
        break;
      case EngineResponseHumanOK():
        gameResultNotifier.showResult(force: false);
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

    if (reversed) {
      gameInstance.reverseWhoIsAi();
    }
  }

  void showSnakeBarHumanNotation(String humanStr) {
    final List<ExtMove> moves = gameRecorder.mainlineMoves;
    final ExtMove? lastMove = moves.isNotEmpty ? moves.last : null;
    final String? n = lastMove?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        position.action != Act.remove &&
        n != null) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("$humanStr: $n"));
    }
  }

  Future<void> gifShare(BuildContext context) async {
    headerTipNotifier.showTip(S.of(context).pleaseWait);
    final String done = S.of(context).done;
    await GifShare().captureView();
    headerTipNotifier.showTip(done);

    GifShare().shareGif();
  }

  /// Starts a game save.
  static Future<String?> save(BuildContext context,
      {bool shouldPop = true}) async {
    return LoadService.saveGame(context, shouldPop: shouldPop);
  }

  /// Starts a game load.
  static Future<void> load(BuildContext context,
      {bool shouldPop = true}) async {
    return LoadService.loadGame(context, null,
        isRunning: true, shouldPop: shouldPop);
  }

  /// Starts a game import.
  static Future<void> import(BuildContext context,
      {bool shouldPop = true}) async {
    return ImportService.importGame(context, shouldPop: shouldPop);
  }

  /// Starts a game export.
  static Future<void> export(BuildContext context,
      {bool shouldPop = true}) async {
    return ExportService.exportGame(context, shouldPop: shouldPop);
  }
}
