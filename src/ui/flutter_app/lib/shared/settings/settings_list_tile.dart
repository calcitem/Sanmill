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
    final bool ltr = Directionality.of(context) == TextDirection.ltr;

    final Widget trailing;
    if (trailingColor != null) {
      trailing = Text(
        trailingColor!.value.toRadixString(16),
        style: TextStyle(backgroundColor: trailingColor),
      );
    } else if (trailingString != null) {
      trailing = Text(
        trailingString!,
        style: AppTheme.listTileSubtitleStyle,
      );
    } else {
      trailing = Icon(
        ltr
            ? FluentIcons.chevron_right_24_regular
            : FluentIcons.chevron_left_24_regular,
        color: AppTheme.listTileSubtitleColor,
      );
    }

    return ListTile(
      title: Text(
        titleString,
        style: AppTheme.listTileTitleStyle,
      ),
      subtitle: subtitleString != null
          ? Text(subtitleString!, style: AppTheme.listTileSubtitleStyle)
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
