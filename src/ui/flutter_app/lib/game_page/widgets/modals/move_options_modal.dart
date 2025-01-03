// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

part of '../game_page.dart';

class MoveOptionsModal extends StatelessWidget {
  const MoveOptionsModal({super.key, required this.mainContext});

  final BuildContext mainContext;

  void _showMoveList(BuildContext context) {
    Navigator.pop(context);
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!mainContext.mounted) {
        return;
      }
      showDialog<void>(
        context: mainContext,
        builder: (BuildContext context) => const MoveListDialog(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamePageDialog(
      semanticLabel: S.of(context).moveNumber(0),
      children: <Widget>[
        if (!DB().displaySettings.isHistoryNavigationToolbarShown) ...<Widget>[
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.takeBack(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).takeBack),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.stepForward(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).stepForward),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.takeBackAll(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).takeBackAll),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            onPressed: () => HistoryNavigator.stepForwardAll(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).stepForwardAll),
            ),
          ),
          const CustomSpacer(),
        ],
        if (GameController().gameRecorder.hasPrevious ||
            GameController().isPositionSetup == true) ...<Widget>[
          SimpleDialogOption(
            onPressed: () => _showMoveList(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).showMoveList),
            ),
          ),
          const CustomSpacer(),
        ],
        SimpleDialogOption(
          onPressed: () {
            GameController().moveNow(context);
            Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(S.of(context).moveNow),
          ),
        ),
        const CustomSpacer(),
        if (DB().generalSettings.screenReaderSupport)
          SimpleDialogOption(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).close),
            ),
            onPressed: () => Navigator.pop(context),
          ),
      ],
    );
  }
}
