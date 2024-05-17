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

part of '../game_page.dart';

class _MoveListDialog extends StatelessWidget {
  const _MoveListDialog();

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    final List<String> mergedMoves = _getMergedMoves(controller);
    final int movesCount = (mergedMoves.length + 1) ~/ 2;

    if (DB().generalSettings.screenReaderSupport) {
      rootScaffoldMessengerKey.currentState!.clearSnackBars();
    }

    return GamePageActionSheet(
      child: AlertDialog(
        backgroundColor: UIColors.semiTransparentBlack,
        title: Text(
          S.of(context).moveList,
          style: _getTitleTextStyle(context),
        ),
        content: SizedBox(
          width: calculateNCharWidth(context, 32),
          height: calculateNCharWidth(context, mergedMoves.length * 2 + 1),
          child: ListView(
            shrinkWrap: false,
            physics: const AlwaysScrollableScrollPhysics(),
            children: List<Widget>.generate(
              movesCount,
              (int index) => _buildMoveListItem(context, mergedMoves, index),
            ),
          ),
        ),
        actions: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: TextButton(
                  child: Text(
                    S.of(context).copy,
                    style: _getButtonTextStyle(context),
                  ),
                  onPressed: () => GameController.export(context),
                ),
              ),
              Expanded(
                child: TextButton(
                  child: Text(
                    S.of(context).cancel,
                    style: _getButtonTextStyle(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _getMergedMoves(GameController controller) {
    final List<String> moves = controller.gameRecorder.moveHistoryText
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty && !s.contains('.'))
        .toList();

    final List<String> mergedMoves = <String>[];
    for (final String move in moves) {
      if (move.startsWith('x') && mergedMoves.isNotEmpty) {
        mergedMoves[mergedMoves.length - 1] += move;
      } else {
        mergedMoves.add(move);
      }
    }

    return mergedMoves;
  }

  Widget _buildMoveListItem(
      BuildContext context, List<String> mergedMoves, int index) {
    final int moveIndex = index * 2;
    final List<InlineSpan> spans = <InlineSpan>[];

    spans.add(
      WidgetSpan(
        child: Text(
          '${(index + 1).toString().padLeft(3)}.  ',
          style: _getTitleTextStyle(context),
        ),
      ),
    );

    for (int i = 0; i < 2; i++) {
      if (moveIndex + i >= mergedMoves.length) {
        break;
      }

      final String moveText = mergedMoves[moveIndex + i];
      spans.add(
        WidgetSpan(
          child: InkWell(
            onTap: () => _importGame(context, mergedMoves, moveIndex + i),
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Text(
                moveText,
                style: _getTitleTextStyle(context),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        title: Text.rich(
          TextSpan(
            children: spans,
            style: const TextStyle(height: 1.2),
          ),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _importGame(
      BuildContext context, List<String> mergedMoves, int clickedIndex) async {
    final String ml = mergedMoves.sublist(0, clickedIndex + 1).join(' ');
    final SnackBar snackBar = SnackBar(
      content: Text(ml),
      duration: const Duration(seconds: 2),
    );
    if (!ScaffoldMessenger.of(context).mounted) {
      return;
    }
    if (EnvironmentConfig.devMode) {
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
    try {
      ImportService.import(ml);
    } catch (exception) {
      if (!context.mounted) {
        return;
      }
      final String tip = S.of(context).cannotImport(ml);
      GameController().headerTipNotifier.showTip(tip);
      Navigator.pop(context);
      return;
    }
    if (!context.mounted) {
      return;
    }
    await HistoryNavigator.takeBackAll(context, pop: false);
    if (!context.mounted) {
      return;
    }
    if (await HistoryNavigator.stepForwardAll(context, pop: false) ==
        const HistoryOK()) {
      if (!context.mounted) {
        return;
      }
      GameController().headerTipNotifier.showTip(S.of(context).gameImported);
    } else {
      if (!context.mounted) {
        return;
      }
      final String tip =
          S.of(context).cannotImport(HistoryNavigator.importFailedStr);
      GameController().headerTipNotifier.showTip(tip);
      HistoryNavigator.importFailedStr = "";
    }
  }

  TextStyle _getTitleTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          color: AppTheme.gamePageActionSheetTextColor,
          fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
          fontFamily: getMonospaceTitleTextStyle(context).fontFamily,
        );
  }

  TextStyle _getButtonTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          color: AppTheme.gamePageActionSheetTextColor,
          fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
        );
  }
}
