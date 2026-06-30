// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  test('provides framework localizations for every Sanmill locale', () async {
    for (final Locale locale in S.supportedLocales) {
      final WidgetsLocalizations widgetsLocalizations =
          await _loadFirstSupportedLocalization<WidgetsLocalizations>(locale);
      final MaterialLocalizations materialLocalizations =
          await _loadFirstSupportedLocalization<MaterialLocalizations>(locale);
      final CupertinoLocalizations cupertinoLocalizations =
          await _loadFirstSupportedLocalization<CupertinoLocalizations>(locale);

      expect(widgetsLocalizations.textDirection, isA<TextDirection>());
      expect(materialLocalizations.okButtonLabel, isNotEmpty);
      expect(cupertinoLocalizations.alertDialogLabel, isNotEmpty);
    }
  });

  test('falls back for Tibetan WidgetsLocalizations', () async {
    const Locale tibetan = Locale('bo');

    expect(GlobalWidgetsLocalizations.delegate.isSupported(tibetan), isFalse);
    expect(S.supportedLocales, contains(tibetan));

    final WidgetsLocalizations widgetsLocalizations =
        await _loadFirstSupportedLocalization<WidgetsLocalizations>(tibetan);

    expect(widgetsLocalizations, isA<DefaultWidgetsLocalizations>());
  });
}

Future<T> _loadFirstSupportedLocalization<T>(Locale locale) {
  final LocalizationsDelegate<T> delegate = sanmillLocalizationsDelegates
      .whereType<LocalizationsDelegate<T>>()
      .firstWhere((LocalizationsDelegate<T> delegate) {
        return delegate.isSupported(locale);
      });

  return delegate.load(locale);
}
