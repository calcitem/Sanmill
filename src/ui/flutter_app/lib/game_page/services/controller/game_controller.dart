// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

  /// Mill Controller
  ///
  /// A singleton class that holds all objects and methods needed to play Mill.
  ///
  /// Controls:
  /// * The tip [HeaderTipNotifier]
  /// * The engine [Engine]
  /// * The position [Position]
  /// * The game instance [Game]
  /// * The recorder [GameRecorder]
  ///
  /// All listed objects should not be crated outside of this scope.
  GameController._() {
    _init();
  }

  static const String _logTag = "[Controller]";

  bool isDisposed = false;
  bool isControllerReady = false;
  bool isControllerActive = false;
  bool isEngineRunning = false;
  bool isEngineInDelay = false;
  bool isPositionSetupBanPiece = false; // TODO: isPieceBannedInPositionSetup?

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

  late AnimationController animationController;
  late Animation<double> animation;

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
    final bool isPositionSetup = GameController().isPositionSetup;

    value = "0";
    aiMoveType = AiMoveType.unknown;

    GameController().engine.stopSearching();

    if (isPositionSetup == true && force == false) {
      fen = GameController().gameRecorder.setupPosition;
    }

    _init();

    if (isPositionSetup == true && force == false) {
      GameController().gameRecorder.setupPosition = fen;
      GameController().gameRecorder.lastPositionWithRemove = fen;
      GameController().position.setFen(fen!);
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
    gameRecorder = GameRecorder(lastPositionWithRemove: position.fen);

    _startGame();
  }

  // TODO: [Leptopoda] The reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<EngineResponse> engineToGo(BuildContext context,
      {required bool isMoveNow}) async {
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

    if (isMoveNow == true) {
      if (GameController().gameInstance.isHumanToMove) {
        return const EngineResponseSkip();
      }

      if (!GameController().gameRecorder.isClean) {
        return const EngineResponseSkip();
      }
    } else {
      if (GameController().position._checkIfGameIsOver() == true) {
        return const EngineNoBestMove();
      }

      if (GameController()
              .position
              .pieceToRemoveCount[GameController().position.sideToMove]! >
          0) {
        GameController().position.action = Act.remove;
      }
    }

    if (GameController().isEngineRunning == true && isMoveNow == false) {
      // TODO: Monkey test trigger
      logger.v("$tag engineToGo() is still running, skip.");
      //assert(false);
      return const EngineResponseSkip();
    }

    GameController().isEngineRunning = true;

    GameController().isControllerActive = true;

    // TODO
    logger.v("$tag engine type is $gameMode");

    if (gameMode == GameMode.humanVsAi &&
        GameController().position.phase == Phase.moving &&
        isMoveNow == false &&
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
      rootScaffoldMessengerKey.currentState!.showSnackBar(CustomSnackBar(
          S.of(context).enteredFlyingPhase,
          duration: const Duration(seconds: 8)));

      DB().generalSettings = DB().generalSettings.copyWith(
            remindedOpponentMayFly: true,
          );
    }

    while ((gameInstance.isAiToMove &&
            (isGameRunning || DB().generalSettings.isAutoRestart)) &&
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
        logger.v("$tag Searching..., isMoveNow: $isMoveNow");

        if (GameController().position.pieceOnBoardCount[PieceColor.black]! >
            0) {
          isEngineInDelay = true;
          await Future<void>.delayed(Duration(
              seconds: DB().displaySettings.aiResponseDelayTime.toInt()));
          isEngineInDelay = false;
        }

        engineRet = await controller.engine
            // ignore: avoid_bool_literals_in_conditional_expressions
            .search(moveNow: loopIsFirst ? isMoveNow : false);

        if (GameController().isControllerActive == false) {
          break;
        }

        // TODO: Unify return and throw
        if (controller.gameInstance.doMove(engineRet.extMove!) == false) {
          // TODO: Should catch it and throw.
          GameController().isEngineRunning = false;
          return const EngineNoBestMove();
        }

        loopIsFirst = false;
        searched = true;

        if (GameController().isDisposed == false) {
          GameController().animationController.reset();
          GameController().animationController.animateTo(1.0);
        }

        // TODO: Do not use BuildContexts across async gaps.
        if (DB().generalSettings.screenReaderSupport) {
          rootScaffoldMessengerKey.currentState!.showSnackBar(
            CustomSnackBar("$aiStr: ${engineRet.extMove!.notation}"),
          );
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

      if (GameController().position.winner != PieceColor.nobody) {
        if (DB().generalSettings.isAutoRestart == true) {
          GameController().reset();
        } else {
          GameController().isEngineRunning = false;
          if (GameController().gameInstance.gameMode == GameMode.aiVsAi) {
            GameController().headerTipNotifier.showTip(
                GameController().position.scoreString,
                snackBar: false);
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

    if (isEngineInDelay == true) {
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).aiIsDelaying);
    }

    // TODO: WAR
    if ((GameController().gameInstance.sideToMove == PieceColor.white ||
            GameController().gameInstance.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
    }

    if ((GameController().position.sideToMove == PieceColor.white ||
            GameController().position.sideToMove == PieceColor.black) ==
        false) {
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

    if (!GameController().gameRecorder.isClean) {
      logger.i("$tag History is not clean. Prune, and think now.");
      GameController().gameRecorder.prune();
    }

    final String strTimeout = S.of(context).timeout;
    final String strNoBestMoveErr = S.of(context).error(S.of(context).noMove);

    switch (await GameController()
        .engineToGo(context, isMoveNow: GameController().isEngineRunning)) {
      case EngineResponseOK():
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
        assert(false);
        break;
    }

    if (reversed) {
      GameController().gameInstance.reverseWhoIsAi();
    }
  }

  void showSnakeBarHumanNotation(String humanStr) {
    final String? n = gameRecorder.lastF?.notation;

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
  static Future<void> save(BuildContext context) async =>
      LoadService.saveGame(context);

  /// Starts a game load.
  static Future<void> load(BuildContext context) async =>
      LoadService.loadGame(context);

  /// Starts a game import.
  static Future<void> import(BuildContext context) async =>
      ImportService.importGame(context);

  /// Starts a game export.
  static Future<void> export(BuildContext context) async =>
      ImportService.exportGame(context);
}
