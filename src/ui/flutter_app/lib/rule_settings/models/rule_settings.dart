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

import 'dart:ui';

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:hive_flutter/adapters.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rule_settings.g.dart';

@HiveType(typeId: 4)
enum BoardFullAction {
  @HiveField(0)
  firstPlayerLose,
  @HiveField(1)
  firstAndSecondPlayerRemovePiece,
  @HiveField(2)
  secondAndFirstPlayerRemovePiece,
  @HiveField(3)
  sideToMoveRemovePiece,
  @HiveField(4)
  agreeToDraw,
}

@HiveType(typeId: 8)
enum StalemateAction {
  @HiveField(0)
  endWithStalemateLoss,
  @HiveField(1)
  changeSideToMove,
  @HiveField(2)
  removeOpponentsPieceAndMakeNextMove,
  @HiveField(3)
  removeOpponentsPieceAndChangeSideToMove,
  @HiveField(4)
  endWithStalemateDraw,
}

// Currently unused
String enumName(Object enumEntry) {
  final Map<Object, String> nameMap = <Object, String>{
    BoardFullAction.firstPlayerLose: "0-1",
    BoardFullAction.firstAndSecondPlayerRemovePiece: 'W->B',
    BoardFullAction.secondAndFirstPlayerRemovePiece: 'B->W',
    BoardFullAction.sideToMoveRemovePiece: 'X',
    BoardFullAction.agreeToDraw: '=',
    StalemateAction.endWithStalemateLoss: "0-1",
    StalemateAction.changeSideToMove: '->',
    StalemateAction.removeOpponentsPieceAndMakeNextMove: 'XM',
    StalemateAction.removeOpponentsPieceAndChangeSideToMove: 'X ->',
    StalemateAction.endWithStalemateDraw: '=',
  };

  return nameMap[enumEntry] ?? '';
}

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
    @Deprecated('Use [boardFullAction] instead')
    this.isWhiteLoseButNotDrawWhenBoardFull = true,
    this.boardFullAction = BoardFullAction.firstPlayerLose,
    @Deprecated('Use [StalemateAction] instead')
    this.isLoseButNotChangeSideWhenNoWay = true,
    this.stalemateAction = StalemateAction.endWithStalemateLoss,
    this.mayFly = true,
    this.nMoveRule = 100,
    this.endgameNMoveRule = 100,
    this.threefoldRepetitionRule = true,
  });

  /// Encodes a Json style map into a [RuleSettings] object
  factory RuleSettings.fromJson(Map<String, dynamic> json) =>
      _$RuleSettingsFromJson(json);

  /// Creates a Rules object based on the given locale
  factory RuleSettings.fromLocale(Locale? locale) {
    switch (locale?.languageCode) {
      case "fa": // Iran
      case "si": // Sri Lanka
        return const TwelveMensMorrisRuleSettings();
      case "ko": // Korea
        return const ChamGonuRuleSettings();
      default:
        return const RuleSettings();
    }
  }

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
  @Deprecated('Use [boardFullAction] instead')
  @HiveField(10)
  final bool isWhiteLoseButNotDrawWhenBoardFull;
  @Deprecated('Use [StalemateAction] instead')
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
  @HiveField(16, defaultValue: BoardFullAction.firstPlayerLose)
  final BoardFullAction? boardFullAction;
  @HiveField(17, defaultValue: StalemateAction.endWithStalemateLoss)
  final StalemateAction? stalemateAction;

  /// decodes a Json from a [RuleSettings] object
  Map<String, dynamic> toJson() => _$RuleSettingsToJson(this);
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

/// Cham Gonu Rules
///
/// Those rules are the Cham Gonu rules.
class ChamGonuRuleSettings extends RuleSettings {
  const ChamGonuRuleSettings()
      : super(
            piecesCount: 12,
            hasDiagonalLines: true,
            mayFly: false,
            hasBannedLocations: true,
            mayRemoveFromMillsAlways: true);
}
