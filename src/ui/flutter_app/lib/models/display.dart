// This file is part of Sanmill.
// Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)
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

import 'dart:ui';

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/material.dart' show Locale, immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sanmill/services/storage/adapters/adapters.dart';
import 'package:sanmill/services/storage/storage.dart';

part 'display.g.dart';

/// Display data model
///
/// holds the data needed for the Display Settings
@HiveType(typeId: 1)
@JsonSerializable()
@CopyWith(generateCopyWithNull: true)
@immutable
class Display {
  const Display({
    this.languageCode,
    @Deprecated("Until other export options are implemented this setting shouldn't be used")
        this.standardNotationEnabled = true,
    this.isPieceCountInHandShown = true,
    this.isNotationsShown = false,
    this.isHistoryNavigationToolbarShown = false,
    this.boardBorderLineWidth = 2.0,
    this.boardInnerLineWidth = 2.0,
    this.pointStyle,
    @Deprecated("Use [pointStyle] instead.") this.oldPointStyle = 0,
    this.pointWidth = 10.0,
    this.pieceWidth = 0.9 / MigrationValues.pieceWidth,
    this.fontScale = 1.0,
    this.boardTop = 36.0,
    this.animationDuration = 0.0,
  });

  /// the uses locale
  @HiveField(0)
  @JsonKey(
    fromJson: LocaleAdapter.localeFromJson,
    toJson: LocaleAdapter.localeToJson,
  )
  final Locale? languageCode;

  @Deprecated(
    "Until other export options are implemented this setting shouldn't be used",
  )
  @HiveField(1)
  final bool standardNotationEnabled;

  @HiveField(2)
  final bool isPieceCountInHandShown;

  @HiveField(3)
  final bool isNotationsShown;

  @HiveField(4)
  final bool isHistoryNavigationToolbarShown;

  @HiveField(5)
  final double boardBorderLineWidth;

  @HiveField(6)
  final double boardInnerLineWidth;

  @Deprecated("Use [pointStyle] instead.")
  @HiveField(7)
  final int oldPointStyle;

  @HiveField(13)
  @JsonKey(
    fromJson: PaintingStyleAdapter.paintingStyleFromJson,
    toJson: PaintingStyleAdapter.paintingStyleToJson,
  )
  final PaintingStyle? pointStyle;

  @HiveField(8)
  final double pointWidth;

  @HiveField(9)
  final double pieceWidth;

  @HiveField(10)
  final double fontScale;

  @HiveField(11)
  final double boardTop;

  @HiveField(12)
  final double animationDuration;

  /// encodes a Json style map into a [Display] object
  factory Display.fromJson(Map<String, dynamic> json) =>
      _$DisplayFromJson(json);

  /// decodes a Json from a [Display] object
  Map<String, dynamic> toJson() => _$DisplayToJson(this);
}
