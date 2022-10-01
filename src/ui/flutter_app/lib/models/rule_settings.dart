// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rule_settings.g.dart';

/// Rule Settings data model
///
/// Holds the default rule settings for the Mill game.
/// Currently supported special rule settings include [TwelveMensMorrisRuleSettings].
/// To get the rule settings corresponding to a given local use [RuleSettings.fromLocale].
@HiveType(typeId: 3)
@JsonSerializable()
@CopyWith()
@immutable
class RuleSettings {
  const RuleSettings({
    this.piecesCount = 9,
    this.flyPieceCount = 3,
    this.piecesAtLeastCount = 3,
    this.hasDiagonalLines = false,
    this.hasBannedLocations = false,
    this.mayMoveInPlacingPhase = false,
    this.isDefenderMoveFirst = false,
    this.mayRemoveMultiple = false,
    this.mayRemoveFromMillsAlways = false,
    this.mayOnlyRemoveUnplacedPieceInPlacingPhase = false,
    this.isWhiteLoseButNotDrawWhenBoardFull = true,
    this.isLoseButNotChangeSideWhenNoWay = true,
    this.mayFly = true,
    this.nMoveRule = 100,
    this.endgameNMoveRule = 100,
    this.threefoldRepetitionRule = true,
  });

  @HiveField(0)
  final int piecesCount;
  @HiveField(1)
  final int flyPieceCount;
  @HiveField(2)
  final int piecesAtLeastCount;
  @HiveField(3)
  final bool hasDiagonalLines;
  @HiveField(4)
  final bool hasBannedLocations;
  @HiveField(5)
  final bool mayMoveInPlacingPhase;
  @HiveField(6)
  final bool isDefenderMoveFirst;
  @HiveField(7)
  final bool mayRemoveMultiple;
  @HiveField(8)
  final bool mayRemoveFromMillsAlways;
  @HiveField(9)
  final bool mayOnlyRemoveUnplacedPieceInPlacingPhase;
  @HiveField(10)
  final bool isWhiteLoseButNotDrawWhenBoardFull;
  @HiveField(11)
  final bool isLoseButNotChangeSideWhenNoWay;
  @HiveField(12)
  final bool mayFly;
  @HiveField(13)
  final int nMoveRule;
  @HiveField(14)
  final int endgameNMoveRule;
  @HiveField(15)
  final bool threefoldRepetitionRule;

  /// Encodes a Json style map into a [RuleSettings] object
  factory RuleSettings.fromJson(Map<String, dynamic> json) =>
      _$RuleSettingsFromJson(json);

  /// decodes a Json from a [RuleSettings] object
  Map<String, dynamic> toJson() => _$RuleSettingsToJson(this);

  /// Creates a Rules object based on the given locale
  factory RuleSettings.fromLocale(Locale? locale) {
    switch (locale?.languageCode) {
      case "fa":
        return const TwelveMensMorrisRuleSettings();
      default:
        return const RuleSettings();
    }
  }
}

/// Twelve Men's Morris Rules
///
/// Those rules are the standard Twelve Men's Morris rules.
class TwelveMensMorrisRuleSettings extends RuleSettings {
  const TwelveMensMorrisRuleSettings()
      : super(
          piecesCount: 12,
          hasDiagonalLines: true,
        );
}
