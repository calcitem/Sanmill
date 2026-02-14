// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// string_helper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/string_helpers/string_helper.dart';

void main() {
  // ---------------------------------------------------------------------------
  // removeBracketedContent
  // ---------------------------------------------------------------------------
  group('removeBracketedContent', () {
    test('should remove content inside parentheses', () {
      expect(removeBracketedContent('hello (world)'), 'hello ');
    });

    test('should remove content inside square brackets', () {
      expect(removeBracketedContent('hello [world]'), 'hello ');
    });

    test('should remove content inside curly braces', () {
      expect(removeBracketedContent('hello {world}'), 'hello ');
    });

    test('should remove content from all bracket types simultaneously', () {
      expect(
        removeBracketedContent('a(b)[c]{d}e'),
        'ae',
      );
    });

    test('should handle multiple pairs of the same bracket type', () {
      expect(
        removeBracketedContent('x(a)y(b)z'),
        'xyz',
      );
    });

    test('should return the same string when no brackets present', () {
      expect(removeBracketedContent('no brackets here'), 'no brackets here');
    });

    test('should handle empty string', () {
      expect(removeBracketedContent(''), '');
    });

    test('should handle empty bracket pairs', () {
      expect(removeBracketedContent('a()b[]c{}d'), 'abcd');
    });

    test('should handle string with only brackets', () {
      expect(removeBracketedContent('(hello)'), '');
    });
  });

  // ---------------------------------------------------------------------------
  // transformOutside
  // ---------------------------------------------------------------------------
  group('transformOutside', () {
    test('should lowercase the text', () {
      expect(
        transformOutside('HELLO', <String, String>{}),
        'hello',
      );
    });

    test('should apply replacements after lowercasing', () {
      expect(
        transformOutside('Hello World', <String, String>{'hello': 'hi'}),
        'hi world',
      );
    });

    test('should apply multiple replacements', () {
      expect(
        transformOutside(
          'ABC DEF',
          <String, String>{'abc': '123', 'def': '456'},
        ),
        '123 456',
      );
    });

    test('should handle empty string', () {
      expect(
        transformOutside('', <String, String>{'a': 'b'}),
        '',
      );
    });

    test('should handle empty replacements map', () {
      expect(
        transformOutside('Hello', <String, String>{}),
        'hello',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // processOutsideBrackets
  // ---------------------------------------------------------------------------
  group('processOutsideBrackets', () {
    test('should transform text outside brackets while preserving inside', () {
      expect(
        processOutsideBrackets(
          'Hello (World) Foo',
          <String, String>{'hello': 'hi', 'foo': 'bar'},
        ),
        'hi (World) bar',
      );
    });

    test('should preserve content inside square brackets', () {
      expect(
        processOutsideBrackets(
          'ABC [DEF] GHI',
          <String, String>{'abc': '123', 'ghi': '789'},
        ),
        '123 [DEF] 789',
      );
    });

    test('should preserve content inside curly braces', () {
      expect(
        processOutsideBrackets(
          'Hello {WORLD} Bye',
          <String, String>{'hello': 'hi', 'bye': 'ciao'},
        ),
        'hi {WORLD} ciao',
      );
    });

    test('should handle nested brackets', () {
      // Nested brackets: inner content should remain untouched
      expect(
        processOutsideBrackets(
          'A (B [C] D) E',
          <String, String>{'a': '1', 'e': '5'},
        ),
        '1 (B [C] D) 5',
      );
    });

    test('should handle string with no brackets', () {
      expect(
        processOutsideBrackets(
          'HELLO WORLD',
          <String, String>{'hello': 'hi'},
        ),
        'hi world',
      );
    });

    test('should handle empty string', () {
      expect(
        processOutsideBrackets('', <String, String>{'a': 'b'}),
        '',
      );
    });

    test('should handle text that is entirely bracketed', () {
      expect(
        processOutsideBrackets(
          '(HELLO WORLD)',
          <String, String>{'hello': 'hi'},
        ),
        '(HELLO WORLD)',
      );
    });

    test('should handle unclosed brackets gracefully', () {
      // Unclosed bracket: text after the opening bracket is treated as inside
      final String result = processOutsideBrackets(
        'A (B C',
        <String, String>{'a': '1'},
      );
      // "A " is outside, "(B C" is inside (unclosed)
      expect(result, '1 (B C');
    });

    test('should handle mismatched closing bracket as normal text', () {
      final String result = processOutsideBrackets(
        'A ) B',
        <String, String>{'a': '1'},
      );
      // ')' is treated as normal text outside brackets
      expect(result, contains('1'));
    });

    test('should handle multiple bracket types in sequence', () {
      expect(
        processOutsideBrackets(
          'A (B) C [D] E {F} G',
          <String, String>{'a': '1', 'c': '3', 'e': '5', 'g': '7'},
        ),
        '1 (B) 3 [D] 5 {F} 7',
      );
    });
  });
}
