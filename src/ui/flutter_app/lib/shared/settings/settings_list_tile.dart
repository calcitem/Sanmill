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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class SettingsListTile extends StatelessWidget {
  const SettingsListTile({
    Key? key,
    required this.titleString,
    this.subtitleString,
    this.trailingString,
    this.trailingColor,
    required this.onTap,
  }) : super(key: key);

  final String titleString;
  final String? subtitleString;
  final String? trailingString;
  final Color? trailingColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        titleString,
        style: AppTheme.listTileTitleStyle,
      ),
      subtitle: subtitleString != null
          ? Text(subtitleString!, style: AppTheme.listTileSubtitleStyle)
          : null,
      // TODO: [Leptopoda] fix the trailing widget
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            trailingColor?.value.toRadixString(16) ?? trailingString ?? '',
            style: TextStyle(backgroundColor: trailingColor),
          ),
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Icon(
              FluentIcons.chevron_right_24_regular,
              color: AppTheme.listTileSubtitleColor,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
