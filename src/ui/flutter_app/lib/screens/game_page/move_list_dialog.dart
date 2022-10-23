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

class _MoveListDialog extends StatelessWidget {
  const _MoveListDialog();

  @override
  Widget build(BuildContext context) {
    final MillController controller = MillController();

    final String moveHistoryText = controller.recorder.moveHistoryText!;
    final int end = controller.recorder.length - 1;

    final TextStyle titleTextStyle = Theme.of(context)
        .textTheme
        .headline6!
        .copyWith(color: AppTheme.gamePageActionSheetTextColor);
    final TextStyle buttonTextStyle = titleTextStyle;

    if (DB().generalSettings.screenReaderSupport) {
      rootScaffoldMessengerKey.currentState!.clearSnackBars();
    }

    return GamePageActionSheet(
      child: AlertDialog(
        title: Text(
          S.of(context).moveList,
          style: titleTextStyle,
          textScaleFactor: DB().displaySettings.fontScale,
        ),
        content: SingleChildScrollView(
          child: Text(
            moveHistoryText,
            textDirection: TextDirection.ltr,
            textScaleFactor: DB().displaySettings.fontScale,
            style: Theme.of(context).textTheme.headline6!.copyWith(
                color: AppTheme.gamePageActionSheetTextColor,
                fontWeight: FontWeight.normal,
                fontFeatures: [const FontFeature.tabularFigures()]),
          ),
        ),
        actions: <Widget>[
          if (end > 0)
            TextButton(
              child: Text(
                S.of(context).rollback,
                style: buttonTextStyle,
                textScaleFactor: DB().displaySettings.fontScale,
              ),
              onPressed: () async => _rollback(context, end),
            ),
          TextButton(
            child: Text(
              S.of(context).copy,
              style: buttonTextStyle,
              textScaleFactor: DB().displaySettings.fontScale,
            ),
            onPressed: () => MillController.export(context),
          ),
          TextButton(
            child: Text(
              S.of(context).cancel,
              style: buttonTextStyle,
              textScaleFactor: DB().displaySettings.fontScale,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _rollback(BuildContext context, int end) async {
    final int? selectValue = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) => NumberPicker(
          end: end, newTitle: S.of(context).pleaseSelect, showMoveString: true),
    );

    if (selectValue == null) return;

    // ignore: use_build_context_synchronously
    await HistoryNavigator.takeBackN(context, selectValue);
  }
}
