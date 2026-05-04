// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// analysis_mode.dart

// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/material.dart';

/// Holds the on/off flag for the perfect-database analysis overlay.
///
/// The actual analyze toolbar and renderer were retired together with
/// the legacy C++ engine in the Phase 3 / Phase 4 cleanup; this class
/// remains as a tiny state holder so historical replay events
/// (`analysisOn` / `analysisOff` recorded against older builds) and
/// the few `AnalysisMode.disable()` resets from `GameController` keep
/// compiling.  It can be deleted once all callers are migrated to the
/// Rust analyze backend (no current ETA).
class AnalysisMode {
  static bool _isEnabled = false;
  static bool _isAnalyzing = false;

  /// Notifies listeners when the enabled flag flips.  Kept for
  /// backwards compat with widgets that still subscribe to it.
  static final ValueNotifier<bool> stateNotifier = ValueNotifier<bool>(false);

  /// Returns whether analysis mode is currently enabled.  Always
  /// `false` on this branch because no caller flips the flag on.
  static bool get isEnabled => _isEnabled;

  /// Returns whether an analysis is currently in progress.
  static bool get isAnalyzing => _isAnalyzing;

  /// Disable the (always-off) analysis overlay.  Idempotent.
  static void disable() {
    if (!_isEnabled && !_isAnalyzing) {
      return;
    }
    _isEnabled = false;
    _isAnalyzing = false;
    stateNotifier.value = false;
  }

  /// Track when an analysis pass starts / finishes.  Kept for the
  /// few diagnostic call-sites that toggle this flag; the analyze
  /// backend itself is gone.
  static void setAnalyzing(bool analyzing) {
    _isAnalyzing = analyzing;
    stateNotifier.value = _isEnabled;
  }
}
