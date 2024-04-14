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

class _NMoveRuleModal extends StatelessWidget {
  const _NMoveRuleModal({
    required this.nMoveRule,
    required this.onChanged,
  });

  final int nMoveRule;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).nMoveRule,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(context, "30", 30),
      _buildRadioListTile(context, "50", 50),
      _buildRadioListTile(context, "60", 60),
      _buildRadioListTile(context, "100", 100),
      _buildRadioListTile(context, "200", 200),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    int value,
  ) {
    return Semantics(
      label: title,
      child: RadioListTile<int>(
        title: Text(title),
        groupValue: nMoveRule,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
