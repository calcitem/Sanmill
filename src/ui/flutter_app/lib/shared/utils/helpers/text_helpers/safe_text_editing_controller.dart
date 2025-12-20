// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// safe_text_editing_controller.dart

import 'package:flutter/widgets.dart';

/// A [TextEditingController] that guarantees its [value] never contains
/// out-of-range selection/composing offsets.
///
/// This prevents Android from throwing `IndexOutOfBoundsException` when Flutter
/// sends the editing state to the platform (e.g. `invalid selection start`).
class SafeTextEditingController extends TextEditingController {
  SafeTextEditingController({super.text}) {
    // The base constructor initializes with an invalid selection (-1).
    // Normalize it immediately so the first focused frame stays safe.
    value = sanitize(value);
  }

  SafeTextEditingController.fromValue(TextEditingValue value)
    : super.fromValue(sanitize(value));

  @override
  set value(TextEditingValue newValue) {
    super.value = sanitize(newValue);
  }

  static TextEditingValue sanitize(TextEditingValue value) {
    final String text = value.text;
    final int length = text.length;

    // ---- selection ----
    int base = value.selection.baseOffset;
    int extent = value.selection.extentOffset;

    // Common initial state is (-1, -1). Android does not accept it, so we
    // normalize to the end-of-text to keep UX reasonable and avoid crashes.
    if (base == -1 && extent == -1) {
      base = length;
      extent = length;
    }

    base = base.clamp(0, length);
    extent = extent.clamp(0, length);

    final TextSelection selection = TextSelection(
      baseOffset: base,
      extentOffset: extent,
      affinity: value.selection.affinity,
      isDirectional: value.selection.isDirectional,
    );

    // ---- composing ----
    TextRange composing = value.composing;
    if (composing.isValid) {
      final int start = composing.start.clamp(0, length);
      final int end = composing.end.clamp(0, length);
      composing = start <= end
          ? TextRange(start: start, end: end)
          : TextRange.empty;
    } else {
      composing = TextRange.empty;
    }

    return TextEditingValue(
      text: text,
      selection: selection,
      composing: composing,
    );
  }
}
