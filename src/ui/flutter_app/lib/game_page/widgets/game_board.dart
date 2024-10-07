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

part of 'game_page.dart';

class GameImages {
  ui.Image? whitePieceImage;
  ui.Image? blackPieceImage;
  ui.Image? markedPieceImage;
  ui.Image? boardImage;
}

/// Game Board
///
/// The board the game is played on.
/// This widget will also handle the input from the user.
@visibleForTesting
class GameBoard extends StatefulWidget {
  /// Creates a [GameBoard] widget.
  ///
  /// The [boardImagePath] parameter is the path to the selected board image.
  const GameBoard({
    super.key,
    required this.boardImagePath,
  });

  /// The path to the selected board image.
  ///
  /// If null or empty, a default background color will be used.
  final String boardImagePath;

  static const String _logTag = "[board]";

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  static const String _logTag = "[board]";
  late Future<GameImages> gameImagesFuture;
  late AnimationManager animationManager;

  // Bluetooth specific
  BluetoothDeviceType? btDevType;
  StreamSubscription<String>? _bluetoothMoveSubscription;

  @override
  void initState() {
    super.initState();
    gameImagesFuture = _loadImages();
    animationManager = AnimationManager(this);

    GameController().gameResultNotifier.addListener(_showResult);

    if (visitedRuleSettingsPage == true) {
      GameController().reset();
      visitedRuleSettingsPage = false;
    }

    GameController().engine.startup();

    _setupValueNotifierListener();

    Future<void>.delayed(const Duration(microseconds: 100), () {
      _setReadyState();
      processInitialSharingMoveList();
    });

    GameController().animationManager = animationManager;

    // Listen for incoming Bluetooth moves if in Bluetooth game mode
    if (GameController().gameInstance.gameMode ==
        GameMode.humanVsHumanBluetooth) {
      btDevType = DB().generalSettings.aiMovesFirst
          ? BluetoothDeviceType.browser
          : BluetoothDeviceType.advertiser;
      _bluetoothMoveSubscription = BluetoothService.createInstance(btDevType)!
          .moveStream
          .listen((String moveStr) {
        if (moveStr != null) {
          logger
              .i("${GameBoard._logTag} Received move from opponent: $moveStr");
          // Apply the opponent's move using GameController
          GameController().applyOpponentMove(moveStr);
        } else {
          logger.w("${GameBoard._logTag} Received invalid move data: $moveStr");
        }
      });
    }
  }

  Future<void> _setReadyState() async {
    logger.i("$_logTag Check if need to set Ready state...");
    // TODO: v1 has "&& mounted && Config.settingsLoaded"
    if (GameController().isControllerReady == false) {
      logger.i("$_logTag Set Ready State...");
      GameController().isControllerReady = true;
    }
  }

  void _processInitialSharingMoveListListener() {
    processInitialSharingMoveList();
  }

  void _setupValueNotifierListener() {
    GameController()
        .initialSharingMoveListNotifier
        .addListener(_processInitialSharingMoveListListener);
  }

  void _removeValueNotifierListener() {
    GameController()
        .initialSharingMoveListNotifier
        .removeListener(_processInitialSharingMoveListListener);
  }

  Future<GameImages> _loadImages() async {
    return loadGameImages();
  }

  void processInitialSharingMoveList() {
    if (!mounted) {
      return;
    }

    if (GameController().initialSharingMoveListNotifier.value == null) {
      return;
    }

    try {
      ImportService.import(GameController().initialSharingMoveList!);
      if (mounted) {
        LoadService.handleHistoryNavigation(context);
      }
    } catch (e) {
      logger.e("$_logTag Error importing initial sharing move list: $e");
      if (mounted) {
        rootScaffoldMessengerKey.currentState!
            .showSnackBarClear("Error importing initial sharing move list: $e");
      }
    }

    if (mounted && GameController().loadedGameFilenamePrefix != null) {
      final String loadedGameFilenamePrefix =
          GameController().loadedGameFilenamePrefix!;

      // Delay to show the tip after the navigation tip is shown
      Future<void>.delayed(Duration.zero, () {
        GameController().headerTipNotifier.showTip(loadedGameFilenamePrefix);
      });
    }

    if (mounted) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(GameController().initialSharingMoveList!);
    }

