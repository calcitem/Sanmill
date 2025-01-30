// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// setup_position_notifier.dart

part of '../mill.dart';

class SetupPositionNotifier with ChangeNotifier {
  SetupPositionNotifier();

  void updateIcons() {
    Future<void>.delayed(Duration.zero, () {
      notifyListeners();
    });
  }
}
