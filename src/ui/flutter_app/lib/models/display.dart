/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart' show Locale, immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sanmill/services/storage/adapters/locale_adapter.dart';
import 'package:sanmill/shared/constants.dart';

part 'display.g.dart';

/// Display data model
///
/// holds the data needed for the Display Settings
@HiveType(typeId: 1)
@JsonSerializable()
@immutable
class Display {
  Display({
    this.languageCode = Constants.defaultLocale,
    this.standardNotationEnabled = true,
    this.isPieceCountInHandShown = true,
    this.isNotationsShown = false,
    this.isHistoryNavigationToolbarShown = false,
    this.boardBorderLineWidth = 2.0,
    this.boardInnerLineWidth = 2.0,
    this.pointStyle = 0,
    this.pointWidth = 10.0,
    this.pieceWidth = 0.9,
    this.fontSize = 16.0,
    double? boardTop,
    this.animationDuration = 0.0,
  }) {
    this.boardTop = boardTop ?? (isLargeScreen ? 75.0 : 36.0);
  }

  /// the uses locale
  @HiveField(0)
  @JsonKey(
    fromJson: LocaleAdapter.colorFromJson,
    toJson: LocaleAdapter.colorToJson,
  )
  final Locale languageCode;

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

  @HiveField(7)
  final int pointStyle;

  @HiveField(8)
  final double pointWidth;

  @HiveField(9)
  final double pieceWidth;

  @HiveField(10)
  final double fontSize;

  @HiveField(11)
  late final double boardTop;

  @HiveField(12)
  final double animationDuration;

  /// returns a modified copy of the [Display] object
  Display copyWith({
    Locale? languageCode,
    bool? standardNotationEnabled,
    bool? isPieceCountInHandShown,
    bool? isNotationsShown,
    bool? isHistoryNavigationToolbarShown,
    double? boardBorderLineWidth,
    double? boardInnerLineWidth,
    int? pointStyle,
    double? pointWidth,
    double? pieceWidth,
    double? fontSize,
    double? boardTop,
    double? animationDuration,
  }) =>
      Display(
        languageCode: languageCode ?? this.languageCode,
        standardNotationEnabled:
            standardNotationEnabled ?? this.standardNotationEnabled,
        isPieceCountInHandShown:
            isPieceCountInHandShown ?? this.isPieceCountInHandShown,
        isNotationsShown: isNotationsShown ?? this.isNotationsShown,
        isHistoryNavigationToolbarShown: isHistoryNavigationToolbarShown ??
            this.isHistoryNavigationToolbarShown,
        boardBorderLineWidth: boardBorderLineWidth ?? this.boardBorderLineWidth,
        boardInnerLineWidth: boardInnerLineWidth ?? this.boardInnerLineWidth,
        pointStyle: pointStyle ?? this.pointStyle,
        pointWidth: pointWidth ?? this.pointWidth,
        pieceWidth: pieceWidth ?? this.pieceWidth,
        fontSize: fontSize ?? this.fontSize,
        boardTop: boardTop ?? this.boardTop,
        animationDuration: animationDuration ?? this.animationDuration,
      );

  /// encodes a Json style map into a [Display] obbject
  factory Display.fromJson(Map<String, dynamic> json) =>
      _$DisplayFromJson(json);

  /// decodes a Json from a [Display] obbject
  Map<String, dynamic> toJson() => _$DisplayToJson(this);
}
