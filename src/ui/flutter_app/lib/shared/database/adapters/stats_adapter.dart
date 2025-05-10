// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// stat_adapter.dart

part of 'adapters.dart';

/// Hive [TypeAdapter] for [PlayerStats].
///
/// We serialise the object into a JSON String to keep the implementation
/// maintainable.  Any future field that is added to the model will be picked up
/// automatically by the [toJson] / [fromJson] methods.
class PlayerStatsAdapter extends TypeAdapter<PlayerStats> {
  @override
  final int typeId =
      kPlayerStatsTypeId; // Must match typeId used in PlayerStats

  @override
  PlayerStats read(BinaryReader reader) {
    final String jsonStr = reader.readString();
    final Map<String, dynamic> map =
        convert.jsonDecode(jsonStr) as Map<String, dynamic>;
    return PlayerStats.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, PlayerStats obj) {
    writer.writeString(convert.jsonEncode(obj.toJson()));
  }
}

/// Hive [TypeAdapter] for [StatsSettings].  Serialisation strategy is identical
/// to [PlayerStatsAdapter].
class StatsSettingsAdapter extends TypeAdapter<StatsSettings> {
  @override
  final int typeId =
      kStatsSettingsTypeId; // Must match typeId used in StatsSettings

  @override
  StatsSettings read(BinaryReader reader) {
    final String jsonStr = reader.readString();
    final Map<String, dynamic> map =
        convert.jsonDecode(jsonStr) as Map<String, dynamic>;
    return StatsSettings.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, StatsSettings obj) {
    writer.writeString(convert.jsonEncode(obj.toJson()));
  }
}
