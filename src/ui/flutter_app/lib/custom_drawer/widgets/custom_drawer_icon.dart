// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_icon.dart

part of '../../custom_drawer/custom_drawer.dart';

/// Custom Drawer Icon
///
/// Displays the drawer icon in the app bar.
class CustomDrawerIcon extends InheritedWidget {
  const CustomDrawerIcon({
    super.key,
    required this.drawerIcon,
    required super.child,
  });

  final Widget drawerIcon;

  @override
  bool updateShouldNotify(InheritedWidget oldWidget) => false;

  static CustomDrawerIcon? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomDrawerIcon>();
}
