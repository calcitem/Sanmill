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

import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sanmill/services/language_info.dart';

part 'rules.g.dart';

/// Rules data model
///
/// holds the data needed for the Rules Settings
@HiveType(typeId: 3)
@JsonSerializable()
@immutable
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
  late final int piecesCount;
  @HiveField(1)
  final int flyPieceCount;
  @HiveField(2)
  final int piecesAtLeastCount;
  @HiveField(3)
  late final bool hasDiagonalLines;
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

  /// returns a modified copy of the [Rules] object
  Rules copyWith({
    int? piecesCount,
    int? flyPieceCount,
    int? piecesAtLeastCount,
    bool? hasDiagonalLines,
    bool? hasBannedLocations,
    bool? mayMoveInPlacingPhase,
    bool? isDefenderMoveFirst,
    bool? mayRemoveMultiple,
    bool? mayRemoveFromMillsAlways,
    bool? mayOnlyRemoveUnplacedPieceInPlacingPhase,
    bool? isWhiteLoseButNotDrawWhenBoardFull,
    bool? isLoseButNotChangeSideWhenNoWay,
    bool? mayFly,
    int? nMoveRule,
    int? endgameNMoveRule,
    bool? threefoldRepetitionRule,
  }) =>
      Rules(
        piecesCount: piecesCount ?? this.piecesCount,
        flyPieceCount: flyPieceCount ?? this.flyPieceCount,
        piecesAtLeastCount: piecesAtLeastCount ?? this.piecesAtLeastCount,
        hasDiagonalLines: hasDiagonalLines ?? this.hasDiagonalLines,
        hasBannedLocations: hasBannedLocations ?? this.hasBannedLocations,
        mayMoveInPlacingPhase:
            mayMoveInPlacingPhase ?? this.mayMoveInPlacingPhase,
        isDefenderMoveFirst: isDefenderMoveFirst ?? this.isDefenderMoveFirst,
        mayRemoveMultiple: mayRemoveMultiple ?? this.mayRemoveMultiple,
        mayRemoveFromMillsAlways:
            mayRemoveFromMillsAlways ?? this.mayRemoveFromMillsAlways,
        mayOnlyRemoveUnplacedPieceInPlacingPhase:
            mayOnlyRemoveUnplacedPieceInPlacingPhase ??
                this.mayOnlyRemoveUnplacedPieceInPlacingPhase,
        isWhiteLoseButNotDrawWhenBoardFull:
            isWhiteLoseButNotDrawWhenBoardFull ??
                this.isWhiteLoseButNotDrawWhenBoardFull,
        isLoseButNotChangeSideWhenNoWay: isLoseButNotChangeSideWhenNoWay ??
            this.isLoseButNotChangeSideWhenNoWay,
        mayFly: mayFly ?? this.mayFly,
        nMoveRule: nMoveRule ?? this.nMoveRule,
        endgameNMoveRule: endgameNMoveRule ?? this.endgameNMoveRule,
        threefoldRepetitionRule:
            threefoldRepetitionRule ?? this.threefoldRepetitionRule,
      );

  /// encodes a Json style map into a [Rules] obbject
  factory Rules.fromJson(Map<String, dynamic> json) => _$RulesFromJson(json);

  /// decodes a Json from a [Rules] obbject
  Map<String, dynamic> toJson() => _$RulesToJson(this);
}
