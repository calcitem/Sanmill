// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// legacy_color_adapter.dart

part of 'adapters.dart';

/// Legacy Color Adapter (typeId = 6)
///
/// Provides backward compatibility for color values stored by older
/// releases (e.g., v6.8.0) which used a custom Color TypeAdapter with
/// typeId=6. New writes should use hive_ce_flutter's built-in
/// ColorAdapter (typeId=200). To avoid interfering with the default
/// writer selection for Color, this adapter is registered as
/// `TypeAdapter<dynamic>` and is only meant for reading legacy data.
class LegacyColorAdapter extends TypeAdapter<dynamic> {
  @override
  final int typeId = 6;

  @override
  Color read(BinaryReader reader) {
    final int value = reader.readInt();
    return Color(value);
  }

  @override
  void write(BinaryWriter writer, dynamic obj) {
    // Not used for new writes. If invoked unexpectedly, surface error
    // instead of writing a fallback value to avoid color corruption.
    assert(obj is Color, 'LegacyColorAdapter expects a Color instance');
    if (obj is! Color) {
      throw StateError('LegacyColorAdapter can only write Color values');
    }

    final int alpha = Color.getAlphaFromOpacity(obj.a) & 0xFF;
    final int red = (obj.r * 255).round() & 0xFF;
    final int green = (obj.g * 255).round() & 0xFF;
    final int blue = (obj.b * 255).round() & 0xFF;

    final int combinedValue = (alpha << 24) | (red << 16) | (green << 8) | blue;
    writer.writeInt(combinedValue);
  }
}
