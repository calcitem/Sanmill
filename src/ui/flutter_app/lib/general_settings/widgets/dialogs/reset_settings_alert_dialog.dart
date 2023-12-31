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

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _ResetSettingsAlertDialog extends StatelessWidget {
  const _ResetSettingsAlertDialog();

  void _cancel(BuildContext context) => Navigator.pop(context);

  Future<void> _restore(BuildContext context) async {
    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).reopenToTakeEffect);

    Navigator.pop(context);

    // TODO: Seems to need to close and reopen the program for it to work.
    await DB.reset();

    GameController().reset(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).restore,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        child: Text(
          "${S.of(context).restoreDefaultSettings}?",
          style: TextStyle(
              fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _restore(context),
          child: Text(
            S.of(context).ok,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
        ),
        TextButton(
          onPressed: () => _cancel(context),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
        ),
      ],
    );
  }
}
