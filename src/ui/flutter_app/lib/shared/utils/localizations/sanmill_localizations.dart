// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// sanmill_localizations.dart

import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../../generated/intl/l10n.dart';

const List<LocalizationsDelegate<dynamic>> sanmillLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      _FallbackWidgetsLocalizationsDelegate(),
      _FallbackMaterialLocalizationsDelegate(),
      _FallbackCupertinoLocalizationsDelegate(),
      ...S.localizationsDelegates,
    ];

class _FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    final LocalizationsDelegate<WidgetsLocalizations> delegate =
        GlobalWidgetsLocalizations.delegate.isSupported(locale)
        ? GlobalWidgetsLocalizations.delegate
        : DefaultWidgetsLocalizations.delegate;
    return delegate.load(locale);
  }

  @override
  bool shouldReload(_FallbackWidgetsLocalizationsDelegate old) => false;
}

class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final LocalizationsDelegate<MaterialLocalizations> delegate =
        GlobalMaterialLocalizations.delegate.isSupported(locale)
        ? GlobalMaterialLocalizations.delegate
        : DefaultMaterialLocalizations.delegate;
    return delegate.load(locale);
  }

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final LocalizationsDelegate<CupertinoLocalizations> delegate =
        GlobalCupertinoLocalizations.delegate.isSupported(locale)
        ? GlobalCupertinoLocalizations.delegate
        : DefaultCupertinoLocalizations.delegate;
    return delegate.load(locale);
  }

  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}
