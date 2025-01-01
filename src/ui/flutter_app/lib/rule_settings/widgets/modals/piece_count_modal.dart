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
      label: S.of(context).piecesCount,
      child: Column(
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
      label: title,
      child: RadioListTile<int>(
        title: Text(title),
        groupValue: piecesCount,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
