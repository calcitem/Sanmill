// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

part of 'adapters.dart';

/// Color Adapter
///
/// This adapter provides helper functions to be used with [JsonSerializable]
/// and is a general [TypeAdapter] to be used with Hive [Box]es
class ColorAdapter extends TypeAdapter<Color> {
  @override
  final int typeId = 6;

  @override
  Color read(BinaryReader reader) {
    final int value = reader.readInt();
    return Color(value);
  }

  @override
  void write(BinaryWriter writer, Color obj) {
    final int alpha = Color.getAlphaFromOpacity(obj.a) & 0xFF;
    final int red = (obj.r * 255).round() & 0xFF;
    final int green = (obj.g * 255).round() & 0xFF;
    final int blue = (obj.b * 255).round() & 0xFF;

    final int combinedValue = (alpha << 24) | (red << 16) | (green << 8) | blue;

    writer.writeInt(combinedValue);
  }

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
