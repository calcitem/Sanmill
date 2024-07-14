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

class _InsertionRuleActionModal extends StatelessWidget {
  const _InsertionRuleActionModal({
    required this.insertionRuleAction,
    required this.onChanged,
  });

  final InsertionRuleAction insertionRuleAction;
  final Function(InsertionRuleAction?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).removeByInsertion_Detail,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildRadioListTiles(context),
        ),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(
        context,
        S.of(context).removeByInsertionDisabled,
        InsertionRuleAction.disabled,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeByInsertionAlwaysAllowed,
        InsertionRuleAction.alwaysAllowed,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeByInsertionMovingPhaseOnly,
        InsertionRuleAction.movingPhaseOnly,
      ),
      _buildRadioListTile(
        context,
        S.of(context).removeByInsertionMovingPhaseLimitedPieces,
        InsertionRuleAction.movingPhaseLimitedPieces,
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    InsertionRuleAction value,
  ) {
    return Semantics(
      label: title,
      child: RadioListTile<InsertionRuleAction>(
        title: Text(title),
        groupValue: insertionRuleAction,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
