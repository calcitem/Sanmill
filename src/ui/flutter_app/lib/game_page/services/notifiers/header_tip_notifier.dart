// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// header_tip_notifier.dart

part of '../mill.dart';

class HeaderTipNotifier with ChangeNotifier {
  HeaderTipNotifier();

  String _message = "";
  bool showSnackBar = false;

  String get message => _message;

  void showTip(String tip, {bool snackBar = true}) {
    logger.i("[tip] $tip");
    showSnackBar = DB().generalSettings.screenReaderSupport && snackBar;
    _message = tip;
    Future<void>.delayed(Duration.zero, () {
      notifyListeners();
    });
  }
}
