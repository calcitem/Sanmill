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
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class NumberPicker extends StatelessWidget {
  const NumberPicker({
    super.key,
    this.start = 1,
    required this.end,
    required this.newTitle,
    required this.showMoveString,
  });

  final int start;
  final int end;
  final String newTitle;
  final bool showMoveString;

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).textTheme.bodyText1!.fontSize!;
    int selectValue = start;

    final List<Widget> items = List.generate(
      end,
      (int index) => Text(showMoveString
          ? S.of(context).moveNumber(start + index)
          : (start + index).toString()),
    );

    return AlertDialog(
      title: Text(
        newTitle,
        style: AppTheme.dialogTitleTextStyle,
        textScaleFactor: DB().displaySettings.fontScale,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: CupertinoPicker(
          itemExtent: size + 12,
          children: items,
          onSelectedItemChanged: (int numb) => selectValue = numb + 1,
        ),
      ),
      actions: [
        TextButton(
          child: Text(
            S.of(context).cancel,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text(
            S.of(context).confirm,
            textScaleFactor: DB().displaySettings.fontScale,
          ),
          onPressed: () => Navigator.pop(context, selectValue),
        ),
      ],
    );
  }
}
