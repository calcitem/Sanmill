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

/// Game Board
///
/// The board the game is played on.
/// This widget will also handle the input from the user.
@visibleForTesting
class GameBoard extends StatefulWidget {
  const GameBoard({super.key});

  static const String _logTag = "[board]";

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard>
    with SingleTickerProviderStateMixin {
  static const String _logTag = "[board]";
  late Future<Map<PieceColor, ui.Image?>> pieceImagesFuture;
  late AnimationManager animationManager;

  @override
  void initState() {
    super.initState();
    pieceImagesFuture = _loadImages();
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
  }

  Future<void> _setReadyState() async {
    logger.i("$_logTag Check if need to set Ready state...");
    // TODO: v1 has "&& mounted && Config.settingsLoaded"
    if (GameController().isControllerReady == false) {
      logger.i("$_logTag Set Ready State...");
      GameController().isControllerReady = true;
    }
  }

  void _setupValueNotifierListener() {
    GameController().initialSharingMoveListNotifier.addListener(() {
      processInitialSharingMoveList();
    });
  }

  Future<Map<PieceColor, ui.Image?>> _loadImages() async {
    return loadPieceImages();
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
      // Delay to show the tip after the navigation tip is shown
      Future<void>.delayed(Duration.zero, () {
        GameController()
            .headerTipNotifier
            .showTip(GameController().loadedGameFilenamePrefix!);
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
  Future<Map<PieceColor, ui.Image?>> loadPieceImages() async {
    final DisplaySettings displaySettings = DB().displaySettings;
    final Map<PieceColor, ui.Image?> images = <PieceColor, ui.Image?>{};

    final String whitePieceImagePath = displaySettings.whitePieceImagePath;
    final String blackPieceImagePath = displaySettings.blackPieceImagePath;

    images[PieceColor.white] = await loadImage(whitePieceImagePath);
    images[PieceColor.black] = await loadImage(blackPieceImagePath);

    images[PieceColor.marked] =
        await loadImage('assets/images/marked_piece_image.png');

    return images;
  }

  @override
  Widget build(BuildContext context) {
    final TapHandler tapHandler = TapHandler(
      context: context,
    );

    final AnimatedBuilder customPaint = AnimatedBuilder(
      animation: animationManager.animation,
      builder: (_, Widget? child) {
        return FutureBuilder<Map<PieceColor, ui.Image?>>(
          future: pieceImagesFuture,
          builder: (BuildContext context,
              AsyncSnapshot<Map<PieceColor, ui.Image?>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else {
              final Map<PieceColor, ui.Image?>? pieceImages = snapshot.data;
              return CustomPaint(
                painter: BoardPainter(context),
                foregroundPainter: PiecePainter(
                  animationValue: animationManager.animation.value,
                  pieceImages: pieceImages,
                ),
                child: DB().generalSettings.screenReaderSupport
                    ? const _BoardSemantics()
                    : Semantics(
                        label: S.of(context).youCanEnableScreenReaderSupport,
                        container: true,
                      ),
              );
            }
          },
        );
      },
    );

    animationManager.forwardAnimation();

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
    GameController()
        .initialSharingMoveListNotifier
        .removeListener(_setupValueNotifierListener);
    super.dispose();
  }
}
