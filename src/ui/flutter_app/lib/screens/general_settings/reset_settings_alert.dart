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

part of 'package:sanmill/screens/general_settings/general_settings_page.dart';

class _ResetSettingsAlert extends StatelessWidget {
  const _ResetSettingsAlert({Key? key}) : super(key: key);

  void _cancel(BuildContext context) => Navigator.pop(context);

  Future<void> _restore(BuildContext context) async {
    Navigator.pop(context);

    await DB.reset();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).restore,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: SingleChildScrollView(
        child: Text("${S.of(context).restoreDefaultSettings}?"),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _restore(context),
          child: Text(
            S.of(context).ok,
          ),
        ),
        TextButton(
          onPressed: () => _cancel(context),
          child: Text(
            S.of(context).cancel,
          ),
        ),
      ],
    );
  }
}
