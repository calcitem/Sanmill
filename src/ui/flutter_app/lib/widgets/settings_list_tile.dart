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
import 'package:sanmill/style/app_theme.dart';

class SettingsListTile extends StatelessWidget {
  const SettingsListTile({
    Key? key,
    required this.context,
    required this.titleString,
    this.subtitleString,
    this.trailingString,
    this.trailingColor,
    required this.onTap,
  }) : super(key: key);

  final BuildContext context;
  final String titleString;
  final String? subtitleString;
  final String? trailingString;
  final int? trailingColor;
  final onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(titleString,
          style: TextStyle(color: AppTheme.switchListTileTitleColor)),
      subtitle: subtitleString == null
          ? null
          : Text(
              subtitleString!,
              style: TextStyle(color: AppTheme.listTileSubtitleColor),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            trailingColor == null
                ? (trailingString == null ? "" : trailingString!)
                : trailingColor!.toRadixString(16),
            style: TextStyle(
              backgroundColor:
                  trailingColor == null ? null : Color(trailingColor!),
            ),
          ),
          Icon(Icons.keyboard_arrow_right,
              color: AppTheme.listTileSubtitleColor),
        ],
      ),
      onTap: onTap,
    );
  }
}
