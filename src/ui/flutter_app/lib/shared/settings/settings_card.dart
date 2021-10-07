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
import 'package:sanmill/shared/list_item_divider.dart';
import 'package:sanmill/shared/theme/app_theme.dart';


class SettingsCard extends StatelessWidget {
  const SettingsCard({
    Key? key,
    required this.context,
    required this.children,
  }) : super(key: key);

  final BuildContext context;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.cardColor,
      margin: AppTheme.cardMargin,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemBuilder: (_, index) => children[index],
        separatorBuilder: (_, __) => const ListItemDivider(),
        itemCount: children.length,
      ),
    );
  }
}
