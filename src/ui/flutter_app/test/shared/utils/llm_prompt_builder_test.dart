// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// llm_prompt_builder_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/llm/llm_assisted_development_prompt_builder.dart';

void main() {
  // ---------------------------------------------------------------------------
  // looksLikeSanmillLog
  // ---------------------------------------------------------------------------
  group('looksLikeSanmillLog', () {
    test('should return true for text containing package:sanmill', () {
      expect(
        looksLikeSanmillLog('Error at package:sanmill/main.dart:42'),
        isTrue,
      );
    });

    test('should return true for text containing info score', () {
      expect(
        looksLikeSanmillLog('info score cp 100 depth 10 nodes 5000'),
        isTrue,
      );
    });

    test('should be case-insensitive', () {
      expect(
        looksLikeSanmillLog('ERROR AT PACKAGE:SANMILL/MAIN.DART'),
        isTrue,
      );
      expect(
        looksLikeSanmillLog('INFO SCORE cp 100'),
        isTrue,
      );
    });

    test('should return false for empty string', () {
      expect(looksLikeSanmillLog(''), isFalse);
    });

    test('should return false for whitespace-only string', () {
      expect(looksLikeSanmillLog('   \n\t  '), isFalse);
    });

    test('should return false for unrelated text', () {
      expect(looksLikeSanmillLog('Hello world'), isFalse);
      expect(looksLikeSanmillLog('Just some random text'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // extractSanmillLog
  // ---------------------------------------------------------------------------
  group('extractSanmillLog', () {
    test('should return trimmed log for valid Sanmill logs', () {
      const String log = '  Error at package:sanmill/main.dart:42  ';
      expect(
        extractSanmillLog(log),
        'Error at package:sanmill/main.dart:42',
      );
    });

    test('should return null for empty string', () {
      expect(extractSanmillLog(''), isNull);
    });

    test('should return null for whitespace-only string', () {
      expect(extractSanmillLog('   '), isNull);
    });

    test('should return null for non-Sanmill text', () {
      expect(extractSanmillLog('Hello world'), isNull);
    });

    test('should return trimmed text for info score logs', () {
      const String log = '  info score cp 50 depth 8  ';
      expect(
        extractSanmillLog(log),
        'info score cp 50 depth 8',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // buildLlmAssistedDevelopmentPrompt
  // ---------------------------------------------------------------------------
  group('buildLlmAssistedDevelopmentPrompt', () {
    test('should include the task text', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Fix the crash on startup',
        languageName: 'English',
      );

      expect(prompt, contains('Fix the crash on startup'));
    });

    test('should include the language name in footer', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Add a feature',
        languageName: '中文',
      );

      expect(prompt, contains('中文'));
    });

    test('should include the header with expert role', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Test task',
        languageName: 'English',
      );

      expect(prompt, contains('expert'));
      expect(prompt, contains('Mill board game'));
      expect(prompt, contains('Flutter'));
    });

    test('should include footer instructions', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Test task',
        languageName: 'English',
      );

      expect(prompt, contains('ARB files'));
      expect(prompt, contains('code comments must be in English'));
      expect(prompt, contains('Co-authored-by'));
    });

    test('should include log section when log is provided', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Debug this issue',
        languageName: 'English',
        log: 'Error at package:sanmill/main.dart:42\nStack trace...',
      );

      expect(prompt, contains('relevant logs'));
      expect(prompt, contains('```'));
      expect(prompt, contains('Error at package:sanmill/main.dart:42'));
    });

    test('should not include log section when log is null', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Add feature',
        languageName: 'English',
      );

      expect(prompt, isNot(contains('relevant logs')));
      expect(prompt, isNot(contains('```')));
    });

    test('should not include log section when log is empty', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Add feature',
        languageName: 'English',
        log: '',
      );

      expect(prompt, isNot(contains('relevant logs')));
    });

    test('should not include log section when log is whitespace-only', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: 'Add feature',
        languageName: 'English',
        log: '   \n  ',
      );

      expect(prompt, isNot(contains('relevant logs')));
    });

    test('should trim the task text', () {
      final String prompt = buildLlmAssistedDevelopmentPrompt(
        task: '  Trimmed task  ',
        languageName: 'English',
      );

      expect(prompt, contains('Trimmed task'));
    });

    test('should handle various language names', () {
      for (final String lang in <String>[
        'English',
        '中文',
        'Deutsch',
        '日本語',
        '한국어',
      ]) {
        final String prompt = buildLlmAssistedDevelopmentPrompt(
          task: 'Test',
          languageName: lang,
        );
        expect(
          prompt,
          contains(lang),
          reason: 'Prompt should contain language name: $lang',
        );
      }
    });
  });
}
