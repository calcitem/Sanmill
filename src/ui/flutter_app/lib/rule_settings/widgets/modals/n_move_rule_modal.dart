// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// n_move_rule_modal.dart

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
      key: const Key('n_move_rule_semantics'),
      label: S.of(context).nMoveRule,
      child: Column(
        key: const Key('n_move_rule_column'),
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
      key: Key('semantics_$value'),
      label: title,
      child: RadioListTile<int>(
        key: Key('radio_$value'),
        title: Text(title),
        groupValue: nMoveRule,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
