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
