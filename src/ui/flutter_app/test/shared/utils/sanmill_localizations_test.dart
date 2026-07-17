// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  test('separates computer-play and generative AI terminology', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.humanVsAi, 'Human vs computer');
    expect(english.aiVsAi, 'Computer vs computer');
    expect(english.humanAiRobotLevel(7), 'Computer level 7');
    expect(english.advancedAiSearch, 'Advanced engine search');
    expect(english.aiChatTitle, 'AI Assistant');
    expect(english.aiAnalysisTitle, 'AI Game Analysis');

    expect(chinese.humanVsAi, '人机对弈');
    expect(chinese.aiVsAi, '电脑自弈');
    expect(chinese.humanAiRobotLevel(7), '电脑等级 7');
    expect(chinese.advancedAiSearch, '高级引擎搜索');
    expect(chinese.aiChatTitle, 'AI 助手');
    expect(chinese.aiAnalysisTitle, 'AI 棋局分析');
  });

  test('localizes screenshot save failures in English and Chinese', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.failedToSaveImageToGallery, 'Could not save the image.');
    expect(
      english.imageSavingNotSupported,
      'Saving images is not supported on this platform.',
    );
    expect(chinese.failedToSaveImageToGallery, '无法保存图片。');
    expect(chinese.imageSavingNotSupported, '当前平台不支持保存图片。');
  });

  test('localizes annotation semantics in English and Chinese', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.annotationToolName('line'), 'Line tool');
    expect(
      english.selectAnnotationColor(english.annotationColorName('red')),
      'Select red',
    );
    expect(chinese.annotationToolName('line'), '直线工具');
    expect(
      chinese.selectAnnotationColor(chinese.annotationColorName('red')),
      '选择红色',
    );
  });

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

  test('uses Flutter Tibetan WidgetsLocalizations', () async {
    const Locale tibetan = Locale('bo');

    expect(GlobalWidgetsLocalizations.delegate.isSupported(tibetan), isTrue);
    expect(S.supportedLocales, contains(tibetan));

    final WidgetsLocalizations widgetsLocalizations =
        await _loadFirstSupportedLocalization<WidgetsLocalizations>(tibetan);

    expect(widgetsLocalizations, isNot(isA<DefaultWidgetsLocalizations>()));
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
