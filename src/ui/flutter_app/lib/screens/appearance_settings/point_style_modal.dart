// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

part of 'package:sanmill/screens/appearance_settings/appearance_settings_page.dart';

class _PointStyleModal extends StatelessWidget {
  const _PointStyleModal({
    Key? key,
    required this.pointStyle,
    required this.onChanged,
  }) : super(key: key);

  final PaintingStyle? pointStyle;
  final Function(PaintingStyle?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).pointStyle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile<PaintingStyle?>(
            title: Text(S.of(context).none),
            groupValue: pointStyle,
            value: null,
            onChanged: onChanged,
          ),
          RadioListTile(
            title: Text(S.of(context).solid),
            groupValue: pointStyle,
            value: PaintingStyle.fill,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
