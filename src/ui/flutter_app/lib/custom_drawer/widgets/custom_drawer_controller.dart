// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_controller.dart

part of '../../custom_drawer/custom_drawer.dart';

/// Custom Drawer Controller
///
/// Manages the [CustomDrawer] state
class CustomDrawerController extends ValueNotifier<CustomDrawerValue> {
  /// Creates a controller with the initial drawer state (Hidden by default)
  CustomDrawerController([CustomDrawerValue? value])
      : super(value ?? CustomDrawerValue.hidden());

  /// Shows the drawer
  void showDrawer() => value = CustomDrawerValue.visible();

  /// Hides the drawer
  void hideDrawer() => value = CustomDrawerValue.hidden();

  /// Toggles the drawer visibility
  void toggleDrawer() => value.isDrawerVisible ? hideDrawer() : showDrawer();
}
