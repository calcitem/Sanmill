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

part of './game_page.dart';

class _MoveOptionsModal extends StatelessWidget {
  const _MoveOptionsModal({Key? key}) : super(key: key);

  void _showMoveList(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _MoveListDialog(),
    );
  }

  Future<void> _moveNow(BuildContext context) async {
    Navigator.pop(context);
    // await extracted.engineToGo(isMoveNow: true);
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
        if (MillController().recorder.moveHistoryText != null) ...[
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
