import 'package:flutter/material.dart';

class TextSizeHelper {
  // Get the size of the text through textPainter
  static Size boundingTextSize(
      BuildContext context, String text, TextStyle style,
      {int maxLines = 2 ^ 31, double maxWidth = double.infinity}) {
    if (text.isEmpty) {
      return Size.zero;
    }
    final TextPainter textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(text: text, style: style),
        textScaleFactor: MediaQuery.of(context).textScaleFactor,
        locale: Localizations.localeOf(context),
        maxLines: maxLines)
      ..layout(maxWidth: maxWidth);
    return textPainter.size;
  }
}
