// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_adapter.dart

part of 'adapters.dart';

/// Color Adapter
///
/// Provides helper functions for Color serialization to be used with
/// [JsonSerializable]. Note: Hive serialization is handled by the built-in
/// ColorAdapter from hive_ce_flutter package (typeId 200).
class ColorAdapter {
  const ColorAdapter._();

  static int colorToJson(Color color) {
    final int alpha = Color.getAlphaFromOpacity(color.a) & 0xFF;
    final int red = (color.r * 255).round() & 0xFF;
    final int green = (color.g * 255).round() & 0xFF;
    final int blue = (color.b * 255).round() & 0xFF;

    return (alpha << 24) | (red << 16) | (green << 8) | blue;
  }

  static Color colorFromJson(int value) {
    return Color(value);
  }
}
