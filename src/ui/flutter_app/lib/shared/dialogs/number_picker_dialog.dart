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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../themes/app_theme.dart';

class NumberPickerDialog extends StatelessWidget {
  const NumberPickerDialog({
    super.key,
    this.startNumber = 1,
    required this.endNumber,
    required this.dialogTitle,
    required this.displayMoveText,
  });

  final int startNumber;
  final int endNumber;
  final String dialogTitle;
  final bool displayMoveText;

  @override
  Widget build(BuildContext context) {
    final double fontSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
    int selectedValue = startNumber;

    final List<Widget> numberItems = List<Widget>.generate(
      endNumber,
      (int index) => Text(displayMoveText
          ? S.of(context).moveNumber(startNumber + index)
          : (startNumber + index).toString()),
    );

    return AlertDialog(
      title: Text(
        dialogTitle,
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: CupertinoPicker(
          itemExtent: fontSize + 12,
          children: numberItems,
          onSelectedItemChanged: (int number) => selectedValue = number + 1,
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text(
            S.of(context).confirm,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context, selectedValue),
        ),
      ],
    );
  }
}
