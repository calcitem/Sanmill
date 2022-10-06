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

class _MoveOptionsModal extends StatelessWidget {
  final BuildContext mainContext;

  const _MoveOptionsModal({Key? key, required this.mainContext})
      : super(key: key);

  void _showMoveList(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _MoveListDialog(),
    );
  }

  Future<void> _moveNow(BuildContext context) async {
    const tag = "[engineToGo]";

    Navigator.pop(context);

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
      logger.i("$tag Human to Move. Cannot get search result now.");
      return rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(S.of(context).notAIsTurn);
    }

    if (!MillController().recorder.isClean) {
      logger.i("$tag History is not clean. Prune, and think now.");
      MillController().recorder.prune();
    }

    final strTimeout = S.of(context).timeout;
    final strNoBestMoveErr = S.of(context).error("No best move");

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
  }

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).moveNumber(0),
      children: <Widget>[
        if (!DB().displaySettings.isHistoryNavigationToolbarShown) ...[
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.takeBack(context),
            child: Text(S.of(context).takeBack),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.stepForward(context),
            child: Text(S.of(context).stepForward),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.takeBackAll(context),
            child: Text(S.of(context).takeBackAll),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.stepForwardAll(context),
            child: Text(S.of(context).stepForwardAll),
          ),
          const CustomSpacer(),
        ],
        if (MillController().recorder.hasPrevious) ...[
          SimpleDialogOption(
            onPressed: () => _showMoveList(context),
            child: Text(S.of(context).showMoveList),
          ),
          const CustomSpacer(),
        ],
        SimpleDialogOption(
          onPressed: () => _moveNow(context),
          child: Text(S.of(context).moveNow),
        ),
        const CustomSpacer(),
        if (DB().generalSettings.screenReaderSupport)
          SimpleDialogOption(
            child: Text(S.of(context).close),
            onPressed: () => Navigator.pop(context),
          ),
      ],
    );
  }
}
