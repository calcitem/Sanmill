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

import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sanmill/l10n/resources.dart';

part 'rules.g.dart';

/// Rules data model
///
/// holds the data needed for the Rules Settings
@HiveType(typeId: 3)
@JsonSerializable()
class Rules {
  Rules({
    int? piecesCount,
    this.flyPieceCount = 3,
    this.piecesAtLeastCount = 3,
    bool? hasDiagonalLines,
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
  }) {
    this.piecesCount =
        piecesCount ?? (specialCountryAndRegion == "Iran" ? 12 : 9);
    this.hasDiagonalLines =
        hasDiagonalLines ?? specialCountryAndRegion == "Iran";
  }

  @HiveField(0)
  late int piecesCount;
  @HiveField(1)
  int flyPieceCount;
  @HiveField(2)
  int piecesAtLeastCount;
  @HiveField(3)
  late bool hasDiagonalLines;
  @HiveField(4)
  bool hasBannedLocations;
  @HiveField(5)
  bool mayMoveInPlacingPhase;
  @HiveField(6)
  bool isDefenderMoveFirst;
  @HiveField(7)
  bool mayRemoveMultiple;
  @HiveField(8)
  bool mayRemoveFromMillsAlways;
  @HiveField(9)
  bool mayOnlyRemoveUnplacedPieceInPlacingPhase;
  @HiveField(10)
  bool isWhiteLoseButNotDrawWhenBoardFull;
  @HiveField(11)
  bool isLoseButNotChangeSideWhenNoWay;
  @HiveField(12)
  bool mayFly;
  @HiveField(13)
  int nMoveRule;
  @HiveField(14)
  int endgameNMoveRule;
  @HiveField(15)
  bool threefoldRepetitionRule;

  /// encodes a Json style map into a [Rules] obbject
  factory Rules.fromJson(Map<String, dynamic> json) => _$RulesFromJson(json);

  /// decodes a Json from a [Rules] obbject
  Map<String, dynamic> toJson() => _$RulesToJson(this);
}
