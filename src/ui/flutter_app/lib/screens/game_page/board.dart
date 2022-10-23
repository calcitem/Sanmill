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

part of 'game_page.dart';

/// Game Board
///
/// The board the game is played on.
/// This widget will also handle the input from the user.
@visibleForTesting
class Board extends StatefulWidget {
  static const String _tag = "[board]";

  const Board({super.key});

  @override
  State<Board> createState() => _BoardState();
}

class _BoardState extends State<Board> with SingleTickerProviderStateMixin {
  static const String _tag = "[board]";

  @override
  void initState() {
    super.initState();

    MillController().gameResultNotifier.addListener(_showResult);

    if (visitedRuleSettingsPage == true) {
      MillController().reset();
      visitedRuleSettingsPage = false;
    }

    MillController().isReady == false;

    MillController().engine.startup();

    Future.delayed(const Duration(microseconds: 100), () {
      _setReadyState();
    });

    // TODO: Check _initAnimation() on branch master.

    MillController().animationController = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: DB().displaySettings.animationDuration.toInt(),
      ),
    );

    // sqrt(1.618) = 1.272
    MillController().animation = Tween(begin: 1.27, end: 1.0)
        .animate(MillController().animationController);
  }

  _setReadyState() async {
    logger.i("$_tag Check if need to set Ready state...");
    // TODO: v1 has "&& mounted && Config.settingsLoaded"
    if (MillController().isReady == false) {
      logger.i("$_tag Set Ready State...");
      MillController().isReady = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TapHandler tapHandler = TapHandler(
      context: context,
    );

    final AnimatedBuilder customPaint = AnimatedBuilder(
      animation: MillController().animation,
      builder: (_, Widget? child) {
        return CustomPaint(
          painter: BoardPainter(),
          foregroundPainter: PiecePainter(
            animationValue: MillController().animation.value,
          ),
          child: child,
        );
      },
      child: DB().generalSettings.screenReaderSupport
          ? const _BoardSemantics()
          : null,
    );

    MillController().animationController.forward();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constrains) {
        final double dimension = constrains.maxWidth;

        return SizedBox.square(
          dimension: dimension,
          child: GestureDetector(
            child: customPaint,
            onTapUp: (TapUpDetails d) async {
              final int? square =
                  squareFromPoint(pointFromOffset(d.localPosition, dimension));

              if (square == null) {
                return logger.v(
                  "${Board._tag} Tap not on a square $square (ignored).",
                );
              }

              logger.v("${Board._tag} Tap on square <$square>");

              final String strTimeout = S.of(context).timeout;
              final String strNoBestMoveErr =
                  S.of(context).error(S.of(context).noMove);

              switch (await tapHandler.onBoardTap(square)) {
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
                default:
                  break;
              }

              MillController().disposed = false;
            },
          ),
        );
      },
    );
  }

  void _showResult() {
    if (!mounted) return;
    final GameMode gameMode = MillController().gameInstance.gameMode;
    final PieceColor winner = MillController().position.winner;
    final String? message = winner.getWinString(context);
    final bool force = MillController().gameResultNotifier.force;

    if (message != null && (force == true || winner != PieceColor.nobody)) {
      MillController().headerTipNotifier.showTip(message, snackBar: false);
    }

    MillController().headerIconsNotifier.showIcons();

    if (DB().generalSettings.isAutoRestart == false &&
        winner != PieceColor.nobody &&
        gameMode != GameMode.aiVsAi &&
        gameMode != GameMode.setupPosition) {
      showDialog(
        context: context,
        builder: (_) => GameResultAlert(winner: winner),
      );
    }
  }

  @override
  void dispose() {
    MillController().disposed = true;
    MillController().engine.stopSearching();
    //MillController().engine.shutdown();
    MillController().animationController.dispose();
    MillController().gameResultNotifier.removeListener(_showResult);
    super.dispose();
  }
}

/// Semantics for the Board
///
/// This Widget only contains [Semantics] nodes to help impaired people interact with the [Board].
class _BoardSemantics extends StatefulWidget {
  const _BoardSemantics();

  @override
  State<_BoardSemantics> createState() => _BoardSemanticsState();
}

class _BoardSemanticsState extends State<_BoardSemantics> {
  @override
  void initState() {
    super.initState();
    MillController().boardSemanticsNotifier.addListener(updateBoardSemantics);
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
      children: List.generate(
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
    final List<String> coordinates = [];
    final List<String> pieceDesc = [];
    final List<String> squareDesc = [];

    const List<int> map = [
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

    const List<int> checkPoints = [
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
          MillController().position.pieceOnGrid(i).pieceName(context),
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
    MillController()
        .boardSemanticsNotifier
        .removeListener(updateBoardSemantics);
    super.dispose();
  }
}
