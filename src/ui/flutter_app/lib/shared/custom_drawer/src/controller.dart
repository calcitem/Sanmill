// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
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

/// Custom Drawer Controller
///
/// manages the [CustomDrawer] state
class CustomDrawerController extends ValueNotifier<CustomDrawerValue> {
  /// Creates a controller with the initial drawer state (Hidden by default)
  CustomDrawerController([CustomDrawerValue? value])
      : super(value ?? CustomDrawerValue.hidden());

  /// shows the drawer
  void showDrawer() {
    value = CustomDrawerValue.visible();
  }

  /// hides the drawer
  void hideDrawer() {
    value = CustomDrawerValue.hidden();
  }

  /// toggles the drawer visibility
  void toggleDrawer() {
    if (value.visible) {
      hideDrawer();
    } else {
      showDrawer();
    }
  }
}
