// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

// A modal widget to select a rule set for the game.
class _RuleSetModal extends StatelessWidget {
  const _RuleSetModal({
    required this.ruleSet,
    required this.onChanged,
  });

  final RuleSet ruleSet;
  final Function(RuleSet?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).ruleSet,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RadioListTile<RuleSet>(
              title: Text(S.of(context).currentRule),
              groupValue: ruleSet,
              value: RuleSet.current,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).nineMensMorris),
              groupValue: ruleSet,
              value: RuleSet.nineMensMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).twelveMensMorris),
              groupValue: ruleSet,
              value: RuleSet.twelveMensMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).morabaraba),
              groupValue: ruleSet,
              value: RuleSet.morabaraba,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).dooz),
              groupValue: ruleSet,
              value: RuleSet.dooz,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).laskerMorris),
              groupValue: ruleSet,
              value: RuleSet.laskerMorris,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).oneTimeMill),
              groupValue: ruleSet,
              value: RuleSet.oneTimeMill,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).chamGonu),
              groupValue: ruleSet,
              value: RuleSet.chamGonu,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).zhiQi),
              groupValue: ruleSet,
              value: RuleSet.zhiQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).chengSanQi),
              groupValue: ruleSet,
              value: RuleSet.chengSanQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).daSanQi),
              groupValue: ruleSet,
              value: RuleSet.daSanQi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).mulMulan),
              groupValue: ruleSet,
              value: RuleSet.mulMulan,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).nerenchi),
              groupValue: ruleSet,
              value: RuleSet.nerenchi,
              onChanged: onChanged,
            ),
            RadioListTile<RuleSet>(
              title: Text(S.of(context).elfilja),
              groupValue: ruleSet,
              value: RuleSet.elfilja,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
