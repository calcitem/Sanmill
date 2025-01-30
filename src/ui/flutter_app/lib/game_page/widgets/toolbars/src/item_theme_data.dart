// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// item_theme_data.dart

part of '../game_toolbar.dart';

/// A [ButtonStyle] that overrides the default appearance of
/// [ToolbarItem]s when it's used with [ToolbarItemTheme].
///
/// The [style]'s properties override [ToolbarItem]'s default style,
/// i.e.  the [ButtonStyle] returned by [ToolbarItem.defaultStyleOf]. Only
/// the style's non-null property values or resolved non-null
/// [WidgetStateProperty] values are used.
///
/// See also:
///
///  * [ToolbarItemTheme], the theme which is configured with this class.
///  * [ToolbarItem.defaultStyleOf], which returns the default [ButtonStyle]
///    for toolbar buttons.
///  * [ToolbarItem.styleFrom], which converts simple values into a
///    [ButtonStyle] that's consistent with [ToolbarItem]'s defaults.
///  * [WidgetStateProperty.resolve], "resolve" a material state property
///    to a simple value based on a set of [WidgetState]s.
@immutable
class ToolbarItemThemeData with Diagnosticable {
  /// Creates a [ToolbarItemThemeData].
  ///
  /// The [style] may be null.
  const ToolbarItemThemeData({this.style});

  /// Overrides for [ToolbarItem]'s default style.
  ///
  /// Non-null properties or non-null resolved [WidgetStateProperty]
  /// values override the [ButtonStyle] returned by
  /// [ToolbarItem.defaultStyleOf].
  ///
  /// If [style] is null, then this theme doesn't override anything.
  final ButtonStyle? style;

  /// Linearly interpolate between two toolbar button themes.
  static ToolbarItemThemeData? lerp(
    ToolbarItemThemeData? a,
    ToolbarItemThemeData? b,
    double t,
  ) {
    if (a == null && b == null) {
      return null;
    }
    return ToolbarItemThemeData(
      style: ButtonStyle.lerp(a?.style, b?.style, t),
    );
  }

  @override
  int get hashCode => style.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ToolbarItemThemeData && other.style == style;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<ButtonStyle>('style', style, defaultValue: null),
    );
  }
}
