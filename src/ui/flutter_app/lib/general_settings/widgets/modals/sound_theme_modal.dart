// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

class _SoundThemeModal extends StatelessWidget {
  const _SoundThemeModal({
    required this.soundTheme,
    required this.onChanged,
  });

  final SoundTheme soundTheme;
  final Function(SoundTheme?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).soundTheme,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(
        context,
        SoundTheme.ball.localeName(context),
        SoundTheme.ball,
      ),
      _buildRadioListTile(
        context,
        SoundTheme.liquid.localeName(context),
        SoundTheme.liquid,
      ),
      _buildRadioListTile(
        context,
        SoundTheme.wood.localeName(context),
        SoundTheme.wood,
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    SoundTheme value,
  ) {
    return Semantics(
      label: title,
      child: RadioListTile<SoundTheme>(
        title: Text(title),
        groupValue: soundTheme,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
