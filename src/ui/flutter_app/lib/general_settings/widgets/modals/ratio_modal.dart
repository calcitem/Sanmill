// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ratio_modal.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _RatioModal extends StatelessWidget {
  const _RatioModal({
    required this.ratio,
    required this.onChanged,
  });

  final int ratio;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('ratio_modal_semantics'),
      label: S.of(context).pixelRatio, // TODO: Ratio
      child: Column(
        key: const Key('ratio_modal_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(context, "25%", 25),
      _buildRadioListTile(context, "50%", 50),
      _buildRadioListTile(context, "75%", 75),
      _buildRadioListTile(context, "100%", 100),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    int value,
  ) {
    return Semantics(
      key: Key('ratio_modal_radio_list_tile_semantics_$value'),
      label: title,
      child: RadioListTile<int>(
        key: Key('ratio_modal_radio_list_tile_$value'),
        title: Text(
          title,
          key: Key('ratio_modal_radio_list_tile_${value}_title'),
        ),
        groupValue: ratio,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
