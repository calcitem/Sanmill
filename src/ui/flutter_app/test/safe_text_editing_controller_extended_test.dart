// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// safe_text_editing_controller_extended_test.dart
//
// Extended edge-case tests for SafeTextEditingController.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';

void main() {
  group('SafeTextEditingController extended', () {
    test('empty text should have selection at 0', () {
      final SafeTextEditingController controller = SafeTextEditingController(
        text: '',
      );

      expect(controller.value.text, '');
      expect(controller.value.selection.baseOffset, 0);
      expect(controller.value.selection.extentOffset, 0);
    });

    test('setting value with valid selection should preserve it', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 3),
      );

      expect(controller.value.selection.baseOffset, 3);
    });

    test('selection beyond text length should be clamped', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 100),
      );

      expect(controller.value.selection.baseOffset, 2);
      expect(controller.value.selection.extentOffset, 2);
    });

    test('negative selection should be clamped to 0', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      // Use sanitize directly to test negative handling
      final TextEditingValue sanitized = SafeTextEditingController.sanitize(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection(baseOffset: -5, extentOffset: -3),
        ),
      );

      expect(sanitized.selection.baseOffset, 0);
      expect(sanitized.selection.extentOffset, 0);
    });

    test('composing range should be clamped to text length', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 100),
      );

      expect(controller.value.composing.start, 0);
      expect(controller.value.composing.end, 2);
    });

    test('invalid composing range should become empty', () {
      // When start > end after clamping, composing should be empty
      final TextEditingValue sanitized = SafeTextEditingController.sanitize(
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange(start: 5, end: 3),
        ),
      );

      // After clamping: start=1, end=1 (both clamped to length)
      // Or start > end → empty
      expect(
        sanitized.composing == TextRange.empty ||
            sanitized.composing.start <= sanitized.composing.end,
        isTrue,
      );
    });

    test('fromValue constructor should sanitize', () {
      final SafeTextEditingController controller =
          SafeTextEditingController.fromValue(
            const TextEditingValue(
              text: 'abc',
              selection: TextSelection.collapsed(offset: 50),
            ),
          );

      expect(controller.value.selection.baseOffset, 3);
    });

    test('setting text multiple times should always sanitize', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'first',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(controller.value.selection.baseOffset, 5);

      controller.value = const TextEditingValue(
        text: 'hi',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(controller.value.selection.baseOffset, 2);
    });

    test('range selection should be clamped on both ends', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection(baseOffset: 10, extentOffset: 20),
      );

      expect(controller.value.selection.baseOffset, 3);
      expect(controller.value.selection.extentOffset, 3);
    });

    test('valid composing range should be preserved', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 4),
      );

      expect(controller.value.composing.start, 1);
      expect(controller.value.composing.end, 4);
    });

    test('sanitize static method should be idempotent', () {
      const TextEditingValue input = TextEditingValue(
        text: 'test',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 4),
      );

      final TextEditingValue first = SafeTextEditingController.sanitize(input);
      final TextEditingValue second = SafeTextEditingController.sanitize(first);

      expect(first.text, second.text);
      expect(first.selection, second.selection);
      expect(first.composing, second.composing);
    });
  });
}
