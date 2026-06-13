// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// setup_position_notifier.dart

part of '../mill.dart';

/// Notifies the setup-position toolbar that the editor model changed so it
/// can refresh its icons/labels.  Board taps (handled in `TapHandler`)
/// call [updateIcons] after mutating the setup controller, and the
/// toolbar listens to rebuild.  Notifications are debounced to avoid
/// excessive rebuilds during rapid edits.
class SetupPositionNotifier with ChangeNotifier {
  SetupPositionNotifier();

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  void updateIcons() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, notifyListeners);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    super.dispose();
  }
}
