// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// color_settings.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/material.dart' show Colors, Color, immutable;
import 'package:hive_ce_flutter/adapters.dart'
    show HiveField, HiveType, BinaryReader, BinaryWriter, TypeAdapter;
import 'package:json_annotation/json_annotation.dart';

import '../../shared/database/adapters/adapters.dart';
import '../../shared/themes/ui_colors.dart';

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
    this.boardLineColor = UIColors.burntSienna,
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
    this.capturablePieceHighlightColor = Colors.orange,
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

  /// Color for highlighting capturable pieces
  @JsonKey(
    fromJson: ColorAdapter.colorFromJson,
    toJson: ColorAdapter.colorToJson,
  )
  @HiveField(19, defaultValue: Colors.orange)
  final Color capturablePieceHighlightColor;

  /// Decodes a Json from a [ColorSettings] object
  Map<String, dynamic> toJson() => _$ColorSettingsToJson(this);
}
