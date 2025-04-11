// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// fly_piece_count_modal.dart

part of 'package:sanmill/rule_settings/widgets/rule_settings_page.dart';

class _FlyPieceCountModal extends StatelessWidget {
  const _FlyPieceCountModal({
    required this.flyPieceCount,
    required this.onChanged,
  });

  final int flyPieceCount;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('fly_piece_count_semantics'),
      label: S.of(context).flyPieceCount,
      child: Column(
        key: const Key('fly_piece_count_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(context, "3", 3),
      _buildRadioListTile(context, "4", 4),
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
        groupValue: flyPieceCount,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
