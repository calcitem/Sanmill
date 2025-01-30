// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// item_theme.dart

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
  /// ToolbarItemThemeData theme = ToolbarItemTheme.of(context);
  /// ```
  static ToolbarItemThemeData of(BuildContext context) {
    final ToolbarItemTheme? buttonTheme =
        context.dependOnInheritedWidgetOfExactType<ToolbarItemTheme>();
    return buttonTheme?.data ?? const ToolbarItemThemeData();
  }

  @override
  Widget wrap(BuildContext context, Widget child) => ToolbarItemTheme(
        key: const Key('toolbar_item_theme_wrap'),
        data: data,
        child: child,
      );

  @override
  bool updateShouldNotify(ToolbarItemTheme oldWidget) => data != oldWidget.data;
}
