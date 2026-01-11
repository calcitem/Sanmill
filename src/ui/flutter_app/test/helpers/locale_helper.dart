// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// locale_helper.dart

import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';

Widget makeTestableWidget(Widget child, [Locale locale = const Locale("en")]) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
}