    GameController().initialSharingMoveList = null;
  }

  Future<ui.Image> loadImage(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List());
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  // Loading images and creating PiecePainter
  // TODO: Load from settings
  Future<GameImages> loadGameImages() async {
    final DisplaySettings displaySettings = DB().displaySettings;
    final GameImages gameImages = GameImages();

    final String whitePieceImagePath = displaySettings.whitePieceImagePath;
    final String blackPieceImagePath = displaySettings.blackPieceImagePath;

    if (whitePieceImagePath.isEmpty) {
      gameImages.whitePieceImage = null;
    } else {
      gameImages.whitePieceImage = await loadImage(whitePieceImagePath);
    }

    if (blackPieceImagePath.isEmpty) {
      gameImages.blackPieceImage = null;
    } else {
      gameImages.blackPieceImage = await loadImage(blackPieceImagePath);
    }

    gameImages.markedPieceImage =
        await loadImage('assets/images/marked_piece_image.png');

    if (widget.boardImagePath.isEmpty) {
      gameImages.boardImage = null;
    } else {
      gameImages.boardImage = await loadImage(widget.boardImagePath);
    }

    return gameImages;
  }

  @override
  Widget build(BuildContext context) {
    final TapHandler tapHandler = TapHandler(
      context: context,
    );

    final AnimatedBuilder customPaint = AnimatedBuilder(
      animation: Listenable.merge(<Animation<double>>[
        animationManager.placeAnimationController,
        animationManager.moveAnimationController,
        animationManager.removeAnimationController,
      ]),
      builder: (_, Widget? child) {
        return FutureBuilder<GameImages>(
          future: gameImagesFuture,
          builder: (BuildContext context, AsyncSnapshot<GameImages> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else {
              final GameImages? gameImages = snapshot.data;
              return SizedBox.expand(
                child: CustomPaint(
                  painter: BoardPainter(context, gameImages?.boardImage),
                  foregroundPainter: PiecePainter(
                    placeAnimationValue: animationManager.placeAnimation.value,
                    moveAnimationValue: animationManager.moveAnimation.value,
                    removeAnimationValue:
                        animationManager.removeAnimation.value,
                    pieceImages: <PieceColor, ui.Image?>{
                      PieceColor.white: gameImages?.whitePieceImage,
                      PieceColor.black: gameImages?.blackPieceImage,
                      PieceColor.marked: gameImages?.markedPieceImage,
                    },
                  ),
                  child: DB().generalSettings.screenReaderSupport
                      ? const _BoardSemantics()
                      : Semantics(
                          label: S.of(context).youCanEnableScreenReaderSupport,
                          container: true,
                        ),
                ),
              );
            }
          },
        );
      },
    );

    return ValueListenableBuilder<Box<DisplaySettings>>(
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        AppTheme.boardPadding =
            ((deviceWidth(context) - AppTheme.boardMargin * 2) *
                        DB().displaySettings.pieceWidth /
                        7) /
                    2 +
                4;

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constrains) {
            final double dimension = constrains.maxWidth;

            return SizedBox.square(
              dimension: dimension,
              child: GestureDetector(
                child: customPaint,
                onTapUp: (TapUpDetails d) async {
                  final int? square = squareFromPoint(
                      pointFromOffset(d.localPosition, dimension));

                  if (square == null) {
                    return logger.t(
                      "${GameBoard._logTag} Tap not on a square $square (ignored).",
                    );
                  }

                  logger.t("${GameBoard._logTag} Tap on square <$square>");

                  final String strTimeout = S.of(context).timeout;
                  final String strNoBestMoveErr =
                      S.of(context).error(S.of(context).noMove);

                  // Check if the game mode is Bluetooth, handle Bluetooth-specific tap logic
                  if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsHumanBluetooth) {
                    // TODO(BT): Handle the tap in Bluetooth mode, such as sending the move to the other player
                    logger.i(
                        "${GameBoard._logTag} Handling move in Bluetooth mode for square $square");

                    // Example placeholder for Bluetooth move handling
                    // TODO(BT): Implement the logic to send the move over Bluetooth and receive the opponent's move
                    //await _handleBluetoothMove(square);

                    return;
                  }

                  switch (await tapHandler.onBoardTap(square)) {
                    case EngineResponseOK():
                      GameController()
                          .gameResultNotifier
                          .showResult(force: true);
                      break;
                    case EngineResponseHumanOK():
                      GameController()
                          .gameResultNotifier
                          .showResult(force: false);
                      break;
                    case EngineTimeOut():
                      GameController().headerTipNotifier.showTip(strTimeout);
                      break;
                    case EngineNoBestMove():
                      GameController()
                          .headerTipNotifier
                          .showTip(strNoBestMoveErr);
                      break;
                    case EngineGameIsOver():
                      GameController()
                          .gameResultNotifier
                          .showResult(force: true);
                      break;
                    default:
                      break;
                  }

                  GameController().isDisposed = false;
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Handles a move when playing in Bluetooth mode.
  Future<void> _handleBluetoothMove(String moveStr) async {
    // TODO(BT): Implement the logic to send the move over Bluetooth and receive the opponent's move
    logger.i("${GameBoard._logTag} Sending move $moveStr over Bluetooth");
    // Send the move to the opponent via Bluetooth
    await BluetoothService.createInstance(btDevType)!.sendMove(moveStr);

    // Optionally, you can add a delay or waiting mechanism if needed
    logger.i("${GameBoard._logTag} Sent move $moveStr over Bluetooth");
  }

  void _showResult() {
    if (!mounted) {
      return;
    }

    setState(() {});

    final GameMode gameMode = GameController().gameInstance.gameMode;
    final PieceColor winner = GameController().position.winner;
    final String? message = winner.getWinString(context);
    final bool force = GameController().gameResultNotifier.force;

    if (message != null && (force == true || winner != PieceColor.nobody)) {
      if (GameController().position.action == Act.remove) {
        // Fix sometimes tip show "Please place" when action is remove
        // Commit e9884ea
        //GameController()
        //    .headerTipNotifier
        //    .showTip(S.of(context).tipRemove, snackBar: false);
        // Because delayed(Duration.zero), so revert it.
        GameController().headerTipNotifier.showTip(message, snackBar: false);
      } else {
        GameController().headerTipNotifier.showTip(message, snackBar: false);
      }
    }

    GameController().headerIconsNotifier.showIcons();

    if (DB().generalSettings.isAutoRestart == false &&
        winner != PieceColor.nobody &&
        gameMode != GameMode.aiVsAi &&
        gameMode != GameMode.setupPosition) {
      showDialog(
        context: context,
        builder: (_) => GameResultAlertDialog(winner: winner),
      );
    }
  }

  @override
  void dispose() {
    GameController().isDisposed = true;
    GameController().engine.stopSearching();
    //MillController().engine.shutdown();

    animationManager.dispose();
    GameController().gameResultNotifier.removeListener(_showResult);
    _removeValueNotifierListener();

    // Cancel the Bluetooth move subscription if it exists
    _bluetoothMoveSubscription?.cancel();

    super.dispose();
  }
}
