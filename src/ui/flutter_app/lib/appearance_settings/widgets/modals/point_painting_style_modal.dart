// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// point_painting_style_modal.dart

part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

class _PointPaintingStyleModal extends StatelessWidget {
  const _PointPaintingStyleModal({
    required this.pointPaintingStyle,
    required this.onPointPaintingStyleChanged,
  });

  final PointPaintingStyle? pointPaintingStyle;
  final Function(PointPaintingStyle?) onPointPaintingStyleChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).pointStyle,
      child: Column(
        key: const Key('point_painting_style_column'),
        mainAxisSize: MainAxisSize.min,
        children: _buildRadioListTiles(context),
      ),
    );
  }

  List<Widget> _buildRadioListTiles(BuildContext context) {
    return <Widget>[
      _buildRadioListTile(
        context,
        S.of(context).none,
        PointPaintingStyle.none,
        key: const Key('radio_none'),
      ),
      _buildRadioListTile(
        context,
        S.of(context).solid,
        PointPaintingStyle.fill,
        key: const Key('radio_solid'),
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    PointPaintingStyle value, {
    required Key key,
  }) {
    return Semantics(
      label: title,
      child: RadioListTile<PointPaintingStyle>(
        key: key,
        title: Text(title),
        groupValue: pointPaintingStyle,
        value: value,
        onChanged: onPointPaintingStyleChanged,
      ),
    );
  }
}
