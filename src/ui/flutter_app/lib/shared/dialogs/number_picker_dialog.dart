// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// number_picker_dialog.dart

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
        key: const Key('number_picker_dialog_title'),
        style: AppTheme.dialogTitleTextStyle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: CupertinoPicker(
          key: const Key('number_picker_cupertino_picker'),
          itemExtent: fontSize + 12,
          children: numberItems,
          onSelectedItemChanged: (int number) => selectedValue = number + 1,
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('number_picker_cancel_button'),
          child: Text(
            S.of(context).cancel,
            style: TextStyle(
                fontSize: AppTheme.textScaler.scale(AppTheme.defaultFontSize)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          key: const Key('number_picker_confirm_button'),
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
