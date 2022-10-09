// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
class MillController {
  static const _tag = "[Controller]";

  bool disposed = false;
  bool isReady = false;
  bool isActive = false;
  bool isEngineGoing = false;
  bool isPositionSetupBanPiece = false;

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

  late GameRecorder recorder;
  GameRecorder? newRecorder;

  late AnimationController animationController;
  late Animation<double> animation;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool get isPositionSetup => recorder.setupPosition != null;
  void clearPositionSetupFlag() => recorder.setupPosition = null;

  @visibleForTesting
  static MillController instance = MillController._();

  factory MillController() => instance;

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
  MillController._() {
    _init();
  }

  /// Starts up the controller. It will initialize the audio subsystem and heat the engine.
  Future<void> start() async {
    if (_initialized) return;

    await Audios().loadSounds();

    _initialized = true;
    logger.i("$_tag initialized");
  }

  /// Resets the controller.
  ///
  /// This method is suitable to use for starting a new game.
  void reset({bool force = false}) {
    final gameModeBak = gameInstance.gameMode;
    String? fen = "";
    final bool isPositionSetup = MillController().isPositionSetup;

    MillController().engine.stopSearching();

    if (isPositionSetup == true && force == false) {
      fen = MillController().recorder.setupPosition;
    }

    _init();

    if (isPositionSetup == true && force == false) {
      MillController().recorder.setupPosition = fen;
      MillController().recorder.lastPositionWithRemove = fen;
      MillController().position.setFen(fen!);
    }

    gameInstance.gameMode = gameModeBak;
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
    gameInstance = Game();
    engine = Engine();
    recorder = GameRecorder(lastPositionWithRemove: position.fen);

    _startGame();
  }

  // TODO: [Leptopoda] The reference of this method has been removed in a few instances.
  // We'll need to find a better way for this.
  Future<EngineResponse> engineToGo(BuildContext context,
      {required bool isMoveNow}) async {
    const tag = "[engineToGo]";

    bool searched = false;
    bool loopIsFirst = true;

    final aiStr = S.of(context).ai;
    final thinkingStr = S.of(context).thinking;
    final humanStr = S.of(context).human;

    final controller = MillController();
    final gameMode = MillController().gameInstance.gameMode;
    bool isGameRunning = position.winner == PieceColor.nobody;

    if (isMoveNow == true) {
      if (MillController().gameInstance.isHumanToMove) {
        return const EngineResponseSkip();
      }

      if (!MillController().recorder.isClean) {
        return const EngineResponseSkip();
      }
    }

    if (MillController().isEngineGoing == true && isMoveNow == false) {
      // TODO: No triggering scene found
      logger.v("$tag engineToGo() is still running, skip.");
      assert(false);
      return const EngineResponseSkip();
    }

    MillController().isEngineGoing = true;

    MillController().isActive = true;

    // TODO
    logger.v("$tag engine type is $gameMode");

    while ((gameInstance.isAiToMove &&
            (isGameRunning || DB().generalSettings.isAutoRestart)) &&
        MillController().isActive) {
      if (gameMode == GameMode.aiVsAi) {
        MillController()
            .headerTipNotifier
            .showTip(MillController().position.scoreString, snackBar: false);
      } else {
        MillController()
            .headerTipNotifier
            .showTip(thinkingStr, snackBar: false);

        showSnakeBarHumanNotation(humanStr);
      }

      MillController().headerIconsNotifier.showIcons();
      MillController().boardSemanticsNotifier.updateSemantics();

      try {
        logger.v("$tag Searching..., isMoveNow: $isMoveNow");

        final extMove = await controller.engine
            .search(moveNow: loopIsFirst ? isMoveNow : false);

        if (MillController().isActive == false) break;

        // TODO: Unify return and throw
        if (controller.gameInstance.doMove(extMove) == false) {
          throw const EngineNoBestMove();
        }

        loopIsFirst = false;
        searched = true;

        if (MillController().disposed == false) {
          MillController().animationController.reset();
          MillController().animationController.animateTo(1.0);
        }

        // TODO: Do not use BuildContexts across async gaps.
        if (DB().generalSettings.screenReaderSupport) {
          rootScaffoldMessengerKey.currentState!.showSnackBar(
            CustomSnackBar("$aiStr: ${extMove.notation}"),
          );
        }
      } on EngineTimeOut {
        logger.i("$tag Engine response type: timeout");
        MillController().isEngineGoing = false;
        return const EngineTimeOut();
      } on EngineNoBestMove {
        logger.i("$tag Engine response type: nobestmove");
        MillController().isEngineGoing = false;
        return const EngineNoBestMove();
      }

      if (MillController().position.winner != PieceColor.nobody) {
        if (DB().generalSettings.isAutoRestart == true) {
          MillController().reset();
        } else {
          MillController().isEngineGoing = false;
          if (MillController().gameInstance.gameMode == GameMode.aiVsAi) {
            MillController().headerTipNotifier.showTip(
                MillController().position.scoreString,
                snackBar: false);
            MillController().headerIconsNotifier.showIcons();
            MillController().boardSemanticsNotifier.updateSemantics();
          }
          return const EngineResponseOK();
        }
      }
    }

    MillController().isEngineGoing = false;

    // TODO: Why need not update tip and icons?
    MillController().boardSemanticsNotifier.updateSemantics();

    return searched ? const EngineResponseOK() : const EngineResponseHumanOK();
  }

  Future<void> moveNow(BuildContext context) async {
    const tag = "[engineToGo]";
    bool reversed = false;

    // TODO: WAR
    if ((MillController().gameInstance.sideToMove == PieceColor.white ||
            MillController().gameInstance.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
    }

    if ((MillController().position.sideToMove == PieceColor.white ||
            MillController().position.sideToMove == PieceColor.black) ==
        false) {
      // If modify sideToMove, not take effect, I don't know why.
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
    }

    if (MillController().gameInstance.isHumanToMove) {
      logger.i("$tag Human to Move. Temporarily swap AI and Human roles.");
      //return rootScaffoldMessengerKey.currentState!
      //    .showSnackBarClear(S.of(context).notAIsTurn);
      MillController().gameInstance.reverseWhoIsAi();
      reversed = true;
    }

    if (!MillController().recorder.isClean) {
      logger.i("$tag History is not clean. Prune, and think now.");
      MillController().recorder.prune();
    }

    final strTimeout = S.of(context).timeout;
    final strNoBestMoveErr = S.of(context).error(S.of(context).noMove);

    switch (await MillController()
        .engineToGo(context, isMoveNow: MillController().isEngineGoing)) {
      case EngineResponseOK():
        MillController().gameResultNotifier.showResult(force: true);
        break;
      case EngineResponseHumanOK():
        MillController().gameResultNotifier.showResult(force: false);
        break;
      case EngineTimeOut():
        MillController().headerTipNotifier.showTip(strTimeout);
        break;
      case EngineNoBestMove():
        MillController().headerTipNotifier.showTip(strNoBestMoveErr);
        break;
      case EngineResponseSkip():
        MillController().headerTipNotifier.showTip("Error: Skip"); // TODO
        break;
      default:
        assert(false);
        break;
    }

    if (reversed) MillController().gameInstance.reverseWhoIsAi();
  }

  showSnakeBarHumanNotation(String humanStr) {
    final String? n = recorder.lastF?.notation;

    if (DB().generalSettings.screenReaderSupport &&
        MillController().position._action != Act.remove &&
        n != null) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBar(CustomSnackBar("$humanStr: $n"));
    }
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

  /// Starts a smart lens.
  static Future<void> scan(BuildContext context) async =>
      ImportService.scanGame(context);
}
