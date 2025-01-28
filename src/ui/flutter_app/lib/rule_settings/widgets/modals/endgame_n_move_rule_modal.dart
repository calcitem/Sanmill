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

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

class _EndGameNMoveRuleModal extends StatelessWidget {
  const _EndGameNMoveRuleModal({
    required this.endgameNMoveRule,
    required this.onChanged,
  });

  final int endgameNMoveRule;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('end_game_n_move_rule_semantics'),
      label: S.of(context).endgameNMoveRule,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile<int>(
              key: const Key('radio_5'),
              title: const Text("5"),
              groupValue: endgameNMoveRule,
              value: 5,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_10'),
              title: const Text("10"),
              groupValue: endgameNMoveRule,
              value: 10,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_20'),
              title: const Text("20"),
              groupValue: endgameNMoveRule,
              value: 20,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_30'),
              title: const Text("30"),
              groupValue: endgameNMoveRule,
              value: 30,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_50'),
              title: const Text("50"),
              groupValue: endgameNMoveRule,
              value: 50,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_60'),
              title: const Text("60"),
              groupValue: endgameNMoveRule,
              value: 60,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_100'),
              title: const Text("100"),
              groupValue: endgameNMoveRule,
              value: 100,
              onChanged: onChanged,
            ),
            RadioListTile<int>(
              key: const Key('radio_200'),
              title: const Text("200"),
              groupValue: endgameNMoveRule,
              value: 200,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
