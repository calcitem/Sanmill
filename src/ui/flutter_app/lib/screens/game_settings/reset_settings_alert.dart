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

part of 'package:sanmill/screens/game_settings/game_settings_page.dart';

class _ResetSettingsAlert extends StatelessWidget {
  const _ResetSettingsAlert({Key? key}) : super(key: key);

  void cancel(BuildContext context) => Navigator.pop(context);

  Future<void> _restore(BuildContext context) async {
    Navigator.pop(context);

    // TODO: we should probably enable database deletion in monkey tests
    //as the new storage backend supports deletion without needing an app restart
    if (!EnvironmentConfig.monkeyTest) {
      await LocalDatabaseService.resetStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: remove these strings as they aren't needed anymore
    //S.of(context).exitApp;
    //S.of(context).exitAppManually

    return AlertDialog(
      title: Text(
        S.of(context).restore,
        style: TextStyle(
          color: AppTheme.dialogTitleColor,
          fontSize: LocalDatabaseService.display.fontSize + 4,
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          "${S.of(context).restoreDefaultSettings}?",
          style: TextStyle(
            fontSize: LocalDatabaseService.display.fontSize,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _restore(context),
          child: Text(
            S.of(context).ok,
            style: TextStyle(
              fontSize: LocalDatabaseService.display.fontSize,
            ),
          ),
        ),
        TextButton(
          onPressed: () => cancel(context),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
              fontSize: LocalDatabaseService.display.fontSize,
            ),
          ),
        ),
      ],
    );
  }
}
