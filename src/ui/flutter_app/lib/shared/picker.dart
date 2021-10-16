/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:flutter_picker/flutter_picker.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/shared/common/config.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

Future<int> showPickerNumber(
  BuildContext context,
  int begin,
  int end,
  int initValue,
  String suffixString,
) async {
  int selectValue = 0;
  await Picker(
    adapter: NumberPickerAdapter(
      data: [
        NumberPickerColumn(
          begin: begin,
          end: end,
          initValue: initValue,
          suffix: Text(
            suffixString,
            style: TextStyle(
              fontSize: Config.fontSize,
            ),
          ),
        ),
      ],
    ),
    hideHeader: true,
    title: Text(
      S.of(context).pleaseSelect,
      style: TextStyle(
        color: AppTheme.appPrimaryColor,
        fontSize: Config.fontSize + 4.0,
      ),
    ),
    textStyle: TextStyle(
      color: Colors.black,
      fontSize: Config.fontSize,
    ),
    selectedTextStyle: const TextStyle(color: AppTheme.appPrimaryColor),
    cancelText: S.of(context).cancel,
    cancelTextStyle: TextStyle(
      color: AppTheme.appPrimaryColor,
      fontSize: Config.fontSize,
    ),
    confirmText: S.of(context).confirm,
    confirmTextStyle: TextStyle(
      color: AppTheme.appPrimaryColor,
      fontSize: Config.fontSize,
    ),
    onConfirm: (Picker picker, List value) async {
      debugPrint(value.toString());
      final List selectValues = picker.getSelectedValues();
      debugPrint(selectValues.toString());
      selectValue = selectValues[0] as int;
    },
  ).showDialog(context);

  return selectValue;
}
