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

class _DurationModal extends StatelessWidget {
  const _DurationModal({
    required this.duration,
    required this.onChanged,
  });

  final int duration;
  final Function(int?)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.of(context).duration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RadioListTile<int>(
            title: const Text("1"),
            groupValue: duration,
            value: 1,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("2"),
            groupValue: duration,
            value: 2,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("3"),
            groupValue: duration,
            value: 3,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("5"),
            groupValue: duration,
            value: 5,
            onChanged: onChanged,
          ),
          RadioListTile<int>(
            title: const Text("10"),
            groupValue: duration,
            value: 10,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
