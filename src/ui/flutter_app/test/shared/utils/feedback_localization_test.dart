// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// feedback_localization_test.dart

import 'dart:ui';

import 'package:feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/localizations/feedback_localization.dart';

void main() {
  // ---------------------------------------------------------------------------
  // CustomFeedbackLocalizations
  // ---------------------------------------------------------------------------
  group('CustomFeedbackLocalizations', () {
    test('should return values from the provided map', () {
      const CustomFeedbackLocalizations loc =
          CustomFeedbackLocalizations(<String, String>{
            'submitButtonText': 'Go',
            'feedbackDescriptionText': 'Describe',
            'draw': 'Paint',
            'navigate': 'Move',
          });

      expect(loc.submitButtonText, 'Go');
      expect(loc.feedbackDescriptionText, 'Describe');
      expect(loc.draw, 'Paint');
      expect(loc.navigate, 'Move');
    });
  });

  // ---------------------------------------------------------------------------
  // CustomFeedbackLocalizationsDelegate
  // ---------------------------------------------------------------------------
  group('CustomFeedbackLocalizationsDelegate', () {
    const CustomFeedbackLocalizationsDelegate delegate =
        CustomFeedbackLocalizationsDelegate.delegate;

    test('isSupported should return true for English', () {
      expect(delegate.isSupported(const Locale('en')), isTrue);
    });

    test('isSupported should return true for Chinese', () {
      expect(delegate.isSupported(const Locale('zh')), isTrue);
    });

    test('isSupported should return true for German', () {
      expect(delegate.isSupported(const Locale('de')), isTrue);
    });

    test(
      'isSupported should return true for unsupported locale (fallback)',
      () {
        // Even unsupported locales return true (with fallback)
        expect(delegate.isSupported(const Locale('xx')), isTrue);
      },
    );

    test('shouldReload should return false', () {
      expect(
        delegate.shouldReload(CustomFeedbackLocalizationsDelegate.delegate),
        isFalse,
      );
    });

    test('toString should contain delegate info', () {
      expect(delegate.toString(), contains('DefaultFeedbackLocalizations'));
    });

    test(
      'load should return English localizations for English locale',
      () async {
        final FeedbackLocalizations loc = await delegate.load(
          const Locale('en'),
        );

        expect(loc.submitButtonText, 'Submit');
        expect(loc.feedbackDescriptionText, "What's wrong?");
        expect(loc.draw, 'Draw');
        expect(loc.navigate, 'Navigate');
      },
    );

    test(
      'load should return Chinese localizations for Chinese locale',
      () async {
        final FeedbackLocalizations loc = await delegate.load(
          const Locale('zh'),
        );

        expect(loc.submitButtonText, '提交');
        expect(loc.draw, '涂鸦');
        expect(loc.navigate, '导航');
      },
    );

    test('load should return German localizations for German locale', () async {
      final FeedbackLocalizations loc = await delegate.load(const Locale('de'));

      expect(loc.submitButtonText, 'Senden');
      expect(loc.draw, 'Zeichnen');
    });

    test('load should fall back to English for unknown locale', () async {
      final FeedbackLocalizations loc = await delegate.load(const Locale('xx'));

      expect(loc.submitButtonText, 'Submit');
      expect(loc.draw, 'Draw');
    });

    test('should support major world languages', () async {
      const List<String> majorLanguages = <String>[
        'en',
        'zh',
        'de',
        'fr',
        'es',
        'pt',
        'ru',
        'ja',
        'ko',
        'ar',
        'hi',
        'tr',
        'it',
        'pl',
        'nl',
        'sv',
        'th',
        'vi',
      ];

      for (final String lang in majorLanguages) {
        final FeedbackLocalizations loc = await delegate.load(Locale(lang));
        expect(
          loc.submitButtonText,
          isNotEmpty,
          reason: 'submitButtonText for $lang should not be empty',
        );
        expect(
          loc.feedbackDescriptionText,
          isNotEmpty,
          reason: 'feedbackDescriptionText for $lang should not be empty',
        );
        expect(
          loc.draw,
          isNotEmpty,
          reason: 'draw for $lang should not be empty',
        );
        expect(
          loc.navigate,
          isNotEmpty,
          reason: 'navigate for $lang should not be empty',
        );
      }
    });

    test('delegate static instance should be non-null', () {
      expect(CustomFeedbackLocalizationsDelegate.delegate, isNotNull);
    });
  });
}
