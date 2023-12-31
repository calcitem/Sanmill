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

part of '../../custom_drawer/custom_drawer.dart';

/// CustomDrawer Value
///
/// The different states at the [CustomDrawer] can be in
class CustomDrawerValue {
  const CustomDrawerValue({
    this.isDrawerVisible = false,
  });

  /// Creates a value with hidden state
  factory CustomDrawerValue.hidden() => const CustomDrawerValue();

  /// Creates a value with visible state
  factory CustomDrawerValue.visible() => const CustomDrawerValue(
        isDrawerVisible: true,
      );

  /// Indicates whether drawer visible or not
  final bool isDrawerVisible;
}
