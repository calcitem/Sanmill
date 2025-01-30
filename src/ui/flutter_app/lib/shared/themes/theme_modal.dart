// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// theme_modal.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

enum ColorTheme {
  current,
  light,
  dark,
  monochrome,
  transparentCanvas,
  autumnLeaves,
  legendaryLand,
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
              title: Text(S.of(context).monochrome),
              groupValue: theme,
              value: ColorTheme.monochrome,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).transparentCanvas),
              groupValue: theme,
              value: ColorTheme.transparentCanvas,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).autumnLeaves),
              groupValue: theme,
              value: ColorTheme.autumnLeaves,
              onChanged: onChanged,
            ),
            RadioListTile<ColorTheme>(
              title: Text(S.of(context).legendaryLand),
              groupValue: theme,
              value: ColorTheme.legendaryLand,
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
