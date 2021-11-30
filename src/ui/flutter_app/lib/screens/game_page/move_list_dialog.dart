/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

part of 'package:sanmill/screens/game_page/game_page.dart';

class _MoveListDialog extends StatelessWidget {
  const _MoveListDialog({
    required this.takeBackCallback,
    Key? key,
  }) : super(key: key);

  final Function(int) takeBackCallback;

  @override
  Widget build(BuildContext context) {
    final moveHistoryText = controller.position.moveHistoryText!;
    final end = controller.gameInstance.moveHistory.length - 1;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).clearSnackBars();

    return AlertDialog(
      backgroundColor: AppTheme.moveHistoryDialogBackgroundColor,
      title: Text(
        S.of(context).moveList,
        style: AppTheme.moveHistoryTextStyle,
      ),
      content: SingleChildScrollView(
        child: Text(
          moveHistoryText,
          style: AppTheme.moveHistoryTextStyle,
          textDirection: TextDirection.ltr,
        ),
      ),
      actions: <Widget>[
        if (end > 0)
          TextButton(
            child: Text(
              S.of(context).rollback,
              style: AppTheme.moveHistoryTextStyle,
            ),
            onPressed: () async => _rollback(context, end),
          ),
        TextButton(
          child: Text(
            S.of(context).copy,
            style: AppTheme.moveHistoryTextStyle,
          ),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: moveHistoryText));
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).clearSnackBars();
            // ignore: use_build_context_synchronously
            showSnackBar(context, S.of(context).moveHistoryCopied);
          },
        ),
        TextButton(
          child: Text(
            S.of(context).cancel,
            style: AppTheme.moveHistoryTextStyle,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Future<void> _rollback(BuildContext context, int end) async {
    final selectValue = await showDialog<int?>(
      context: context,
      builder: (context) => NumberPicker(end: end),
    );
    assert(selectValue != null);
    takeBackCallback(selectValue!);
  }
}
