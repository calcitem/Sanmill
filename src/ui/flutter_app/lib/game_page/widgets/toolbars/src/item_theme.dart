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

/// Overrides the default [ButtonStyle] of its [ToolbarItem] descendants.
///
/// See also:
///
///  * [ToolbarItemThemeData], which is used to configure this theme.
///  * [ToolbarItem.defaultStyleOf], which returns the default [ButtonStyle]
///    for toolbar buttons.
///  * [ToolbarItem.styleFrom], which converts simple values into a
///    [ButtonStyle] that's consistent with [ToolbarItem]'s defaults.
class ToolbarItemTheme extends InheritedTheme {
  /// Create a [ToolbarItemTheme].
  ///
  /// The [data] parameter must not be null.
  const ToolbarItemTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The configuration of this theme.
  final ToolbarItemThemeData data;

  /// The closest instance of this class that encloses the given context.
  ///
  /// If there is no enclosing [ToolbarItemTheme] widget, then
  /// the default [ToolbarItemThemeData] is used.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// ToolbarItemTheme theme = ToolbarItemTheme.of(context);
  /// ```
  static ToolbarItemThemeData of(BuildContext context) {
    final ToolbarItemTheme? buttonTheme =
        context.dependOnInheritedWidgetOfExactType<ToolbarItemTheme>();
    return buttonTheme?.data ?? const ToolbarItemThemeData();
  }

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ToolbarItemTheme(data: data, child: child);

  @override
  bool updateShouldNotify(ToolbarItemTheme oldWidget) => data != oldWidget.data;
}
