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

part of '../game_toolbar.dart';

class GamePageToolbar extends StatelessWidget {
  const GamePageToolbar({
    super.key,
    required this.children,
    this.backgroundColor,
    this.itemColor,
  });

  final List<Widget> children;
  final Color? backgroundColor;
  final Color? itemColor;

  static const EdgeInsets _padding = EdgeInsets.symmetric(vertical: 2);
  static const EdgeInsets _margin = EdgeInsets.symmetric(vertical: 0.5);

  /// Gets the calculated height this widget adds to it's children.
  /// To get the absolute height add the surrounding [ButtonThemeData.height].
  static double get height => (_padding.vertical + _margin.vertical) * 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: backgroundColor,
      ),
      margin: _margin,
      padding: _padding,
      child: ToolbarItemTheme(
        data: ToolbarItemThemeData(
          style: ToolbarItem.styleFrom(primary: itemColor),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: children,
          ),
        ),
      ),
    );
  }
}
