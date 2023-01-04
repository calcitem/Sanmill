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

part of 'package:sanmill/screens/appearance_settings/appearance_settings_page.dart';

enum ColorTheme {
  current,
  light,
  dark,
}

class _ThemeModal extends StatelessWidget {
  const _ThemeModal({
    required this.theme,
    required this.onChanged,
  });

  final ColorTheme theme;
  final Function(ColorTheme?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).theme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile<ColorTheme>(
            title: Text(S.of(context).currentTheme),
            groupValue: theme,
            value: ColorTheme.current,
            onChanged: onChanged,
          ),
          RadioListTile<ColorTheme>(
            title: Text(S.of(context).light),
            groupValue: theme,
            value: ColorTheme.light,
            onChanged: onChanged,
          ),
          RadioListTile<ColorTheme>(
            title: Text(S.of(context).dark),
            groupValue: theme,
            value: ColorTheme.dark,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
