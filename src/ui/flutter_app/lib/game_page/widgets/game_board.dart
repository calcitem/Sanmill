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

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  static const String _logTag = "[board]";

  bool _isMovingAnimationComplete = false;
  bool _isPlacingAnimationComplete = false;

  late Future<Map<PieceColor, ui.Image?>> pieceImagesFuture;

  @override
  void initState() {
    super.initState();
    pieceImagesFuture = _loadImages();
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

    // TODO: Check _initAnimation() on branch master.

    if (mounted) {
      GameController().movingAnimationController = AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (DB().displaySettings.animationDuration * 1000).round(),
        ),
      );

      GameController().placingAnimationController = AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (DB().displaySettings.animationDuration * 1000).round(),
        ),
      );

      GameController().removingAnimationController = AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (DB().displaySettings.animationDuration * 1000).round(),
        ),
      );

      GameController()
          .movingAnimationController
          .addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          _onMovingAnimationComplete();
        }
      });

      GameController()
          .placingAnimationController
          .addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          _onPlacingAnimationComplete();
        }
      });

      GameController()
          .removingAnimationController
          .addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          _onRemovingAnimationComplete();
        }
      });
    }

    GameController().movingAnimation = Tween<double>(begin: 0, end: 1)
        .animate(GameController().movingAnimationController);
    GameController().placingAnimation = Tween<double>(begin: 0, end: 1)
        .animate(GameController().placingAnimationController);
    GameController().removingAnimation = Tween<double>(begin: 0, end: 1)
        .animate(GameController().removingAnimationController);
  }

  void _onMovingAnimationComplete() {
    _isMovingAnimationComplete = true;
    if (_isPlacingAnimationComplete) {
      _startRemoveAnimation();
    }
  }

  void _onPlacingAnimationComplete() {
    _isPlacingAnimationComplete = true;
    if (_isMovingAnimationComplete) {
      _startRemoveAnimation();
    }
  }

  void _onRemovingAnimationComplete() {
    return;
  }

  void _startRemoveAnimation() {
    GameController().removingAnimationController.duration = Duration(
      milliseconds: (DB().displaySettings.animationDuration * 1000).round(),
    );

    GameController().removingAnimation = Tween<double>(begin: 0, end: 1)
        .animate(GameController().removingAnimationController);

    GameController().removingAnimationController.reset();

    GameController().removingAnimationController.forward();
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

    late AnimatedBuilder customPaint;

    // This part integrates branchA's logic for different animations based on the current action.
    if (GameController().position.action == Act.remove) {
      customPaint = AnimatedBuilder(
        animation: GameController().movingAnimation,
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
                    animationValue: GameController().movingAnimation.value,
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
    } else if (GameController().position.action == Act.place) {
      customPaint = AnimatedBuilder(
        animation: GameController().placingAnimation,
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
                    animationValue: GameController().placingAnimation.value,
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
    } else if (GameController().position.action == Act.select) {
      customPaint = AnimatedBuilder(
        animation: GameController().movingAnimation,
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
                    animationValue: GameController().movingAnimation.value,
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
    }

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
    GameController().movingAnimationController.dispose();
    GameController().placingAnimationController.dispose();
    GameController().removingAnimationController.dispose();
    GameController().gameResultNotifier.removeListener(_showResult);
    GameController()
        .initialSharingMoveListNotifier
        .removeListener(_setupValueNotifierListener);
    super.dispose();
  }
}

/// Semantics for the Board
///
/// This Widget only contains [Semantics] nodes to help impaired people interact with the [GameBoard].
class _BoardSemantics extends StatefulWidget {
  const _BoardSemantics();

  @override
  State<_BoardSemantics> createState() => _BoardSemanticsState();
}

class _BoardSemanticsState extends State<_BoardSemantics> {
  @override
  void initState() {
    super.initState();
    GameController().boardSemanticsNotifier.addListener(updateBoardSemantics);
  }

  void updateBoardSemantics() {
    setState(() {}); // TODO
  }

  @override
  Widget build(BuildContext context) {
    final List<String> squareDesc = _buildSquareDescription(context);

    return GridView(
      scrollDirection: Axis.horizontal,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      children: List<Widget>.generate(
        7 * 7,
        (int index) => Center(
          child: Semantics(
            // TODO: [Calcitem] Add more descriptive information
            label: squareDesc[index],
          ),
        ),
      ),
    );
  }

  /// Builds a list of Strings representing the label of each semantic node.
  List<String> _buildSquareDescription(BuildContext context) {
    final List<String> coordinates = <String>[];
    final List<String> pieceDesc = <String>[];
    final List<String> squareDesc = <String>[];

    const List<int> map = <int>[
      /* 1 */
      1,
      8,
      15,
      22,
      29,
      36,
      43,
      /* 2 */
      2,
      9,
      16,
      23,
      30,
      37,
      44,
      /* 3 */
      3,
      10,
      17,
      24,
      31,
      38,
      45,
      /* 4 */
      4,
      11,
      18,
      25,
      32,
      39,
      46,
      /* 5 */
      5,
      12,
      19,
      26,
      33,
      40,
      47,
      /* 6 */
      6,
      13,
      20,
      27,
      34,
      41,
      48,
      /* 7 */
      7,
      14,
      21,
      28,
      35,
      42,
      49
    ];

    const List<int> checkPoints = <int>[
      /* 1 */
      1,
      0,
      0,
      1,
      0,
      0,
      1,
      /* 2 */
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      /* 3 */
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      /* 4 */
      1,
      1,
      1,
      0,
      1,
      1,
      1,
      /* 5 */
      0,
      0,
      1,
      1,
      1,
      0,
      0,
      /* 6 */
      0,
      1,
      0,
      1,
      0,
      1,
      0,
      /* 7 */
      1,
      0,
      0,
      1,
      0,
      0,
      1
    ];

    final bool ltr = Directionality.of(context) == TextDirection.ltr;

    for (final String file
        in ltr ? horizontalNotations : horizontalNotations.reversed) {
      for (final String rank in verticalNotations) {
        coordinates.add("${file.toUpperCase()}$rank");
      }
    }

    for (int i = 0; i < 7 * 7; i++) {
      if (checkPoints[i] == 0) {
        pieceDesc.add(S.of(context).noPoint);
      } else {
        pieceDesc.add(
          GameController().position.pieceOnGrid(i).pieceName(context),
        );
      }
    }

    squareDesc.clear();

    for (int i = 0; i < 7 * 7; i++) {
      final String desc = pieceDesc[map[i] - 1];
      if (desc == S.of(context).emptyPoint) {
        squareDesc.add("${coordinates[i]}: $desc");
      } else {
        squareDesc.add("$desc: ${coordinates[i]}");
      }
    }

    return squareDesc;
  }

  @override
  void dispose() {
    GameController()
        .boardSemanticsNotifier
        .removeListener(updateBoardSemantics);
    super.dispose();
  }
}
