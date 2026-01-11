// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// sound_theme_modal.dart

// ignore_for_file: deprecated_member_use

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _SoundThemeModal extends StatelessWidget {
  const _SoundThemeModal({required this.soundTheme, required this.onChanged});

  final SoundTheme soundTheme;
  final Function(SoundTheme?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('sound_theme_modal_semantics'),
      label: S.of(context).soundTheme,
      child: Column(
        key: const Key('sound_theme_modal_column'),
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
    final String keySuffix = value.name.toLowerCase();
    return Semantics(
      key: Key('sound_theme_modal_radio_list_tile_semantics_$keySuffix'),
      label: title,
      child: RadioListTile<SoundTheme>(
        key: Key('sound_theme_modal_radio_list_tile_$keySuffix'),
        title: Text(
          title,
          key: Key('sound_theme_modal_radio_list_tile_${keySuffix}_title'),
        ),
        groupValue: soundTheme,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
