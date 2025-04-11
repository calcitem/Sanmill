// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// locale_adapter.dart

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
