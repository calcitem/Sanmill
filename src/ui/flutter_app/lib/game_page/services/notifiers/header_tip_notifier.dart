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
    final String normalizedTip = _normalizeHeaderTipPunctuation(tip);
    logger.i("[tip] $normalizedTip");
    showSnackBar = DB().generalSettings.screenReaderSupport && snackBar;
    _message = normalizedTip;
    _kind = kind;
    Future<void>.delayed(Duration.zero, () {
      notifyListeners();
    });
  }

  String _normalizeHeaderTipPunctuation(String tip) {
    return tip
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2022', '-')
        .replaceAll('\u2026', '...')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
