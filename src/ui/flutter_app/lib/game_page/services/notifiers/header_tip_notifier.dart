// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// header_tip_notifier.dart

part of '../mill.dart';

enum HeaderTipKind { general, openingInfo }

class HeaderTipNotifier with ChangeNotifier {
  HeaderTipNotifier();

  String _message = "";
  HeaderTipKind _kind = HeaderTipKind.general;
  bool showSnackBar = false;

  String get message => _message;

  HeaderTipKind get kind => _kind;

  void showTip(
    String tip, {
    bool snackBar = true,
    HeaderTipKind kind = HeaderTipKind.general,
  }) {
    logger.i("[tip] $tip");
    showSnackBar = DB().generalSettings.screenReaderSupport && snackBar;
    _message = tip;
    _kind = kind;
    Future<void>.delayed(Duration.zero, () {
      notifyListeners();
    });
  }
}
