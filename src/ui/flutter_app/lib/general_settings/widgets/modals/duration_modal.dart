// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// duration_modal.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _DurationModal extends StatelessWidget {
  const _DurationModal({
    required this.duration,
    required this.onChanged,
  });

  final int duration;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('duration_modal_semantics'),
      label: S.of(context).duration,
      child: Column(
        key: const Key('duration_modal_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(context, "1", 1),
      _buildRadioListTile(context, "2", 2),
      _buildRadioListTile(context, "3", 3),
      _buildRadioListTile(context, "5", 5),
      _buildRadioListTile(context, "10", 10),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    int value,
  ) {
    return Semantics(
      key: Key('duration_modal_radio_list_tile_semantics_$value'),
      label: title,
      child: RadioListTile<int>(
        key: Key('duration_modal_radio_list_tile_$value'),
        title: Text(
          title,
          key: Key('duration_modal_radio_list_tile_${value}_title'),
        ),
        groupValue: duration,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
