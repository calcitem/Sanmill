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

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _RatioModal extends StatelessWidget {
  const _RatioModal({
    required this.ratio,
    required this.onChanged,
  });

  final int ratio;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).pixelRatio, // TODO: ratio
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile<int>(
            title: const Text("25%"),
            groupValue: ratio,
            value: 25,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("50%"),
            groupValue: ratio,
            value: 50,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("75%"),
            groupValue: ratio,
            value: 75,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("100%"),
            groupValue: ratio,
            value: 100,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
