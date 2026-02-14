// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// locale_adapter_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/database/adapters/adapters.dart';

void main() {
  group('LocaleAdapter', () {
    group('localeToJson', () {
      test('should return language code for non-null locale', () {
        expect(LocaleAdapter.localeToJson(const Locale('en')), 'en');
        expect(LocaleAdapter.localeToJson(const Locale('de')), 'de');
        expect(LocaleAdapter.localeToJson(const Locale('zh')), 'zh');
      });

      test('should return null for null locale', () {
        expect(LocaleAdapter.localeToJson(null), isNull);
      });
    });

    group('localeFromJson', () {
      test('should return Locale for valid language code', () {
        final Locale? locale = LocaleAdapter.localeFromJson('en');
        expect(locale, isNotNull);
        expect(locale!.languageCode, 'en');
      });

      test('should return Locale for various language codes', () {
        expect(LocaleAdapter.localeFromJson('de')?.languageCode, 'de');
        expect(LocaleAdapter.localeFromJson('zh')?.languageCode, 'zh');
        expect(LocaleAdapter.localeFromJson('ja')?.languageCode, 'ja');
      });

      test('should return null for "Default" string', () {
        expect(LocaleAdapter.localeFromJson('Default'), isNull);
      });

      test('should return null for null input', () {
        expect(LocaleAdapter.localeFromJson(null), isNull);
      });
    });

    group('round-trip', () {
      test('should preserve locale through toJson and fromJson', () {
        const Locale original = Locale('ko');
        final String? json = LocaleAdapter.localeToJson(original);
        final Locale? restored = LocaleAdapter.localeFromJson(json);

        expect(restored, isNotNull);
        expect(restored!.languageCode, 'ko');
      });

      test('should preserve null locale through round-trip', () {
        final String? json = LocaleAdapter.localeToJson(null);
        final Locale? restored = LocaleAdapter.localeFromJson(json);

        expect(restored, isNull);
      });
    });

    group('TypeAdapter', () {
      test('should have typeId 7', () {
        final LocaleAdapter adapter = LocaleAdapter();
        expect(adapter.typeId, 7);
      });
    });
  });
}
