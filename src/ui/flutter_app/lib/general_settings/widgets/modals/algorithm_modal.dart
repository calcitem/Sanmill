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

class _AlgorithmModal extends StatelessWidget {
  const _AlgorithmModal({
    required this.algorithm,
    required this.onChanged,
  });

  final SearchAlgorithm algorithm;
  final Function(SearchAlgorithm?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('algorithm_modal_semantics'),
      label: S.of(context).algorithm,
      child: Column(
        key: const Key('algorithm_modal_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(
        context,
        SearchAlgorithm.alphaBeta.name,
        SearchAlgorithm.alphaBeta,
      ),
      _buildRadioListTile(
        context,
        SearchAlgorithm.pvs.name,
        SearchAlgorithm.pvs,
      ),
      _buildRadioListTile(
        context,
        SearchAlgorithm.mtdf.name,
        SearchAlgorithm.mtdf,
      ),
      _buildRadioListTile(
        context,
        SearchAlgorithm.mcts.name,
        SearchAlgorithm.mcts,
      ),
      _buildRadioListTile(
        context,
        SearchAlgorithm.random.name,
        SearchAlgorithm.random,
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    SearchAlgorithm value,
  ) {
    final String keySuffix = value.name.toLowerCase();
    return Semantics(
      key: Key('algorithm_modal_radio_list_tile_semantics_$keySuffix'),
      label: title,
      child: RadioListTile<SearchAlgorithm>(
        key: Key('algorithm_modal_radio_list_tile_$keySuffix'),
        title: Text(
          title,
          key: Key('algorithm_modal_radio_list_tile_${keySuffix}_title'),
        ),
        groupValue: algorithm,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
