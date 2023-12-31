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

part of 'adapters.dart';

/// Locale Adapter
///
/// This adapter provides helper functions to be used with [JsonSerializable]
/// and is a general [TypeAdapter] to be used with Hive [Box]es
class LocaleAdapter extends TypeAdapter<Locale?> {
  @override
  final int typeId = 7;

  @override
  Locale read(BinaryReader reader) {
    final String value = reader.readString();
    return Locale(value);
  }

  @override
  void write(BinaryWriter writer, Locale? obj) {
    if (obj != null) {
      writer.writeString(obj.languageCode);
    }
  }

  static String? localeToJson(Locale? locale) => locale?.languageCode;
  static Locale? localeFromJson(String? value) {
    if (value != null && value != "Default") {
      return Locale(value);
    }
    return null;
  }
}
