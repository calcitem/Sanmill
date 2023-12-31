// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

// ignore: avoid_classes_with_only_static_members
class TextSizeHelper {
  // Get the size of the text through textPainter
  static Size getBoundingTextSize(
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
}
