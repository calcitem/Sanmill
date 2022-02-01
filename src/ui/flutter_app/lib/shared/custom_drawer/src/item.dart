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

part of '../custom_drawer.dart';

class CustomDrawerItem<T> extends StatelessWidget {
  const CustomDrawerItem({
    Key? key,
    required this.groupValue,
    required this.onChanged,
    required this.value,
    required this.title,
    required this.icon,
  }) : super(key: key);

  final T groupValue;
  final Function(T) onChanged;
  final T value;
  final String title;
  final Icon icon;

  bool get selected => groupValue == value;

  @override
  Widget build(BuildContext context) {
    // TODO: drawerHighlightTextColor
    final _color = selected
        ? DB().colorSettings.drawerTextColor
        : DB().colorSettings.drawerTextColor;

    final listItemIcon = Icon(
      icon.icon,
      color: _color,
    );

    final _drawerItem = Row(
      children: <Widget>[
        const SizedBox(height: 46.0, width: 6.0),
        const Padding(padding: EdgeInsets.all(4.0)),
        listItemIcon,
        const Padding(padding: EdgeInsets.all(4.0)),
        Text(
          title,
          style: Theme.of(context).textTheme.headline6!.copyWith(
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: _color,
              ),
        ),
      ],
    );

    return InkWell(
      splashColor: AppTheme.drawerSplashColor,
      highlightColor: Colors.transparent,
      onTap: () => onChanged(value),
      child: _drawerItem,
    );
  }
}
