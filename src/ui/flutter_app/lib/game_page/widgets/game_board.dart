// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_board.dart

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
  /// The [boardImage] parameter is the ImageProvider for the selected board image.
  const GameBoard({
    super.key,
    required this.boardImage,
  });

  /// The ImageProvider for the selected board image.
  ///
  /// If null, a default background color will be used.
  final ImageProvider? boardImage;

  static const String _logTag = "[board]";

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  static const String _logTag = "[board]";
  late Future<GameImages> gameImagesFuture;
  late AnimationManager animationManager;

  // Flag to prevent duplicate dialog display in AI vs AI mode
  bool _isDialogShowing = false;

  // Define a mapping of animation names to their corresponding constructors.
  final Map<String, PieceEffectAnimation Function()> animationMap =
      <String, PieceEffectAnimation Function()>{
    'Aura': () => AuraPieceEffectAnimation(),
    'Burst': () => BurstPieceEffectAnimation(),
    'Echo': () => EchoPieceEffectAnimation(),
    'Expand': () => ExpandPieceEffectAnimation(),
    'Explode': () => ExplodePieceEffectAnimation(),
    'Fireworks': () => FireworksPieceEffectAnimation(),
    'Glow': () => GlowPieceEffectAnimation(),
    'Orbit': () => OrbitPieceEffectAnimation(),
    'Radial': () => RadialPieceEffectAnimation(),
    'Ripple': () => RipplePieceEffectAnimation(),
    'Rotate': () => RotatePieceEffectAnimation(),
    'Sparkle': () => SparklePieceEffectAnimation(),
    'Spiral': () => SpiralPieceEffectAnimation(),
    'Fade': () => FadePieceEffectAnimation(),
    'Shrink': () => ShrinkPieceEffectAnimation(),
    'Shatter': () => ShatterPieceEffectAnimation(),
    'Disperse': () => DispersePieceEffectAnimation(),
    'Vanish': () => VanishPieceEffectAnimation(),
    'Melt': () => MeltPieceEffectAnimation(),
    'RippleGradient': () => RippleGradientPieceEffectAnimation(),
    'RainbowWave': () => RainbowWavePieceEffectAnimation(),
    'Starburst': () => StarburstPieceEffectAnimation(),
    'Twist': () => TwistPieceEffectAnimation(),
    'PulseRing': () => PulseRingPieceEffectAnimation(),
    'PixelGlitch': () => PixelGlitchPieceEffectAnimation(),
    'FireTrail': () => FireTrailPieceEffectAnimation(),
    'WarpWave': () => WarpWavePieceEffectAnimation(),
    'ShockWave': () => ShockWavePieceEffectAnimation(),
    'ColorSwirl': () => ColorSwirlPieceEffectAnimation(),
    'NeonFlash': () => NeonFlashPieceEffectAnimation(),
    'InkSpread': () => InkSpreadPieceEffectAnimation(),
    'ShadowPulse': () => ShadowPulsePieceEffectAnimation(),
    'RainRipple': () => RainRipplePieceEffectAnimation(),
    'BubblePop': () => BubblePopPieceEffectAnimation(),

    // Add any additional animations here.
  };

  @override
  void initState() {
    super.initState();
    gameImagesFuture = _loadImages();
    animationManager = AnimationManager(this);

    GameController().gameResultNotifier.addListener(_showResult);

    if (visitedRuleSettingsPage == true) {
      GameController().reset();
      visitedRuleSettingsPage = false;
      // Reset dialog flag when game is reset
      _isDialogShowing = false;
    }

    GameController().engine.startup();

    _setupValueNotifierListener();

    Future<void>.delayed(const Duration(microseconds: 100), () {
      _setReadyState();
      processInitialSharingMoveList();
    });

    GameController().animationManager = animationManager;
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

  Future<ui.Image?> loadImageFromFilePath(String filePath) async {
    try {
      if (filePath.startsWith('assets/')) {
        return loadImage(filePath);
      }

      final File file = File(filePath);
      final Uint8List imageData = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(imageData);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      // Log the error for debugging
      logger.e("Error loading image from file path: $e");
      return null;
    }
  }

  // Helper method to convert ImageProvider to ui.Image?
  Future<ui.Image?> _loadImageProvider(ImageProvider? provider) async {
    if (provider == null) {
      return null;
    }

    final Completer<ui.Image> completer = Completer<ui.Image>();
    final ImageStream stream = provider.resolve(ImageConfiguration.empty);
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        completer.complete(info.image);
      },
      onError: (Object exception, StackTrace? stackTrace) {
        completer.completeError(exception, stackTrace);
      },
    );

    stream.addListener(listener);

    try {
      final ui.Image image = await completer.future;
      return image;
    } catch (e) {
      // Handle the error as needed, e.g., log it
      logger.e("Error loading board image: $e");
      return null;
    } finally {
      stream.removeListener(listener);
    }
  }

  // Loading images and creating PiecePainter
  Future<GameImages> loadGameImages() async {
    final DisplaySettings displaySettings = DB().displaySettings;
    final GameImages gameImages = GameImages();

    // Load white piece image from settings, if specified
    final String whitePieceImagePath = displaySettings.whitePieceImagePath;
    if (whitePieceImagePath.isEmpty) {
      gameImages.whitePieceImage = null;
    } else {
      gameImages.whitePieceImage =
          await loadImageFromFilePath(whitePieceImagePath);
    }

    // Load black piece image from settings, if specified
    final String blackPieceImagePath = displaySettings.blackPieceImagePath;
    if (blackPieceImagePath.isEmpty) {
      gameImages.blackPieceImage = null;
    } else {
      gameImages.blackPieceImage =
          await loadImageFromFilePath(blackPieceImagePath);
    }

    // Load marked piece image (static asset)
    gameImages.markedPieceImage =
        await loadImage('assets/images/marked_piece_image.png');

    // Load board image from ImageProvider
    gameImages.boardImage = await _loadImageProvider(widget.boardImage);

    return gameImages;
  }

  @override
  Widget build(BuildContext context) {
    final TapHandler tapHandler = TapHandler(
      context: context,
    );

    // Retrieve the selected animation names from user settings.
    final String placeEffectName = DB().displaySettings.placeEffectAnimation;
    final String removeEffectName = DB().displaySettings.removeEffectAnimation;

    // Use the map to get the corresponding animation instances.
    final PieceEffectAnimation placeEffectAnimation =
        animationMap[placeEffectName]?.call() ?? RadialPieceEffectAnimation();

    final PieceEffectAnimation removeEffectAnimation =
        animationMap[removeEffectName]?.call() ?? ExplodePieceEffectAnimation();

    final AnimatedBuilder customPaint = AnimatedBuilder(
      key: const Key('animated_builder_custom_paint'),
      animation: Listenable.merge(<Animation<double>>[
        animationManager.placeAnimationController,
        animationManager.moveAnimationController,
        animationManager.removeAnimationController,
      ]),
      builder: (_, Widget? child) {
        return FutureBuilder<GameImages>(
          key: const Key('future_builder_game_images'),
          future: gameImagesFuture,
          builder: (BuildContext context, AsyncSnapshot<GameImages> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                key: Key('center_loading'),
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              // Handle errors appropriately
              return const Center(
                key: Key('center_error'),
                child: Text('Error loading images'),
              );
            } else {
              final GameImages? gameImages = snapshot.data;
              return SizedBox.expand(
                key: const Key('sized_box_expand_custom_paint'),
                child: CustomPaint(
                  key: const Key('custom_paint_board_painter'),
                  // Pass the resolved ui.Image? to BoardPainter
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
                    placeEffectAnimation: placeEffectAnimation,
                    removeEffectAnimation: removeEffectAnimation,
                  ),
                  child: DB().generalSettings.screenReaderSupport
                      ? const _BoardSemantics()
                      : Semantics(
                          key: const Key('semantics_screen_reader'),
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
      key: const Key('value_listenable_builder_display_settings'),
      valueListenable: DB().listenDisplaySettings,
      builder: (BuildContext context, Box<DisplaySettings> box, _) {
        AppTheme.boardPadding =
            ((deviceWidth(context) - AppTheme.boardMargin * 2) *
                        DB().displaySettings.pieceWidth /
                        7) /
                    2 +
                4;

        return LayoutBuilder(
          key: const Key('layout_builder_game_board'),
          builder: (BuildContext context, BoxConstraints constrains) {
            final double dimension = constrains.maxWidth;

            return SizedBox.square(
              key: const Key('sized_box_square_game_board'),
              dimension: dimension,
              child: GestureDetector(
                key: const Key('gesture_detector_game_board'),
                child: customPaint,
                onTapUp: (TapUpDetails d) async {
                  final int? square = squareFromPoint(
                      pointFromOffset(d.localPosition, dimension));

                  if (square == null) {
                    return logger.t(
                        "${GameBoard._logTag} Tap not on a square, ignored.");
                  }

                  logger.t("${GameBoard._logTag} Tap on square <$square>");

                  if (GameController().gameInstance.gameMode ==
                      GameMode.humanVsLAN) {
                    if (GameController().isLanOpponentTurn) {
                      rootScaffoldMessengerKey.currentState!
                          .showSnackBarClear(S.of(context).notYourTurn);
                      return;
                    }
                    if (GameController().networkService == null ||
                        !GameController().networkService!.isConnected) {
                      GameController()
                          .headerTipNotifier
                          .showTip(S.of(context).noLanConnection);
                      return;
                    }
                  }

                  final String strTimeout = S.of(context).timeout;
                  final String strNoBestMoveErr =
                      S.of(context).error(S.of(context).noMove);

                  final EngineResponse response =
                      await tapHandler.onBoardTap(square);

                  // Process engine response for displaying tips, etc.
                  switch (response) {
                    case EngineResponseOK():
                      GameController()
                          .gameResultNotifier
                          .showResult(force: true);
                      break;
                    case EngineResponseHumanOK():
                      GameController().gameResultNotifier.showResult();
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

    // Check conditions for showing game result dialog
    final bool shouldShowDialog = GameController().isAutoRestart() == false &&
        winner != PieceColor.nobody &&
        gameMode != GameMode.setupPosition;

    // For AI vs AI mode, additional conditions must be met
    final bool aiVsAiConditions = gameMode != GameMode.aiVsAi ||
        (DB().displaySettings.animationDuration == 0.0 &&
            DB().generalSettings.shufflingEnabled == false);

    // Prevent duplicate dialog display
    if (shouldShowDialog && aiVsAiConditions && !_isDialogShowing) {
      _isDialogShowing = true;
      showDialog(
        context: context,
        builder: (_) => GameResultAlertDialog(
          winner: winner,
        ),
      ).then((_) {
        // Reset flag when dialog is dismissed
        _isDialogShowing = false;
      });
    }
  }

  @override
  void dispose() {
    GameController().isDisposed = true;
    GameController().engine.stopSearching();
    //GameController().engine.shutdown();
    animationManager.dispose();
    GameController().gameResultNotifier.removeListener(_showResult);
    _removeValueNotifierListener();
    super.dispose();
  }
}
