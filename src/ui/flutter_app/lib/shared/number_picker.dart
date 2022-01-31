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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class NumberPicker extends StatelessWidget {
  const NumberPicker({
    Key? key,
    this.start = 1,
    required this.end,
  }) : super(key: key);

  final int start;
  final int end;

  @override
  Widget build(BuildContext context) {
    final _size = Theme.of(context).textTheme.bodyText1!.fontSize!;
    int _selectValue = start;

    final List<Widget> _items = List.generate(
      end,
      (index) => Text(S.of(context).moveNumber(start + index)),
    );

    return AlertDialog(
      title: Text(
        S.of(context).pleaseSelect,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: CupertinoPicker(
          itemExtent: _size + 12,
          children: _items,
          onSelectedItemChanged: (numb) => _selectValue = numb + 1,
        ),
      ),
      actions: [
        TextButton(
          child: Text(
            S.of(context).cancel,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text(
            S.of(context).confirm,
          ),
          onPressed: () => Navigator.pop(context, _selectValue),
        ),
      ],
    );
  }
}
