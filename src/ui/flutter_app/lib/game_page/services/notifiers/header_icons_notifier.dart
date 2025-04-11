// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// header_icons_notifier.dart

part of '../mill.dart';

class HeaderIconsNotifier with ChangeNotifier {
  HeaderIconsNotifier();

  void showIcons() {
    Future<void>.delayed(Duration.zero, () {
      Future<void>.delayed(Duration.zero, () {
        notifyListeners();
      });
    });
  }
}
