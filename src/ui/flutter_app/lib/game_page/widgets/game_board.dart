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

  @override
  void initState() {
    super.initState();

    GameController().gameResultNotifier.addListener(_showResult);

    if (visitedRuleSettingsPage == true) {
      GameController().reset();
      visitedRuleSettingsPage = false;
    }

    // ignore: unnecessary_statements
    GameController().isControllerReady == false;

    GameController().engine.startup();

    // ignore: always_specify_types
    Future.delayed(const Duration(microseconds: 100), () {
      _setReadyState();
    });

    // TODO: Check _initAnimation() on branch master.

    GameController().animationController = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: DB().displaySettings.animationDuration.toInt(),
      ),
    );

    // sqrt(1.618) = 1.272
    GameController().animation = Tween<double>(begin: 1.27, end: 1.0)
        .animate(GameController().animationController);
  }

  Future<void> _setReadyState() async {
    logger.i("$_logTag Check if need to set Ready state...");
    // TODO: v1 has "&& mounted && Config.settingsLoaded"
    if (GameController().isControllerReady == false) {
      logger.i("$_logTag Set Ready State...");
      GameController().isControllerReady = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TapHandler tapHandler = TapHandler(
      context: context,
    );

    final AnimatedBuilder customPaint = AnimatedBuilder(
      animation: GameController().animation,
      builder: (_, Widget? child) {
        return CustomPaint(
          painter: BoardPainter(context),
          foregroundPainter: PiecePainter(
            animationValue: GameController().animation.value,
          ),
          child: child,
        );
      },
      child: DB().generalSettings.screenReaderSupport
          ? const _BoardSemantics()
          : null,
    );

    GameController().animationController.forward();

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
                    return logger.v(
                      "${GameBoard._logTag} Tap not on a square $square (ignored).",
                    );
                  }

                  logger.v("${GameBoard._logTag} Tap on square <$square>");

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
        GameController()
            .headerTipNotifier
            .showTip(S.of(context).tipRemove, snackBar: false);
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
    GameController().animationController.dispose();
    GameController().gameResultNotifier.removeListener(_showResult);
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
        in ltr ? verticalNotations : verticalNotations.reversed) {
      for (final String rank in horizontalNotations) {
        coordinates.add("$file$rank");
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
