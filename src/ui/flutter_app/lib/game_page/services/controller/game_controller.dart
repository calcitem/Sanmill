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
    _init();
  }

  static const String _logTag = "[Controller]";

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

  /// Resets the controller.
  ///
  /// This method is suitable to use for starting a new game.
  void reset({bool force = false}) {
    final GameMode gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPosSetup = GameController().isPositionSetup;

    value = "0";
    aiMoveType = AiMoveType.unknown;

    GameController().engine.stopSearching();

    if (isPosSetup && force == false) {
      fen = GameController().gameRecorder.setupPosition;
    }

    _init();

    if (isPosSetup && force == false && fen != null) {
      GameController().gameRecorder.setupPosition = fen;
      GameController().gameRecorder.lastPositionWithRemove = fen;
      GameController().position.setFen(fen);
    }

    gameInstance.gameMode = gameModeBak;

    GifShare().captureView(first: true);
  }

  /// Starts the current game.
  ///
  /// This method is suitable to use for starting a new game.
  void _startGame() {
    // TODO: [Leptopoda] Reimplement this and clean onBoardTap()
  }

  /// Initializes the controller.
  void _init() {
    position = Position();
    gameInstance = Game(gameMode: GameMode.humanVsAi);
    engine = Engine();
    gameRecorder = GameRecorder(
      lastPositionWithRemove: position.fen,
    );

    _startGame();
  }

  bool isAutoRestart() {
    if (EnvironmentConfig.devMode == true) {
      return DB().generalSettings.isAutoRestart &&
          GameController().position.isNoDraw() == false;
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

    late EngineRet engineRet;

    bool searched = false;
    bool loopIsFirst = true;

    final String aiStr = S.of(context).ai;
    final String thinkingStr = S.of(context).thinking;
    final String humanStr = S.of(context).human;

    final GameController controller = GameController();
    final GameMode gameMode = GameController().gameInstance.gameMode;
    final bool isGameRunning = position.winner == PieceColor.nobody;

    // If isMoveNow but it's actually humanToMove, skip
    if (isMoveNow && GameController().gameInstance.isHumanToMove) {
      return const EngineResponseSkip();
    }

    // Instead of .isAtEnd(), you might do something like:
    // if (isMoveNow && !gameRecorder.isAtEnd()) { ... } or remove it entirely
    // Here, we just remove it for minimal code:
    // if (isMoveNow && !gameRecorder.isAtEnd()) {
    //   return const EngineResponseSkip();
    // }

    if (!isMoveNow && GameController().position._checkIfGameIsOver()) {
      return const EngineGameIsOver();
    }

    if (GameController().isEngineRunning && !isMoveNow) {
      // TODO: Monkey test trigger
      logger.t("$tag engineToGo() is still running, skip.");
      return const EngineResponseSkip();
    }

    GameController().isEngineRunning = true;
    GameController().isControllerActive = true;

    // TODO
    logger.t("$tag engine type is $gameMode");

    if (gameMode == GameMode.humanVsAi &&
        GameController().position.phase == Phase.moving &&
        !isMoveNow &&
        DB().ruleSettings.mayFly &&
        DB().generalSettings.remindedOpponentMayFly == false &&
        (GameController()
                    .position
                    .pieceOnBoardCount[GameController().position.sideToMove]! <=
                DB().ruleSettings.flyPieceCount &&
            GameController()
                    .position
                    .pieceOnBoardCount[GameController().position.sideToMove]! >=
                3)) {
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
            GameController().isControllerActive) {
      if (gameMode == GameMode.aiVsAi) {
        GameController()
            .headerTipNotifier
            .showTip(GameController().position.scoreString, snackBar: false);
      } else {
        GameController()
            .headerTipNotifier
            .showTip(thinkingStr, snackBar: false);
        showSnakeBarHumanNotation(humanStr);
      }

      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();

      try {
        logger.t("$tag Searching..., isMoveNow: $isMoveNow");

        if (GameController().position.pieceOnBoardCount[PieceColor.black]! >
            0) {
          isEngineInDelay = true;
          await Future<void>.delayed(Duration(
            milliseconds:
                (DB().displaySettings.animationDuration * 1000).toInt(),
          ));
          isEngineInDelay = false;
        }

        engineRet =
            await controller.engine.search(moveNow: loopIsFirst && isMoveNow);

        if (!GameController().isControllerActive) {
          break;
        }

        // TODO: Unify return and throw
        if (!controller.gameInstance.doMove(engineRet.extMove!)) {
          // TODO: Should catch it and throw.
          GameController().isEngineRunning = false;
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
        GameController().isEngineRunning = false;
        return const EngineTimeOut();
      } on EngineNoBestMove {
        logger.i("$tag Engine response type: nobestmove");
        GameController().isEngineRunning = false;
        return const EngineNoBestMove();
      }

      GameController().value = engineRet.value;
      GameController().aiMoveType = engineRet.aiMoveType;

      if (GameController().value != null &&
          GameController().aiMoveType != AiMoveType.unknown) {
        GameController().lastMoveFromAI = true;
      }

      if (GameController().position.winner != PieceColor.nobody) {
        if (isAutoRestart()) {
          GameController().reset();
        } else {
          GameController().isEngineRunning = false;
          if (gameMode == GameMode.aiVsAi) {
            GameController().headerTipNotifier.showTip(
                  GameController().position.scoreString,
                  snackBar: false,
                );
            GameController().headerIconsNotifier.showIcons();
            GameController().boardSemanticsNotifier.updateSemantics();
          }
          return const EngineResponseOK();
        }
      }
    }

    GameController().isEngineRunning = false;

    // TODO: Why need not update tip and icons?
    GameController().boardSemanticsNotifier.updateSemantics();

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
    if (GameController().position.sideToMove != PieceColor.white &&
        GameController().position.sideToMove != PieceColor.black) {
      // If modify sideToMove, not take effect, I don't know why.
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
    }

    if (GameController().gameInstance.isHumanToMove) {
      logger.i("$tag Human to Move. Temporarily swap AI and Human roles.");
      //return rootScaffoldMessengerKey.currentState!
      //    .showSnackBarClear(S.of(context).notAIsTurn);
      GameController().gameInstance.reverseWhoIsAi();
      reversed = true;
    }

    final String strTimeout = S.of(context).timeout;
    final String strNoBestMoveErr = S.of(context).error(S.of(context).noMove);

    switch (await GameController()
        .engineToGo(context, isMoveNow: GameController().isEngineRunning)) {
      case EngineResponseOK():
      case EngineGameIsOver():
        GameController().gameResultNotifier.showResult(force: true);
        break;
      case EngineResponseHumanOK():
        GameController().gameResultNotifier.showResult(force: false);
        break;
      case EngineTimeOut():
        GameController().headerTipNotifier.showTip(strTimeout);
        break;
      case EngineNoBestMove():
        GameController().headerTipNotifier.showTip(strNoBestMoveErr);
        break;
      case EngineResponseSkip():
        GameController().headerTipNotifier.showTip("Error: Skip"); // TODO
        break;
      default:
        logger.e("$tag Unknown engine response type.");
        break;
    }

    if (reversed) {
      GameController().gameInstance.reverseWhoIsAi();
    }
  }

  void showSnakeBarHumanNotation(String humanStr) {
    final List<ExtMove> moves = gameRecorder.mainlineMoves;
    final ExtMove? lastMove = moves.isNotEmpty ? moves.last : null;
    final String? n = lastMove?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        GameController().position.action != Act.remove &&
        n != null) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("$humanStr: $n"));
    }
  }

  Future<void> gifShare(BuildContext context) async {
    GameController().headerTipNotifier.showTip(S.of(context).pleaseWait);
    final String done = S.of(context).done;
    await GifShare().captureView();
    GameController().headerTipNotifier.showTip(done);

    GifShare().shareGif();
  }

  /// Starts a game save.
  static Future<String?> save(BuildContext context) async {
    return LoadService.saveGame(context);
  }

  /// Starts a game load.
  static Future<void> load(BuildContext context) async {
    return LoadService.loadGame(context, null, isRunning: true);
  }

  /// Starts a game import.
  static Future<void> import(BuildContext context) async {
    return ImportService.importGame(context);
  }

  /// Starts a game export.
  static Future<void> export(BuildContext context) async {
    return ExportService.exportGame(context);
  }
}
