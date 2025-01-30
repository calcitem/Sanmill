// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// algorithm_modal.dart

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
