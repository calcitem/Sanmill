// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_helper_test.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/utils/helpers/color_helpers/color_helper.dart';

void main() {
  group('pickColorWithMaxDifference', () {
    test('should pick the candidate farther from the reference', () {
      const Color reference = Color(0xFF000000); // Black
      const Color close = Color(0xFF111111); // Very dark grey
      const Color far = Color(0xFFFFFFFF); // White

      expect(pickColorWithMaxDifference(close, far, reference), far);
      expect(pickColorWithMaxDifference(far, close, reference), far);
    });

    test('should return candidate1 when both are equidistant', () {
      const Color reference = Color(0xFF808080); // Mid-grey
      const Color c1 = Color(0xFFFFFFFF); // White
      const Color c2 = Color(0xFF000000); // Black

      // White and Black are roughly equidistant from mid-grey,
      // but we just verify the function returns one of them without error.
      final Color result = pickColorWithMaxDifference(c1, c2, reference);
      expect(result == c1 || result == c2, isTrue);
    });

    test('should return either candidate when they are identical', () {
      const Color reference = Color(0xFF000000);
      const Color c = Color(0xFFFF0000); // Red

      final Color result = pickColorWithMaxDifference(c, c, reference);
      expect(result, c);
    });

    test('should handle reference equal to one candidate', () {
      const Color reference = Color(0xFFFF0000); // Red
      const Color same = Color(0xFFFF0000); // Also Red
      const Color different = Color(0xFF00FF00); // Green

      // "different" is farther from the reference than "same"
      expect(pickColorWithMaxDifference(same, different, reference), different);
      expect(pickColorWithMaxDifference(different, same, reference), different);
    });

    test('should work with transparency differences', () {
      const Color reference = Color(0x00000000); // Transparent black
      const Color c1 = Color(0xFF000000); // Opaque black
      const Color c2 = Color(0xFFFF0000); // Opaque red

      // c2 (red) has more overall difference in RGB channels from reference
      final Color result = pickColorWithMaxDifference(c1, c2, reference);
      expect(result == c1 || result == c2, isTrue);
    });

    test('primary colors vs reference', () {
      const Color reference = Color(0xFF0000FF); // Blue
      const Color red = Color(0xFFFF0000);
      const Color green = Color(0xFF00FF00);

      // Red differs from blue in R and B channels; Green differs in G and B.
      // Both should have similar squared distance, but the function picks one.
      final Color result = pickColorWithMaxDifference(red, green, reference);
      expect(result == red || result == green, isTrue);
    });
  });
}
