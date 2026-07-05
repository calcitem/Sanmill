// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Helpers for respecting Android/iOS system bars when [MediaQuery.padding]
/// under-reports the navigation bar inset.
abstract final class ScreenInsets {
  /// Bottom inset from the system navigation bar or home indicator.
  static double navigationBarInset(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    return math.max(mediaQuery.padding.bottom, mediaQuery.viewPadding.bottom);
  }

  /// Bottom padding for modal bottom-sheet content.
  ///
  /// Includes the navigation bar, any on-screen keyboard, and [extra] spacing.
  static double modalBottomSheetPadding(
    BuildContext context, {
    double extra = 0,
  }) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    return navigationBarInset(context) + mediaQuery.viewInsets.bottom + extra;
  }
}
