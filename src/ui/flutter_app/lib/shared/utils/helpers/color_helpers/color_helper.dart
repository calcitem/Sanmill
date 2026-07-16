// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_helper.dart

import 'dart:ui';

/// The WCAG minimum contrast ratio for normal-sized text.
const double normalTextMinimumContrastRatio = 4.5;

/// Calculates the WCAG contrast ratio between [foreground] and [background].
///
/// A translucent foreground is composited over the opaque background before
/// its relative luminance is calculated.
double colorContrastRatio(Color foreground, Color background) {
  assert(
    background.a == 1,
    'Contrast calculations require an opaque background.',
  );
  final Color effectiveForeground = foreground.a == 1
      ? foreground
      : Color.alphaBlend(foreground, background);
  final double foregroundLuminance = effectiveForeground.computeLuminance();
  final double backgroundLuminance = background.computeLuminance();
  final double lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final double darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Preserves [preferred] when it is readable on [background].
///
/// Otherwise, this returns whichever of opaque black or white has the higher
/// WCAG contrast ratio. This keeps user-selectable colour themes legible even
/// when their preferred text colour is translucent or too close to the
/// background colour.
Color readableForegroundColor({
  required Color preferred,
  required Color background,
  double minimumContrastRatio = normalTextMinimumContrastRatio,
}) {
  assert(
    minimumContrastRatio >= 1 && minimumContrastRatio <= 21,
    'A contrast ratio must be between 1 and 21.',
  );
  if (colorContrastRatio(preferred, background) >= minimumContrastRatio) {
    return preferred;
  }

  const Color black = Color(0xFF000000);
  const Color white = Color(0xFFFFFFFF);
  return colorContrastRatio(black, background) >=
          colorContrastRatio(white, background)
      ? black
      : white;
}

/// A helper function to compare two candidate colors against a reference color
/// and pick the one with the larger RGB squared-distance difference.
Color pickColorWithMaxDifference(
  Color candidate1,
  Color candidate2,
  Color reference,
) {
  double colorDiff(Color c1, Color c2) {
    final double dr = c1.r - c2.r;
    final double dg = c1.g - c2.g;
    final double db = c1.b - c2.b;
    return dr * dr + dg * dg + db * db;
  }

  return (colorDiff(candidate1, reference) > colorDiff(candidate2, reference))
      ? candidate1
      : candidate2;
}
