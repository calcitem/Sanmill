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

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../shared/database/adapters/adapters.dart';

part 'display_settings.g.dart';

/// Strategies for painting shapes and paths on points.
@HiveType(typeId: 9)
enum PointPaintingStyle {
  @HiveField(0)
  none,
  @HiveField(1)
  fill,
  @HiveField(2)
  stroke,
}

/// Display Settings data model
///
/// Holds the data needed for the Display Settings
@HiveType(typeId: 1)
@JsonSerializable()
@CopyWith(copyWithNull: true)
@immutable
class DisplaySettings {
  const DisplaySettings({
    @Deprecated("Use [locale] instead.") this.languageCode = "Default",
    this.locale,
    this.isFullScreen = false,
    @Deprecated(
        "Until other export options are implemented this setting shouldn't be used.")
    this.standardNotationEnabled = true,
    this.isPieceCountInHandShown = true,
    this.isUnplacedAndRemovedPiecesShown = false,
    this.isNotationsShown = false,
    this.isHistoryNavigationToolbarShown = false,
    this.boardBorderLineWidth = 2.0,
    this.boardInnerLineWidth = 2.0,
    @Deprecated("Use [pointPaintingStyle] instead.") this.pointStyle = 0,
    this.pointPaintingStyle = PointPaintingStyle.none,
    this.pointWidth = 10.0,
    this.pieceWidth = 0.9,
    @Deprecated("Use [fontScale] instead.") this.fontSize = 16.0,
    this.fontScale = 1.0,
    this.boardTop = kToolbarHeight,
    this.animationDuration = 0.0,
    this.aiResponseDelayTime = 0.0,
    this.isPositionalAdvantageIndicatorShown = false,
    this.backgroundImagePath = '',
  });

  /// Encodes a Json style map into a [DisplaySettings] object
  factory DisplaySettings.fromJson(Map<String, dynamic> json) =>
      _$DisplaySettingsFromJson(json);

  @Deprecated("Use [locale] instead.")
  @HiveField(0)
  final String languageCode;

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

  @Deprecated("Use [pointPaintingStyle] instead.")
  @HiveField(7)
  final int pointStyle;

  @HiveField(8)
  final double pointWidth;

  @HiveField(9)
  final double pieceWidth;

  @Deprecated("Use [fontScale] instead.")
  @HiveField(10)
  final double fontSize;

  @HiveField(11)
  final double boardTop;

  @HiveField(12)
  final double animationDuration;

  @HiveField(13)
  @JsonKey(
    fromJson: LocaleAdapter.localeFromJson,
    toJson: LocaleAdapter.localeToJson,
  )
  final Locale? locale;

  @HiveField(14)
  final PointPaintingStyle pointPaintingStyle;

  @HiveField(15)
  final double fontScale;

  @HiveField(16, defaultValue: false)
  final bool isUnplacedAndRemovedPiecesShown;

  @HiveField(17, defaultValue: false)
  final bool isFullScreen;

  @HiveField(18, defaultValue: 0.0)
  final double aiResponseDelayTime;

  @HiveField(19, defaultValue: false)
  final bool isPositionalAdvantageIndicatorShown;

  @HiveField(20, defaultValue: '')
  final String backgroundImagePath;

  /// Decodes a Json from a [DisplaySettings] object
  Map<String, dynamic> toJson() => _$DisplaySettingsToJson(this);
}
