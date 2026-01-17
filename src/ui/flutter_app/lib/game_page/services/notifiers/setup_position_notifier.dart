// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// setup_position_notifier.dart

part of '../mill.dart';

class SetupPositionNotifier with ChangeNotifier {
  SetupPositionNotifier();

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  void updateIcons() {
    // Debounce to prevent excessive notifications during rapid state changes
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    super.dispose();
  }
}
