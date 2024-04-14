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
      ),
      _buildRadioListTile(
        context,
        S.of(context).solid,
        PointPaintingStyle.fill,
      ),
    ];
  }

  Widget _buildRadioListTile(
    BuildContext context,
    String title,
    PointPaintingStyle value,
  ) {
    return Semantics(
      label: title,
      child: RadioListTile<PointPaintingStyle>(
        title: Text(title),
        groupValue: pointPaintingStyle,
        value: value,
        onChanged: onPointPaintingStyleChanged,
      ),
    );
  }
}
