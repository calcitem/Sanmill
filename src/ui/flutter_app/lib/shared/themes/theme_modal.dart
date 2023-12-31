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

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

enum ColorTheme {
  current,
  light,
  dark,
  goldenJade,
  forestWood,
  greenMeadow,
  stonyPath,
  midnightBlue,
  greenForest,
  pastelPink,
  turquoiseSea,
  violetDream,
  mintChocolate,
  skyBlue,
  playfulGarden,
  darkMystery,
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
      child: SingleChildScrollView(
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
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).goldenJade),
              groupValue: theme,
              value: ColorTheme.goldenJade,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).forestWood),
              groupValue: theme,
              value: ColorTheme.forestWood,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).greenMeadow),
              groupValue: theme,
              value: ColorTheme.greenMeadow,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).stonyPath),
              groupValue: theme,
              value: ColorTheme.stonyPath,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).midnightBlue),
              groupValue: theme,
              value: ColorTheme.midnightBlue,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).greenForest),
              groupValue: theme,
              value: ColorTheme.greenForest,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).pastelPink),
              groupValue: theme,
              value: ColorTheme.pastelPink,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).turquoiseSea),
              groupValue: theme,
              value: ColorTheme.turquoiseSea,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).violetDream),
              groupValue: theme,
              value: ColorTheme.violetDream,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).mintChocolate),
              groupValue: theme,
              value: ColorTheme.mintChocolate,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).skyBlue),
              groupValue: theme,
              value: ColorTheme.skyBlue,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).playfulGarden),
              groupValue: theme,
              value: ColorTheme.playfulGarden,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).darkMystery),
              groupValue: theme,
              value: ColorTheme.darkMystery,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
