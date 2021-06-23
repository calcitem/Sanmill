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
import 'package:sanmill/common/config.dart';
import 'package:sanmill/style/app_theme.dart';

class SettingsSwitchListTile extends StatelessWidget {
  const SettingsSwitchListTile({
    Key? key,
    required this.context,
    required this.value,
    required this.onChanged,
    required this.titleString,
    this.subtitleString,
  }) : super(key: key);

  final BuildContext context;
  final value;
  final String titleString;
  final String? subtitleString;
  final onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.switchListTileActiveColor,
      title: Text(
        titleString,
        style: TextStyle(
          fontSize: Config.fontSize,
          color: AppTheme.switchListTileTitleColor,
        ),
      ),
      subtitle: subtitleString == null
          ? null
          : Text(
              subtitleString!,
              style: TextStyle(
                fontSize: Config.fontSize,
                color: AppTheme.listTileSubtitleColor,
              ),
            ),
    );
  }
}
