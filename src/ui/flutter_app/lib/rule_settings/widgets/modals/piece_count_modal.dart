// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece_count_modal.dart

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

class _PieceCountModal extends StatelessWidget {
  const _PieceCountModal({
    required this.piecesCount,
    required this.onChanged,
  });

  final int piecesCount;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('piece_count_semantics'),
      label: S.of(context).piecesCount,
      child: Column(
        key: const Key('piece_count_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(context, "9", 9),
      _buildRadioListTile(context, "10", 10),
      _buildRadioListTile(context, "11", 11),
      _buildRadioListTile(context, "12", 12),
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
        groupValue: piecesCount,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
