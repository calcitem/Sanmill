// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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
      label: S.of(context).algorithm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile<SearchAlgorithm>(
            title: Text(SearchAlgorithm.alphaBeta.name),
            groupValue: algorithm,
            value: SearchAlgorithm.alphaBeta,
            onChanged: onChanged,
          ),
          RadioListTile<SearchAlgorithm>(
            title: Text(SearchAlgorithm.pvs.name),
            groupValue: algorithm,
            value: SearchAlgorithm.pvs,
            onChanged: onChanged,
          ),
          RadioListTile<SearchAlgorithm>(
            title: Text(SearchAlgorithm.mtdf.name),
            groupValue: algorithm,
            value: SearchAlgorithm.mtdf,
            onChanged: onChanged,
          ),
          RadioListTile<SearchAlgorithm>(
            title: Text(SearchAlgorithm.mcts.name),
            groupValue: algorithm,
            value: SearchAlgorithm.mcts,
            onChanged: onChanged,
          ),
          if (Platform.isWindows || Platform.isLinux)
            RadioListTile<SearchAlgorithm>(
              title: Text(SearchAlgorithm.retrogradeAnalysis.name),
              groupValue: algorithm,
              value: SearchAlgorithm.retrogradeAnalysis,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
