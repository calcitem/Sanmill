// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// safe_text_editing_controller_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/text_helpers/safe_text_editing_controller.dart';

void main() {
  group('SafeTextEditingController', () {
    test('clamps selection to the end when selection is out of range', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(controller.value.text, 'abc');
      expect(controller.value.selection.baseOffset, 3);
      expect(controller.value.selection.extentOffset, 3);
    });

    test('normalizes the default (-1, -1) selection to end-of-text', () {
      final SafeTextEditingController controller = SafeTextEditingController(
        text: 'abc',
      );

      expect(controller.value.text, 'abc');
      expect(controller.value.selection.baseOffset, 3);
      expect(controller.value.selection.extentOffset, 3);
    });

    test('keeps composing within bounds', () {
      final SafeTextEditingController controller = SafeTextEditingController();

      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 10),
      );

      expect(controller.value.composing, const TextRange(start: 0, end: 3));
    });
  });
}
