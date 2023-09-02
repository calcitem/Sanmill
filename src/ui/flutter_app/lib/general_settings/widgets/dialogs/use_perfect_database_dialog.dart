// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

class _UsePerfectDatabaseDialog extends StatelessWidget {
  const _UsePerfectDatabaseDialog();

  Future<void> _ok(BuildContext context) async {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        S.of(context).usePerfectDatabase,
        style: AppTheme.dialogTitleTextStyle,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: SingleChildScrollView(
        child: Text(
          S.of(context).perfectDatabaseDescription,
          textScaleFactor: DB().displaySettings.fontScale,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _ok(context),
          child: Text(
            S.of(context).ok,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
        ),
      ],
    );
  }
}
