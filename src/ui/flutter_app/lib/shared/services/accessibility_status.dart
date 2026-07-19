// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Current accessibility state reported by the operating system.
abstract final class AccessibilityStatus {
  /// Whether TalkBack, VoiceOver, or an equivalent navigation service is on.
  ///
  /// Desktop embedders do not all report [accessibleNavigation], so a direct
  /// platform request for the semantics tree is also treated as active. This
  /// deliberately ignores framework-only semantics handles used by tests and
  /// inspection tools.
  static bool get isScreenReaderActive {
    final WidgetsBinding binding = WidgetsBinding.instance;
    return binding
            .platformDispatcher
            .accessibilityFeatures
            .accessibleNavigation ||
        binding.platformDispatcher.semanticsEnabled;
  }

  /// Whether Flutter is currently producing a semantics tree.
  static bool get semanticsEnabled =>
      SemanticsBinding.instance.semanticsEnabled;
}
