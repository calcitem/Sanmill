// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// prompt_defaults_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/config/prompt_defaults.dart';

void main() {
  group('PromptDefaults', () {
    group('llmPromptHeader', () {
      test('should not be empty', () {
        expect(PromptDefaults.llmPromptHeader, isNotEmpty);
      });

      test('should contain role description', () {
        expect(PromptDefaults.llmPromptHeader, contains('Nine Men\'s Morris'));
      });

      test('should contain board reference information', () {
        expect(PromptDefaults.llmPromptHeader, contains('Board Reference'));
      });

      test('should reference key strategic concepts', () {
        expect(PromptDefaults.llmPromptHeader, contains('Double Mill'));
        expect(PromptDefaults.llmPromptHeader, contains('Running Mill'));
      });

      test('should list all 24 board positions', () {
        // Check sample positions from each ring
        expect(PromptDefaults.llmPromptHeader, contains('a7'));
        expect(PromptDefaults.llmPromptHeader, contains('d5'));
        expect(PromptDefaults.llmPromptHeader, contains('f4'));
        expect(PromptDefaults.llmPromptHeader, contains('g1'));
      });

      test('should describe mill combinations', () {
        expect(PromptDefaults.llmPromptHeader, contains('Mill Combinations'));
        expect(PromptDefaults.llmPromptHeader, contains('Inner Ring Mills'));
        expect(PromptDefaults.llmPromptHeader, contains('Middle Ring Mills'));
        expect(PromptDefaults.llmPromptHeader, contains('Outer Ring Mills'));
      });

      test('should contain game phases', () {
        expect(PromptDefaults.llmPromptHeader, contains('Phase 1'));
        expect(PromptDefaults.llmPromptHeader, contains('Phase 2'));
        expect(PromptDefaults.llmPromptHeader, contains('Phase 3'));
        expect(PromptDefaults.llmPromptHeader, contains('Placing'));
        expect(PromptDefaults.llmPromptHeader, contains('Moving'));
        expect(PromptDefaults.llmPromptHeader, contains('Flying'));
      });
    });

    group('llmPromptFooter', () {
      test('should not be empty', () {
        expect(PromptDefaults.llmPromptFooter, isNotEmpty);
      });

      test('should contain output requirements', () {
        expect(PromptDefaults.llmPromptFooter, contains('Output Requirements'));
      });

      test('should contain format instructions', () {
        expect(PromptDefaults.llmPromptFooter, contains('Format'));
      });

      test('should mention annotation markers', () {
        // The footer describes using !, ?, etc.
        expect(PromptDefaults.llmPromptFooter, contains('!'));
        expect(PromptDefaults.llmPromptFooter, contains('?'));
      });
    });
  });
}
