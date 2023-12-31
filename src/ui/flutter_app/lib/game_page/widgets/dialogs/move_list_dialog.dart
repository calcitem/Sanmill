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

    final String moveHistoryText = controller.gameRecorder.moveHistoryText;
    final int end = controller.gameRecorder.length - 1;

    final TextStyle titleTextStyle =
        Theme.of(context).textTheme.titleLarge!.copyWith(
              color: AppTheme.gamePageActionSheetTextColor,
              fontSize: AppTheme.textScaler.scale(AppTheme.largeFontSize),
            );
    final TextStyle buttonTextStyle =
        Theme.of(context).textTheme.titleMedium!.copyWith(
              color: AppTheme.gamePageActionSheetTextColor,
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize),
            );

    if (DB().generalSettings.screenReaderSupport) {
      rootScaffoldMessengerKey.currentState!.clearSnackBars();
    }

    return GamePageActionSheet(
      child: AlertDialog(
        backgroundColor: UIColors.semiTransparentBlack,
        title: Text(
          S.of(context).moveList,
          style: titleTextStyle.copyWith(
              fontSize: AppTheme.textScaler
                  .scale(titleTextStyle.fontSize ?? AppTheme.largeFontSize)),
        ),
        content: SingleChildScrollView(
          child: Text(
            moveHistoryText,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontSize: AppTheme.textScaler
                    .scale(titleTextStyle.fontSize ?? AppTheme.largeFontSize),
                color: AppTheme.gamePageActionSheetTextColor,
                fontWeight: FontWeight.normal,
                // ignore: always_specify_types
                fontFeatures: [const FontFeature.tabularFigures()]),
          ),
        ),
        actions: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (end > 0)
                Expanded(
                  child: TextButton(
                    child: Text(
                      S.of(context).rollback,
                      style: buttonTextStyle,
                    ),
                    onPressed: () async => _rollback(context, end),
                  ),
                ),
              Expanded(
                child: TextButton(
                  child: Text(
                    S.of(context).copy,
                    style: buttonTextStyle,
                  ),
                  onPressed: () => GameController.export(context),
                ),
              ),
              Expanded(
                child: TextButton(
                  child: Text(
                    S.of(context).cancel,
                    style: buttonTextStyle,
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

  Future<void> _rollback(BuildContext context, int end) async {
    final int? selectValue = await showDialog<int?>(
      context: context,
      builder: (BuildContext context) => NumberPickerDialog(
          endNumber: end,
          dialogTitle: S.of(context).pleaseSelect,
          displayMoveText: true),
    );

    if (selectValue == null) {
      return;
    }

    // ignore: use_build_context_synchronously
    await HistoryNavigator.takeBackN(context, selectValue);
  }
}
