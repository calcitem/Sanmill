// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_result_notifier.dart

part of '../mill.dart';

class GameResultNotifier with ChangeNotifier {
  GameResultNotifier();

  bool _force = false;
  bool get force => _force;

  void showResult({required bool force}) {
    _force = force;
    notifyListeners();
  }
}
