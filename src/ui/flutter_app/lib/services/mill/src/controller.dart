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
/// * The tip [HeaderTipState]
/// * The engine [Engine]
/// * The position [Position]
/// * The game instance [_Game]
/// * The recorder [_GameRecorder]
class MillController {
  static const _tag = "[Controller]";

  late _Game gameInstance;
  late Position position;
  late Engine engine;
  late HeaderTipState tip;
  late _GameRecorder recorder;

  bool _initialized = false;
  bool get initialized => _initialized;

  @visibleForTesting
  static MillController instance = MillController._();

  factory MillController() => instance;

  /// Mill Controller
  ///
  /// A singleton class that holds all objects and methods needed to play Mill.
  ///
  /// Controls:
  /// * The tip [HeaderTipState]
  /// * The engine [Engine]
  /// * The position [Position]
  /// * The game instance [_Game]
  /// * The recorder [_GameRecorder]
  ///
  /// All listed objects should not be crated outside of this scope.
  MillController._() {
    _init();
  }

  /// Starts up the controller. It will initialize the audio subsystem and heat the engine.
  Future<void> start() async {
    if (_initialized) return;

    await engine.startup();
    await Audios().loadSounds();

    _initialized = true;
    logger.i("$_tag initialized");
  }

  /// Resets the controller.
  ///
  /// This method is suitable to use for starting a new game.
  void reset() {
    final gameModeBak = gameInstance.gameMode;
    _init();
    gameInstance.gameMode = gameModeBak;
  }

  /// Starts the current game.
  ///
  /// This method is suitable to use for starting a new game.
  void _startGame() {
    // TODO: [Leptopoda] Reimplement this
    // MillController().tip.showTip(S.of(context).gameStarted, snackBar: true);
    //
    // if (controller.gameInstance.isAiToMove) {
    //   logger.i("$_tag New game, AI to move.");
    //   engineToGo(isMoveNow: false);
    // }
  }

  /// Initializes the controller.
  void _init() {
    position = Position();
    gameInstance = _Game();
    engine = Engine();
    recorder = _GameRecorder();
    tip = HeaderTipState();

    _startGame();
  }

  /// Starts a game import.
  static Future<void> import(BuildContext context) async =>
      ImportService.importGame(context);

  /// Starts a game export.
  static Future<void> export(BuildContext context) async =>
      ImportService.exportGame(context);

  /// Disposes the current controller and shuts down the engine.
  void dispose() {
    engine.shutdown();

    _initialized = false;
    logger.i("$_tag Disposed");
  }
}
