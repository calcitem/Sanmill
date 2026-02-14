// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_adapter_test.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/database/adapters/adapters.dart';

void main() {
  group('ColorAdapter', () {
    group('colorToJson', () {
      test('should encode opaque white as 0xFFFFFFFF', () {
        const Color white = Color(0xFFFFFFFF);
        final int json = ColorAdapter.colorToJson(white);
        // 0xFFFFFFFF as signed int
        expect(json, 0xFFFFFFFF);
      });

      test('should encode opaque black as 0xFF000000', () {
        const Color black = Color(0xFF000000);
        final int json = ColorAdapter.colorToJson(black);
        expect(json, 0xFF000000);
      });

      test('should encode opaque red as 0xFFFF0000', () {
        const Color red = Color(0xFFFF0000);
        final int json = ColorAdapter.colorToJson(red);
        expect(json, 0xFFFF0000);
      });

      test('should encode fully transparent black as 0x00000000', () {
        const Color transparent = Color(0x00000000);
        final int json = ColorAdapter.colorToJson(transparent);
        expect(json, 0x00000000);
      });

      test('should encode semi-transparent color correctly', () {
        const Color semiTransparent = Color(0x80FF8000);
        final int json = ColorAdapter.colorToJson(semiTransparent);
        // Alpha ~128, R ~255, G ~128, B ~0
        // We check by round-tripping
        final Color restored = ColorAdapter.colorFromJson(json);
        expect(restored.a, closeTo(semiTransparent.a, 0.02));
        expect(restored.r, closeTo(semiTransparent.r, 0.02));
        expect(restored.g, closeTo(semiTransparent.g, 0.02));
        expect(restored.b, closeTo(semiTransparent.b, 0.02));
      });
    });

    group('colorFromJson', () {
      test('should decode 0xFFFFFFFF as white', () {
        final Color color = ColorAdapter.colorFromJson(0xFFFFFFFF);
        expect(color, const Color(0xFFFFFFFF));
      });

      test('should decode 0xFF000000 as black', () {
        final Color color = ColorAdapter.colorFromJson(0xFF000000);
        expect(color, const Color(0xFF000000));
      });

      test('should decode 0xFFFF0000 as red', () {
        final Color color = ColorAdapter.colorFromJson(0xFFFF0000);
        expect(color, const Color(0xFFFF0000));
      });

      test('should decode 0x00000000 as fully transparent', () {
        final Color color = ColorAdapter.colorFromJson(0x00000000);
        expect(color, const Color(0x00000000));
      });
    });

    group('round-trip', () {
      test('should preserve opaque colors', () {
        const List<Color> colors = <Color>[
          Color(0xFFFFFFFF), // White
          Color(0xFF000000), // Black
          Color(0xFFFF0000), // Red
          Color(0xFF00FF00), // Green
          Color(0xFF0000FF), // Blue
          Color(0xFFDEB887), // BurlyWood (UIColors)
          Color(0xFFA15B48), // BurntSienna (UIColors)
        ];

        for (final Color c in colors) {
          final int json = ColorAdapter.colorToJson(c);
          final Color restored = ColorAdapter.colorFromJson(json);
          expect(
            restored,
            c,
            reason: 'Round-trip for $c',
          );
        }
      });
    });
  });
}
