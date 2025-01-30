// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// text_size_helper.dart

import 'package:flutter/material.dart';

// Get the size of the text through TextPainter
Size getBoundingTextSize(
    BuildContext context, String inputText, TextStyle inputTextStyle,
    {int maxLines = 2 ^ 31, double maxWidth = double.infinity}) {
  if (inputText.isEmpty) {
    return Size.zero;
  }
  final TextPainter textSizePainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: inputText, style: inputTextStyle),
      textScaler: MediaQuery.of(context).textScaler,
      locale: Localizations.localeOf(context),
      maxLines: maxLines)
    ..layout(maxWidth: maxWidth);
  return textSizePainter.size;
}
