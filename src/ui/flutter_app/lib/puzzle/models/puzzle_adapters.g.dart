// SPDX-License-Identifier: GPL-3.0-or-later
// Generated manually to provide Hive adapters for puzzle models.
// This file should be kept in sync with the model definitions in
// `puzzle_models.dart`.

part of 'puzzle_adapters.dart';

class PuzzleInfoAdapter extends TypeAdapter<PuzzleInfo> {
  @override
  final int typeId = puzzleInfoTypeId;

  @override
  PuzzleInfo read(BinaryReader reader) {
    final String jsonStr = reader.readString();
    final Map<String, dynamic> map =
        convert.jsonDecode(jsonStr) as Map<String, dynamic>;
    return PuzzleInfo.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, PuzzleInfo obj) {
    writer.writeString(convert.jsonEncode(obj.toJson()));
  }
}

class PuzzleProgressAdapter extends TypeAdapter<PuzzleProgress> {
  @override
  final int typeId = puzzleProgressTypeId;

  @override
  PuzzleProgress read(BinaryReader reader) {
    final String jsonStr = reader.readString();
    final Map<String, dynamic> map =
        convert.jsonDecode(jsonStr) as Map<String, dynamic>;
    return PuzzleProgress.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, PuzzleProgress obj) {
    writer.writeString(convert.jsonEncode(obj.toJson()));
  }
}

class PuzzleSettingsAdapter extends TypeAdapter<PuzzleSettings> {
  @override
  final int typeId = puzzleSettingsTypeId;

  @override
  PuzzleSettings read(BinaryReader reader) {
    final String jsonStr = reader.readString();
    final Map<String, dynamic> map =
        convert.jsonDecode(jsonStr) as Map<String, dynamic>;
    return PuzzleSettings.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, PuzzleSettings obj) {
    writer.writeString(convert.jsonEncode(obj.toJson()));
  }
}
