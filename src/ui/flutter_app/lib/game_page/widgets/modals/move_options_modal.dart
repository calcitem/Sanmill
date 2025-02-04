// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// move_options_modal.dart

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
            key: const Key('take_back_option'),
            onPressed: () => HistoryNavigator.takeBack(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).takeBack),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            key: const Key('step_forward_option'),
            onPressed: () => HistoryNavigator.stepForward(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).stepForward),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            key: const Key('take_back_all_option'),
            onPressed: () => HistoryNavigator.takeBackAll(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).takeBackAll),
            ),
          ),
          const CustomSpacer(),
          SimpleDialogOption(
            key: const Key('step_forward_all_option'),
            onPressed: () => HistoryNavigator.stepForwardAll(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).stepForwardAll),
            ),
          ),
          const CustomSpacer(),
        ],
        if (GameController().gameRecorder.activeNode?.parent != null ||
            GameController().isPositionSetup == true) ...<Widget>[
          SimpleDialogOption(
            key: const Key('show_move_list_option'),
            onPressed: () {
              if (DB().generalSettings.screenReaderSupport) {
                _showMoveList(context);
              } else {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const MovesListPage(),
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(S.of(context).showMoveList),
            ),
          ),
          const CustomSpacer(),
        ],
        SimpleDialogOption(
          key: const Key('move_now_option'),
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
            key: const Key('move_options_modal_close_option'),
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
