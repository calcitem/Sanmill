// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// custom_drawer_value.dart

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
