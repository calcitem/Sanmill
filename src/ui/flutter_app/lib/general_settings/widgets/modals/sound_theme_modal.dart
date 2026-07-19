// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// sound_theme_modal.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _SoundThemeModal extends StatefulWidget {
  const _SoundThemeModal({required this.soundTheme, required this.onChanged});

  final SoundTheme soundTheme;
  final Function(SoundTheme?)? onChanged;

  @override
  State<_SoundThemeModal> createState() => _SoundThemeModalState();
}

class _SoundThemeModalState extends State<_SoundThemeModal> {
  Sound _previewSound = Sound.place;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('sound_theme_modal_semantics'),
      label: S.of(context).soundTheme,
      child: Column(
        key: const Key('sound_theme_modal_column'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: DropdownButtonFormField<Sound>(
              key: const Key('sound_theme_modal_preview_event'),
              initialValue: _previewSound,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: S.of(context).previewSound,
                prefixIcon: const Icon(Icons.music_note_outlined),
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<Sound>>[
                DropdownMenuItem<Sound>(
                  key: const Key('sound_theme_modal_preview_event_place'),
                  value: Sound.place,
                  child: Text(S.of(context).soundEventMove),
                ),
                DropdownMenuItem<Sound>(
                  key: const Key('sound_theme_modal_preview_event_select'),
                  value: Sound.select,
                  child: Text(S.of(context).soundEventSelect),
                ),
                DropdownMenuItem<Sound>(
                  key: const Key('sound_theme_modal_preview_event_mill'),
                  value: Sound.mill,
                  child: Text(S.of(context).soundEventMill),
                ),
                DropdownMenuItem<Sound>(
                  key: const Key('sound_theme_modal_preview_event_remove'),
                  value: Sound.remove,
                  child: Text(S.of(context).soundEventRemove),
                ),
                DropdownMenuItem<Sound>(
                  key: const Key('sound_theme_modal_preview_event_illegal'),
                  value: Sound.illegal,
                  child: Text(S.of(context).soundEventIllegal),
                ),
              ],
              onChanged: (Sound? value) {
                assert(value != null, 'A preview sound must be selected.');
                if (value == null) {
                  return;
                }
                setState(() {
                  _previewSound = value;
                });
              },
            ),
          ),
          ..._buildRadioListTiles(context),
        ],
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
        secondary: IconButton(
          key: Key('sound_theme_modal_preview_$keySuffix'),
          tooltip: S.of(context).previewSound,
          icon: const Icon(Icons.volume_up_outlined),
          onPressed: () => unawaited(
            SoundManager().playSoundThemePreview(value, sound: _previewSound),
          ),
        ),
        groupValue: widget.soundTheme,
        value: value,
        onChanged: widget.onChanged,
      ),
    );
  }
}
