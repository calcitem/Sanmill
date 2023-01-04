// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/material.dart' show Colors, Color, immutable;
import 'package:hive_flutter/adapters.dart'
    show HiveField, HiveType, BinaryReader, BinaryWriter, TypeAdapter;
import 'package:json_annotation/json_annotation.dart';

import '../services/database/adapters/adapters.dart';
import '../shared/theme/colors.dart';

part 'color_settings.g.dart';

/// Color data model
///
/// Holds the data needed for the Color Settings
@HiveType(typeId: 0)
@JsonSerializable()
@CopyWith()
@immutable
class ColorSettings {
  const ColorSettings({
    this.boardLineColor = UIColors.rosewood50,
    this.darkBackgroundColor = UIColors.spruce,
    this.boardBackgroundColor = UIColors.burlyWood,
    this.whitePieceColor = Colors.white,
    this.blackPieceColor = Colors.black,
    this.pieceHighlightColor = Colors.red,
    this.messageColor = Colors.white,
    this.drawerColor = Colors.white,
    @Deprecated("Use [drawerColor] instead.")
        this.drawerBackgroundColor = Colors.white,
    this.drawerTextColor = UIColors.mediumJungleGreen,
    this.drawerHighlightItemColor = UIColors.highlighterGreen20,
    this.mainToolbarBackgroundColor = UIColors.burlyWood,
    this.mainToolbarIconColor = UIColors.cocoaBean60,
    this.navigationToolbarBackgroundColor = UIColors.burlyWood,
    this.navigationToolbarIconColor = UIColors.cocoaBean60,
  });

  /// Encodes a Json style map Color a [ColorSettings] object
  factory ColorSettings.fromJson(Map<String, dynamic> json) =>
      _$ColorSettingsFromJson(json);

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(0)
  final Color boardLineColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(1)
  final Color darkBackgroundColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(2)
  final Color boardBackgroundColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(3)
  final Color whitePieceColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(4)
  final Color blackPieceColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(5)
  final Color pieceHighlightColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(6)
  final Color messageColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(7)
  final Color drawerColor;

  @Deprecated("Use [drawerColor] instead.")
  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(8)
  final Color drawerBackgroundColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(9)
  final Color drawerTextColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(10)
  final Color drawerHighlightItemColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(11)
  final Color mainToolbarBackgroundColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(12)
  final Color mainToolbarIconColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(13)
  final Color navigationToolbarBackgroundColor;

  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(14)
  final Color navigationToolbarIconColor;

  /// Decodes a Json from a [ColorSettings] object
  Map<String, dynamic> toJson() => _$ColorSettingsToJson(this);
}
