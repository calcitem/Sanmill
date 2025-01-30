// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_semantics_notifier.dart

part of '../mill.dart';

class BoardSemanticsNotifier with ChangeNotifier {
  BoardSemanticsNotifier();

  void updateSemantics() {
    if (DB().generalSettings.screenReaderSupport) {
      notifyListeners();
    }
  }
}
